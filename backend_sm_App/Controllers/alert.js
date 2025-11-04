// backend_sm_App/Controllers/alert.js
const Contact = require("../models/Contact");
const Alert = require("../models/Alert");
const twilio = require("twilio");

const accountSid = process.env.TWILIO_ACCOUNT_SID;
const authToken = process.env.TWILIO_AUTH_TOKEN;
const userNumber = process.env.TWILIO_PHONE_NUMBER || "+1234567890"; // fallback for dev

// ✅ Safe Twilio client (only if creds exist)
let client = null;
if (accountSid && authToken) {
  try {
    client = twilio(accountSid, authToken);
    console.log("✅ Twilio client initialized");
  } catch (e) {
    console.warn("⚠️ Failed to init Twilio, SMS disabled:", e.message);
  }
} else {
  console.log("⚠️ Twilio credentials not set — SMS disabled, will still log alerts.");
}

// ================== Add Contacts ==================
module.exports.addContacts = async (req, res) => {
  const { user, contact } = req.body;

  try {
    const result = await Contact.updateOne(
      { user },
      { $addToSet: { contacts: contact } },
      { upsert: true }
    );
    res.status(200).json({
      status: true,
      message: `Contact ${contact} stored successfully`
    });
  } catch (error) {
    res.status(500).json({
      status: false,
      message: `An error occurred: ${error.message}`
    });
  }
};

// ================== Helper: sendSosToContacts ==================
/**
 * sendSosToContacts(options)
 * options = { user, latitude, longitude, msg, videoUrl, voiceUrl }
 *
 * Returns { ok: boolean, details: { storedAlertId, smsResults: [...], recipients: [...] } }
 * This function is safe to call even if Twilio credentials are not configured.
 */
module.exports.sendSosToContacts = async function (options = {}) {
  const { user, latitude, longitude, msg, videoUrl, voiceUrl } = options || {};
  if (!user || latitude === undefined || longitude === undefined || !msg) {
    return { ok: false, error: 'user, latitude, longitude and msg required' };
  }

  const details = { recipients: [], smsResults: [] };
  try {
    // fetch contacts for user
    const userContacts = await Contact.findOne({ user }).lean().exec();
    const recipientsArray = (userContacts && userContacts.contacts) ? userContacts.contacts : [];
    details.recipients = recipientsArray;

    // persist alert to DB
    const alert = new Alert({
      alertType: "SOS",
      msg,
      videoUrl,
      voiceUrl,
      location: { latitude: Number(latitude), longitude: Number(longitude) },
    });
    const saved = await alert.save();
    details.storedAlertId = saved._id ? saved._id.toString() : null;

    // attempt to send SMS via Twilio if configured (best-effort)
    if (client && Array.isArray(recipientsArray) && recipientsArray.length > 0) {
      for (let receiver of recipientsArray) {
        try {
          const sms = await client.messages.create({
            body: `${msg}\nLocation: https://maps.google.com/?q=${latitude},${longitude}`,
            from: userNumber,
            to: receiver,
          });
          details.smsResults.push({ to: receiver, sid: sms.sid, status: sms.status });
        } catch (smsError) {
          console.warn(`⚠️ Twilio send failed for ${receiver}:`, smsError && smsError.message ? smsError.message : smsError);
          details.smsResults.push({ to: receiver, error: smsError && smsError.message ? smsError.message : String(smsError) });
        }
      }
    } else {
      // Twilio not configured - return recipients
      if (!client) {
        details.notice = 'Twilio client not configured; SMS skipped.';
        console.log('🚫 Twilio disabled, skipping SMS. Alert stored only.');
      }
    }

    return { ok: true, details };
  } catch (err) {
    console.error('sendSosToContacts error', err);
    return { ok: false, error: err.message || String(err) };
  }
};

// ================== Send SOS (HTTP endpoint) ==================
// Existing endpoint kept; uses helper internally.
module.exports.sendSOS = async (req, res) => {
  const { latitude, longitude, msg, videoUrl, voiceUrl, user } = req.body;
  if (latitude === undefined || longitude === undefined || !msg || !user) {
    return res.status(400).send("Location, message, and user are required");
  }

  try {
    const result = await module.exports.sendSosToContacts({
      user,
      latitude,
      longitude,
      msg,
      videoUrl,
      voiceUrl,
    });

    if (result.ok) {
      return res.status(200).json({ status: true, message: "Alert processed", details: result.details });
    } else {
      return res.status(500).json({ status: false, message: "Failed to process alert", error: result.error });
    }
  } catch (error) {
    console.error('sendSOS endpoint error', error);
    return res.status(500).json({ status: false, message: `Error sending alert: ${error.message || error}` });
  }
};

// ================== Safety Tips ==================
const safetyTips = [
  "Always use official ride-hailing apps or registered taxis.",
  "Match the license plate and driver details before entering a cab.",
  "Share your live location with a trusted friend.",
];

module.exports.sendSafetyTip = () => {
  return safetyTips[Math.floor(Math.random() * safetyTips.length)];
};

// Get contacts for a user
module.exports.getContacts = async (req, res) => {
  const { user } = req.query;
  try {
    const doc = await Contact.findOne({ user });
    if (!doc) return res.json({ contacts: [] });
    res.json({ contacts: doc.contacts || [] });
  } catch (e) {
    res.status(500).json({ message: "Error fetching contacts: " + e.message });
  }
};
