// Controllers/auth.js
const User = require("../models/User");
const bcrypt = require("bcryptjs");
const crypto = require("crypto");
const jwt = require("jsonwebtoken");

// In-memory OTP store for dev. For production use Redis or DB with TTL.
const _otpStore = new Map();

function normalizeUser(user) {
  if (!user) return user;
  return user.toString().trim();
}

// Helper: try to send SMS via global.twilioClient if available.
// Returns true if an attempt was made successfully, false otherwise.
async function sendOtpSms(phone, otp) {
  try {
    if (global.twilioClient && typeof global.twilioClient.messages.create === "function" && process.env.TWILIO_PHONE_NUMBER) {
      await global.twilioClient.messages.create({
        body: `Your SafetyMitra OTP is ${otp}. It is valid for 5 minutes.`,
        from: process.env.TWILIO_PHONE_NUMBER,
        to: phone,
      });
      return true;
    } else {
      // Twilio not configured
      return false;
    }
  } catch (err) {
    console.error("sendOtpSms error", err);
    return false;
  }
}

// ------------------ Existing endpoints ------------------

// Sign in (legacy)
module.exports.signin = async (req, res) => {
  const user = normalizeUser(req.body.user);
  const smPIN = req.body.smPIN;

  if (!user || !smPIN) {
    return res.status(400).json({ status: false, message: "user and smPIN are required" });
  }

  try {
    const foundUser = await User.findOne({ user }).lean();
    if (!foundUser) {
      return res.status(401).json({ status: false, message: "Invalid user or PIN" });
    }

    const match = await bcrypt.compare(smPIN, foundUser.smPIN);
    if (!match) {
      return res.status(401).json({ status: false, message: "Invalid user or PIN" });
    }

    return res.status(200).json({
      status: true,
      message: "Successfully signed in",
      user: { user: foundUser.user, id: foundUser._id },
    });
  } catch (err) {
    console.error("signin error", err);
    return res.status(500).json({ status: false, message: "Server error" });
  }
};

// Sign up
module.exports.signup = async (req, res) => {
  const user = normalizeUser(req.body.user);
  const smPIN = req.body.smPIN;

  if (!user || !smPIN) {
    return res.status(400).json({ status: false, message: "user and smPIN are required" });
  }

  try {
    const exists = await User.exists({ user });
    if (exists) {
      return res.status(409).json({ status: false, message: "User already exists" });
    }

    const hashedPIN = await bcrypt.hash(smPIN, 10);
    const newUser = new User({ user, smPIN: hashedPIN });
    await newUser.save();

    return res.status(201).json({ status: true, message: "Account created successfully", user: { user, id: newUser._id } });
  } catch (err) {
    console.error("signup error", err);
    return res.status(500).json({ status: false, message: "Error creating account" });
  }
};

// Reset PIN
module.exports.resetPIN = async (req, res) => {
  const user = normalizeUser(req.body.user);
  const smPIN = req.body.smPIN;

  if (!user || !smPIN) {
    return res.status(400).json({ status: false, message: "user and smPIN are required" });
  }

  try {
    const hashedPIN = await bcrypt.hash(smPIN, 10);
    const result = await User.updateOne({ user }, { smPIN: hashedPIN });

    const matched =
      (result && (result.matchedCount || result.n || result.nMatched || result.nModified || result.modifiedCount)) || 0;

    if (matched && matched > 0) {
      return res.status(200).json({ status: true, message: "smPIN successfully reset" });
    } else {
      // fallback: if update couldn't detect matched count (older mongoose),
      // check if user exists and treat as success if found
      const found = await User.findOne({ user }).lean();
      if (found) {
        return res.status(200).json({ status: true, message: "smPIN successfully reset" });
      } else {
        return res.status(404).json({ status: false, message: "User not found" });
      }
    }
  } catch (err) {
    console.error("resetPIN error", err);
    return res.status(500).json({ status: false, message: "Error resetting PIN" });
  }
};

// ------------------ OTP flow ------------------

/**
 * POST /signin-password
 * Body: { user: "<phone>", smPIN: "<pin>" }
 * Verifies the PIN, generates 6-digit OTP + tempId, sends SMS (if twilio configured),
 * returns { status: true, tempId, smsSent }.
 */
module.exports.signinPassword = async (req, res) => {
  const userPhone = normalizeUser(req.body.user);
  const smPIN = req.body.smPIN;
  if (!userPhone || !smPIN) {
    return res.status(400).json({ status: false, message: "user and smPIN are required" });
  }
  try {
    const foundUser = await User.findOne({ user: userPhone }).lean();
    if (!foundUser) return res.status(401).json({ status: false, message: "Invalid user or PIN" });

    const match = await bcrypt.compare(smPIN, foundUser.smPIN);
    if (!match) return res.status(401).json({ status: false, message: "Invalid user or PIN" });

    // generate OTP & tempId
    const otp = String(Math.floor(100000 + Math.random() * 900000)); // 6-digit
    const tempId = crypto.randomBytes(12).toString("hex");
    const expiresAt = Date.now() + (5 * 60 * 1000); // 5 minutes

    _otpStore.set(tempId, { phone: userPhone, otp, expiresAt });

    // DEV: print OTP to server console so you can test without Twilio
    console.log(`(DEV OTP) tempId=${tempId} phone=${userPhone} otp=${otp} expiresAt=${new Date(expiresAt).toISOString()}`);

    // attempt to send via Twilio (best-effort)
    const smsSent = await sendOtpSms(userPhone, otp);

    return res.status(200).json({
      status: true,
      message: "OTP generated",
      tempId,
      smsSent,
    });
  } catch (err) {
    console.error("signinPassword error", err);
    return res.status(500).json({ status: false, message: "Server error" });
  }
};

/**
 * POST /verify-otp
 * Body: { tempId: "<tempId>", otp: "123456" }
 * Verifies OTP, deletes temp record, returns JWT token + user info.
 */
module.exports.verifyOtp = async (req, res) => {
  const { tempId, otp } = req.body;
  if (!tempId || !otp) return res.status(400).json({ status: false, message: "tempId and otp required" });

  try {
    const rec = _otpStore.get(tempId);
    if (!rec) return res.status(400).json({ status: false, message: "Invalid or expired OTP" });

    if (Date.now() > rec.expiresAt) {
      _otpStore.delete(tempId);
      return res.status(400).json({ status: false, message: "OTP expired" });
    }

    if (rec.otp !== otp) return res.status(400).json({ status: false, message: "Invalid OTP" });

    // OTP valid — remove from store
    _otpStore.delete(tempId);

    const userPhone = rec.phone;
    const userDoc = await User.findOne({ user: userPhone }).lean();
    if (!userDoc) return res.status(404).json({ status: false, message: "User not found" });

    // generate JWT (expires in 7 days)
    const jwtSecret = process.env.JWT_SECRET || 'dev-secret-change-me';
    const token = jwt.sign({ user: userDoc.user, id: userDoc._id }, jwtSecret, { expiresIn: '7d' });

    return res.status(200).json({
      status: true,
      message: "OTP verified",
      user: { user: userDoc.user, id: userDoc._id },
      token,
    });
  } catch (err) {
    console.error("verifyOtp error", err);
    return res.status(500).json({ status: false, message: "Server error" });
  }
};
