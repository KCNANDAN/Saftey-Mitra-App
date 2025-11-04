// server.js
require('./db'); // Your MongoDB connection
const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const relationshipCtrl = require('./Controllers/relationship.js');

// Controllers
const auth = require('./Controllers/auth.js');
const loc = require('./Controllers/track.js');
const alr = require('./Controllers/alert.js');

console.log("auth exports:", Object.keys(auth || {}));
console.log("loc exports:", Object.keys(loc || {}));
console.log("alr exports:", Object.keys(alr || {}));

const app = express();
const server = http.createServer(app);

// Socket.IO with slightly relaxed ping settings for flaky mobile/dev networks
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  },
  pingInterval: 25000,
  pingTimeout: 60000,
  transports: ['websocket', 'polling']
});

// make io available to controllers (dev-time convenience)
global.io = io;


app.use(express.json({ limit: '2mb' })); // increase payload limit if needed
app.use(cors());

// 🔹 Log every request (helps debug from mobile)
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} ${req.method} ${req.url} body=`, req.body);
  next();
});

// Root & health routes
app.get('/', (req, res) => res.json({ message: "🚀 Safety Mitra Backend is Running!" }));
app.get('/health', (req, res) => res.json({ status: 'ok', uptime: process.uptime() }));

// ================== AUTH ROUTES ==================
// Existing legacy signin & signup
app.post('/signin', auth.signin);
app.post('/signup', auth.signup);
app.post('/reset-pin', auth.resetPIN);

// --- NEW: register OTP endpoints that exist in Controllers/auth.js ---
if (typeof auth.signinPassword === 'function') {
  app.post('/signin-password', auth.signinPassword);
  console.log('Registered route: POST /signin-password -> auth.signinPassword');
} else {
  console.warn('auth.signinPassword not found, /signin-password not registered');
}

if (typeof auth.verifyOtp === 'function') {
  app.post('/verify-otp', auth.verifyOtp);
  console.log('Registered route: POST /verify-otp -> auth.verifyOtp');
} else {
  console.warn('auth.verifyOtp not found, /verify-otp not registered');
}

// Relationship routes
app.post('/relationship/request', relationshipCtrl.requestRelationship);
app.post('/relationship/respond', relationshipCtrl.respondRelationship);
app.get('/relationship/list', relationshipCtrl.listRelationships);
app.get('/relationship/for-user', relationshipCtrl.getRelationshipsForUser);
app.delete('/relationship/:id', relationshipCtrl.deleteRelationship);


// ================== LOCATION ROUTES ==================
app.post('/store-coordinates', loc.storeCoordinates);
app.post('/create-session', loc.createSession);
app.post('/join-session', loc.joinSession);
app.post('/find-companion', loc.findCompanion);

// ================== ALERT ROUTES ==================
app.post('/add-contacts', alr.addContacts);
app.post('/send-sos', alr.sendSOS);
app.get('/contacts', alr.getContacts);

// Safety tip (GET)
app.get('/safety-tip', (req, res) => {
  try {
    const tip = alr.sendSafetyTip ? alr.sendSafetyTip() : 'Stay aware of your surroundings.';
    return res.json({ tip });
  } catch (err) {
    console.error('sendSafetyTip error', err);
    return res.status(500).json({ error: 'failed to get tip' });
  }
});

// Safe zone endpoints
app.post('/safe-zone', loc.createOrUpdateSafeZone);
app.get('/safe-zone/:session?', loc.getSafeZone); // get by session or use ?user=...
app.post('/safe-zone/breach', loc.safeZoneBreach);

// Breach history endpoint
app.get('/safe-zone/breaches', loc.getBreaches);

// ----------------- SOCKET AUTH MIDDLEWARE (proper validation) -----------------
const jwt = require('jsonwebtoken'); // add at top of server.js if not present
io.use(async (socket, next) => {
  try {
    // read token from query (old style) or handshake.auth (socket.io v3+)
    const token = (socket.handshake && (socket.handshake.query?.token || socket.handshake.auth?.token)) || null;
    console.log('Socket handshake raw token=', token);

    if (!token) {
      console.warn('Socket auth: missing token, rejecting connection');
      return next(new Error('unauthorized: missing token'));
    }

    const User = require('./models/User');
    const jwtSecret = process.env.JWT_SECRET || 'dev-secret-change-me';

    // 1) Try treat token as JWT
    try {
      const decoded = jwt.verify(token, jwtSecret);
      console.log('Socket auth: token verified as JWT, payload=', decoded);
      const username = decoded.user || decoded.username || decoded.u || null;
      if (!username) {
        console.warn('Socket auth: JWT did not contain a user field, rejecting');
        return next(new Error('unauthorized: invalid token payload'));
      }
      const found = await User.findOne({ user: String(username) }).lean().exec();
      if (!found) {
        console.warn('Socket auth: JWT user not found in DB, rejecting', username);
        return next(new Error('unauthorized: invalid token user'));
      }
      socket.authUser = { user: found.user, id: found._id.toString() };
      return next();
    } catch (jwtErr) {
      if (jwtErr && jwtErr.name !== 'JsonWebTokenError' && jwtErr.name !== 'TokenExpiredError') {
        console.warn('Socket auth: JWT verify threw non-JWT error:', jwtErr);
      } else {
        console.log('Socket auth: token is not a valid JWT (will try phone fallback). Reason:', jwtErr && jwtErr.message);
      }
    }

    // 2) Fallback: treat token value as phone string (legacy behavior)
    try {
      const foundByPhone = await User.findOne({ user: String(token) }).lean().exec();
      if (!foundByPhone) {
        console.warn('Socket auth: token did not match any user (phone fallback), rejecting', token);
        return next(new Error('unauthorized: invalid token'));
      }
      socket.authUser = { user: foundByPhone.user, id: foundByPhone._id.toString() };
      console.log('Socket auth: phone-fallback succeeded, authUser=', socket.authUser);
      return next();
    } catch (phoneErr) {
      console.error('Socket auth phone-fallback DB error', phoneErr);
      return next(new Error('unauthorized'));
    }
  } catch (err) {
    console.error('Socket auth middleware error', err);
    return next(new Error('unauthorized'));
  }
});

// ---------------------------------------------------------------------------

// ================== SOCKET.IO ==================
io.on('connection', (socket) => {
  const addr = socket.handshake.address || socket.conn?.remoteAddress || 'unknown';
  const origin = socket.handshake.headers?.origin || 'unknown-origin';
  console.log(`⚡ A user connected: ${socket.id} from ${addr} origin=${origin} authUser=${JSON.stringify(socket.authUser || {})}`);

  socket.emit('server:hello', { message: 'welcome', id: socket.id, authUser: socket.authUser || null });

  socket.on('join_session', ({ sessionCode }) => {
    try {
      if (sessionCode) {
        socket.join(sessionCode);
        console.log(`socket ${socket.id} joined room ${sessionCode}`);
      } else {
        console.log(`socket ${socket.id} sent empty sessionCode for join_session`);
      }
    } catch (err) {
      console.error('join_session error', err);
    }
  });

  socket.on('locationUpdate', async (data, ack) => {
    try {
      console.log('📍 locationUpdate from', socket.id, 'payload=', data);

      const user = (data && data.user) ? String(data.user) : (socket.authUser?.user || 'unknown');
      const lat = Number(data?.latitude || 0);
      const lng = Number(data?.longitude || 0);
      const ts = data?.timestamp || new Date().toISOString();

      if (!isFinite(lat) || !isFinite(lng)) {
        console.warn('locationUpdate - invalid coords', data);
        if (typeof ack === 'function') ack({ status: 'error', error: 'invalid_coords' });
        return;
      }

      const session = data?.session || null;
      if (session) {
        socket.to(session).emit('locationUpdate', { user, latitude: lat, longitude: lng, timestamp: ts, session });
        console.log(`Broadcasted locationUpdate to room ${session}`);
      } else {
        socket.broadcast.emit('locationUpdate', { user, latitude: lat, longitude: lng, timestamp: ts });
        console.log('Broadcasted locationUpdate to all other clients');
      }

      if (loc && typeof loc.saveLocation === 'function') {
        try {
          const savedId = await loc.saveLocation(session, user, lat, lng, ts);
          if (typeof ack === 'function') ack({ status: 'ok', ts: Date.now(), dbId: savedId ? savedId.toString() : null });
          return;
        } catch (dbErr) {
          console.error('DB save failed for locationUpdate', dbErr);
          if (typeof ack === 'function') ack({ status: 'ok', ts: Date.now(), dbError: dbErr.message || 'db_error' });
          return;
        }
      }

      if (typeof ack === 'function') {
        ack({ status: 'ok', ts: Date.now() });
      }
    } catch (err) {
      console.error('locationUpdate handler exception', err);
      if (typeof ack === 'function') ack({ status: 'error', error: err.message || 'server_error' });
    }
  });

  socket.on('disconnect', (reason) => {
    console.log('❌ A user disconnected:', socket.id, 'reason=', reason);
  });

  socket.on('error', (err) => {
    console.error('Socket error', socket.id, err);
  });
});

// ================== START SERVER ==================
const PORT = process.env.PORT || 5000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Server running on http://0.0.0.0:${PORT}`);
});
