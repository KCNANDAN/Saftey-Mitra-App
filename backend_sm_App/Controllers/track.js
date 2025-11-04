// backend_sm_App/Controllers/track.js
/**
 * track.js
 *
 * Responsibilities:
 *  - storeCoordinates: persist incoming coordinates
 *  - saveLocation: helper used by socket event handlers to persist locations
 *  - createSession / joinSession
 *  - createOrUpdateSafeZone / getSafeZone / safeZoneBreach
 *  - findCompanion: robust companion-check endpoint returning companions'
 *      latest coordinates + metadata (lastSeen, distance from requester)
 *
 * Notes:
 *  - This file intentionally includes more verbose logging and defensive checks
 *    to make it easier to debug from mobile clients.
 *  - We accept either `session` or `code` keys for session identifiers in requests.
 */
const Breach = require('../models/Breach'); // ensure path matches your project
const alertCtrl = require('./alert'); // alert.sendSosToContacts
const Coordinate = require("../models/Coordinate");
const Session = require("../models/Session");
const crypto = require("crypto");
const SafeZone = require('../models/SafeZone'); // ensure filename case matches (SafeZone.js)
const Relationship = require('../models/Relationship'); // for permission checks
// helper: generate short hex code
function generateCode(len = 8) {
  return crypto.randomBytes(Math.ceil(len / 2)).toString("hex").slice(0, len);
}

// -------------------- STORE COORDINATES --------------------
async function storeCoordinates(req, res) {
  try {
    const { user, latitude, longitude, timestamp, session } = req.body || {};

    if (!user || latitude === undefined || longitude === undefined) {
      return res.status(400).json({ status: false, message: 'user, latitude and longitude are required' });
    }

    const coord = new Coordinate({
      user: String(user),
      latitude: Number(latitude),
      longitude: Number(longitude),
      timestamp: timestamp || new Date().toISOString(),
      session: session || null
    });

    await coord.save();

    return res.status(200).json({
      status: true,
      message: `${user} : ${latitude},${longitude} at ${coord.timestamp}`,
      id: coord._id
    });
  } catch (error) {
    console.error('storeCoordinates error', error);
    return res.status(500).json({ status: false, message: `Error saving coordinates: ${error.message}` });
  }
}

// -------------------- SOCKET SAVE LOCATION HELPER --------------------
async function saveLocation(session, user, latitude, longitude, timestamp) {
  try {
    if (!user || latitude === undefined || longitude === undefined) {
      throw new Error('user, latitude and longitude required');
    }

    const payload = {
      user: String(user),
      latitude: Number(latitude),
      longitude: Number(longitude),
      timestamp: timestamp || new Date().toISOString(),
      session: session || null
    };

    const coord = new Coordinate(payload);
    await coord.save();
    return coord._id;
  } catch (err) {
    console.error('saveLocation error', err);
    throw err;
  }
}

// -------------------- CREATE SESSION --------------------
async function createSession(req, res) {
  try {
    const { user } = req.body || {};
    if (!user) return res.status(400).json({ status: false, message: "phoneNumber (user) is required" });

    // generate unique code with retries
    let code = null;
    const maxRetries = 6;
    for (let i = 0; i < maxRetries; i++) {
      const candidate = generateCode(8);
      const exists = await Session.exists({ code: candidate });
      if (!exists) {
        code = candidate;
        break;
      }
    }
    if (!code) code = generateCode(12);

    const session = new Session({ code, users: [String(user)] });
    await session.save();

    return res.status(201).json({
      status: true,
      code,
      sessionId: session._id,
      message: `Session created with code ${code}`
    });
  } catch (error) {
    console.error('createSession error', error);
    return res.status(500).json({ status: false, message: `Error creating session: ${error.message}` });
  }
}

// -------------------- JOIN SESSION --------------------
async function joinSession(req, res) {
  try {
    const { user, code } = req.body || {};
    if (!user || !code) return res.status(400).json({ status: false, message: "Please enter session code and phone number" });

    const session = await Session.findOne({ code }).exec();
    if (!session) return res.status(404).json({ status: false, message: "This session does not exist, enter a valid session code" });

    if (!session.users.includes(String(user))) {
      session.users.push(String(user));
      await session.save();
    }

    return res.status(200).json({ status: true, message: `You have successfully joined ${code}`, code });
  } catch (error) {
    console.error('joinSession error', error);
    return res.status(500).json({ status: false, message: `Error joining session: ${error.message}` });
  }
}

// -------------------- SAFE ZONE --------------------
// createOrUpdateSafeZone with actor permission enforcement
// -------------------- SAFE ZONE -------------------

/**
 * Create or update a SafeZone for `user` or `session`.
 * Expects body: { user, session?, latitude, longitude, radiusMeters, actor? }
 * Permission: actor === user OR actor has an accepted relationship with user and grants.editSafeZone === true
 */
async function createOrUpdateSafeZone(req, res) {
  try {
    const { user, session, latitude, longitude, radiusMeters, actor } = req.body || {};
    if (!user || latitude === undefined || longitude === undefined || radiusMeters === undefined) {
      return res.status(400).json({ status: false, message: 'user, latitude, longitude and radiusMeters are required' });
    }

    // permission check: owner always allowed
    if (actor && String(actor) === String(user)) {
      // allowed
    } else if (actor) {
      // check relationships for actor <-> user link with editSafeZone grant
      try {
        const rel = await Relationship.findOne({
          $or: [
            { from: String(actor), to: String(user), status: 'accepted' },
            { from: String(user), to: String(actor), status: 'accepted' }
          ],
          // also ensure grants.editSafeZone === true in doc
          'grants.editSafeZone': true
        }).lean().exec();

        if (!rel) {
          return res.status(403).json({ status: false, message: 'actor not allowed to edit safe zone for this user' });
        }
        // else allowed
      } catch (relErr) {
        console.error('createOrUpdateSafeZone relationship check error', relErr);
        return res.status(500).json({ status: false, message: 'server error checking relationship' });
      }
    } else {
      // no actor provided -> reject (client must send actor)
      return res.status(403).json({ status: false, message: 'actor required to modify safe zone' });
    }

    // Upsert zone
    const query = session ? { session } : { user: String(user) };
    let zone = await SafeZone.findOne(query).exec();
    if (zone) {
      zone.latitude = Number(latitude);
      zone.longitude = Number(longitude);
      zone.radiusMeters = Number(radiusMeters);
      await zone.save();
    } else {
      zone = new SafeZone({
        session: session || null,
        user: String(user),
        latitude: Number(latitude),
        longitude: Number(longitude),
        radiusMeters: Number(radiusMeters)
      });
      await zone.save();
    }

    return res.json({ status: true, message: 'safe zone saved', zone });
  } catch (err) {
    console.error('createOrUpdateSafeZone error', err);
    return res.status(500).json({ status: false, message: 'server error' });
  }
}



async function getSafeZone(req, res) {
  try {
    const session = req.params.session || null;
    const user = req.query.user || null;

    let zone = null;
    if (session) zone = await SafeZone.findOne({ session }).lean().exec();
    else if (user) zone = await SafeZone.findOne({ user }).lean().exec();

    if (!zone) return res.json({ status: true, message: 'no safe zone', zone: null });
    return res.json({ status: true, zone });
  } catch (err) {
    console.error('getSafeZone error', err);
    return res.status(500).json({ status: false, message: 'server error' });
  }
}

async function safeZoneBreach(req, res) {
  try {
    const { user, session, latitude, longitude, timestamp } = req.body || {};
    if (!user || !session) {
      return res.status(400).json({ status: false, message: 'user and session required' });
    }

    const payload = {
      user: String(user),
      session: String(session),
      latitude: (latitude !== undefined && latitude !== null) ? Number(latitude) : null,
      longitude: (longitude !== undefined && longitude !== null) ? Number(longitude) : null,
      timestamp: timestamp || new Date().toISOString(),
      type: 'exit'
    };

    // 1) persist breach record
    try {
      const breachDoc = new Breach({
        user: payload.user,
        session: payload.session,
        latitude: payload.latitude,
        longitude: payload.longitude,
        timestamp: payload.timestamp,
        type: payload.type,
        notified: false
      });
      const saved = await breachDoc.save();
      payload.breachId = saved._id ? saved._id.toString() : null;
      console.log('Saved breach record id=', payload.breachId);
    } catch (saveErr) {
      console.error('Failed to save breach record:', saveErr);
      // continue — do not fail the whole request
    }

    // 2) broadcast to session via sockets (if available)
    try {
      if (global.io && session) {
        global.io.to(session).emit('safezone_breach', payload);
        console.log('Broadcasted safezone_breach to session', session, payload);
      } else {
        console.warn('No global.io or no session for safeZoneBreach');
      }
    } catch (bErr) {
      console.error('Broadcast safezone_breach error', bErr);
    }

    // 3) attempt to notify contacts (best-effort)
    try {
      // create a friendly message and call helper that is resilient if Twilio not configured
      const message = `Auto-alert: ${user} breached safe zone at ${payload.latitude},${payload.longitude} (session ${session}).`;
      const notifyResult = await alertCtrl.sendSosToContacts({
        user: payload.user,
        latitude: payload.latitude,
        longitude: payload.longitude,
        msg: message,
      });

      console.log('safeZoneBreach: notifyResult=', notifyResult);
      // if notify succeeded, mark Breach.notified true (best-effort)
      if (notifyResult && notifyResult.ok && payload.breachId) {
        try {
          await Breach.updateOne({ _id: payload.breachId }, { $set: { notified: true } }).exec();
        } catch (uErr) {
          console.warn('Failed to mark breach as notified:', uErr);
        }
      }
    } catch (notifyErr) {
      console.error('safeZoneBreach notify error:', notifyErr);
    }

    return res.json({ status: true, message: 'breach processed', payload });
  } catch (err) {
    console.error('safeZoneBreach error', err);
    return res.status(500).json({ status: false, message: 'server error' });
  }
}


// -------------------- FIND COMPANION / COMPANION CHECK --------------------
/**
 * POST /find-companion
 * Accepts body:
 *  - { user | username, session | sessionCode | code, latitude?, longitude? }
 *
 * Response:
 *  {
 *    status: true,
 *    message: 'companions fetched',
 *    companions: [
 *      { user: '9999', latitude: 12.3, longitude: 77.3, lastSeen: 'ISO', hasLocation: true, distanceMeters: 120.5 },
 *      { user: 'xxxx', latitude: null, longitude: null, lastSeen: null, hasLocation: false, distanceMeters: null },
 *      ...
 *    ]
 *  }
 *
 * Behavior:
 *  - Validate requester & session
 *  - Return all other session.users except requester
 *  - For each companion, attempt to find latest Coordinate with session filter first,
 *    then without session as fallback. If no coordinate -> nulls.
 *  - If requester provided lat/lng we compute distanceMeters for each companion.
 */
async function findCompanion(req, res) {
  try {
    const body = req.body || {};
    const requester = body.user || body.username || null;
    const sessionVal = body.session || body.sessionCode || body.code || null;

    if (!requester || !sessionVal) {
      return res.status(400).json({
        status: false,
        message: 'Please provide your user (user/username) and session code (session/sessionCode/code) in request body.'
      });
    }

    // optional requester coords for distance calculation
    const requesterLat = (body.latitude !== undefined && body.latitude !== null) ? Number(body.latitude) : null;
    const requesterLng = (body.longitude !== undefined && body.longitude !== null) ? Number(body.longitude) : null;

    // fetch session and list of companions
    const session = await Session.findOne({ code: sessionVal }).lean().exec();
    if (!session) {
      return res.status(404).json({ status: false, message: 'Session not found' });
    }

    const companionsList = session.users.filter(u => String(u) !== String(requester));
    // prepare results
    const results = [];

    // helper to compute Haversine distance in meters
    const toRad = (v) => v * Math.PI / 180;
    const haversine = (lat1, lon1, lat2, lon2) => {
      const R = 6371000; // meters
      const dLat = toRad(lat2 - lat1);
      const dLon = toRad(lon2 - lon1);
      const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
                Math.sin(dLon/2) * Math.sin(dLon/2);
      const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
      return R * c;
    };

    for (const comp of companionsList) {
      try {
        // 1) try latest coordinate scoped to session (if present)
        let latest = null;
        if (sessionVal) {
          latest = await Coordinate.findOne({ user: comp, session: sessionVal })
            .sort({ timestamp: -1, _id: -1 })
            .lean()
            .exec();
        }
        // 2) fallback: latest coordinate globally
        if (!latest) {
          latest = await Coordinate.findOne({ user: comp })
            .sort({ timestamp: -1, _id: -1 })
            .lean()
            .exec();
        }

        if (latest) {
          const lat = (latest.latitude !== undefined && latest.latitude !== null) ? Number(latest.latitude) : null;
          const lng = (latest.longitude !== undefined && latest.longitude !== null) ? Number(latest.longitude) : null;
          const lastSeen = latest.timestamp || latest.createdAt || new Date().toISOString();

          let distanceMeters = null;
          if (requesterLat !== null && requesterLng !== null && lat !== null && lng !== null) {
            try {
              distanceMeters = haversine(requesterLat, requesterLng, lat, lng);
            } catch (dErr) {
              distanceMeters = null;
            }
          }

          results.push({
            user: comp,
            latitude: lat,
            longitude: lng,
            lastSeen: lastSeen,
            hasLocation: (lat !== null && lng !== null),
            distanceMeters: distanceMeters
          });
        } else {
          // no coordinates known
          results.push({
            user: comp,
            latitude: null,
            longitude: null,
            lastSeen: null,
            hasLocation: false,
            distanceMeters: null
          });
        }
      } catch (innerErr) {
        console.error('findCompanion per-companion error', innerErr);
        results.push({
          user: comp,
          latitude: null,
          longitude: null,
          lastSeen: null,
          hasLocation: false,
          distanceMeters: null
        });
      }
    }

    return res.json({ status: true, message: 'companions fetched', companions: results });
  } catch (err) {
    console.error('findCompanion error', err);
    return res.status(500).json({ status: false, message: `Error finding companions: ${err.message}` });
  }
}

// -------------------- BREACH HISTORY (GET) --------------------
/**
 * GET /safe-zone/breaches?session=<code>&user=<phone>&limit=20&page=0
 * Returns recent breaches matching filters.
 */
async function getBreaches(req, res) {
  try {
    const session = req.query.session || null;
    const user = req.query.user || null;
    const limit = Math.min(100, parseInt(req.query.limit || '20', 10) || 20);
    const page = Math.max(0, parseInt(req.query.page || '0', 10) || 0);

    const q = {};
    if (session) q.session = session;
    if (user) q.user = user;

    const docs = await Breach.find(q)
      .sort({ createdAt: -1 })
      .skip(page * limit)
      .limit(limit)
      .lean()
      .exec();

    return res.json({ status: true, breaches: docs, count: docs.length });
  } catch (err) {
    console.error('getBreaches error', err);
    return res.status(500).json({ status: false, message: 'server error' });
  }
}

// -------------------- EXPORTS --------------------
module.exports = {
  storeCoordinates,
  saveLocation,
  createSession,
  joinSession,
  findCompanion,
  createOrUpdateSafeZone,
  getSafeZone,
  safeZoneBreach,
  getBreaches,
};
