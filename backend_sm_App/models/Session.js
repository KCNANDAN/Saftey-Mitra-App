// Models/Session.js
const mongoose = require('../db');
const Schema = mongoose.Schema;

const sessionSchema = new Schema({
  code: { type: String, required: true },
  users: { type: [String], default: [] },
  createdAt: { type: Date, default: Date.now },
});

// TTL: keep the document for 24 hours after createdAt
// We create an index on createdAt with expireAfterSeconds to implement TTL.
sessionSchema.index({ createdAt: 1 }, { expireAfterSeconds: 24 * 60 * 60 });

// Unique index on code to enforce uniqueness at DB level
sessionSchema.index({ code: 1 }, { unique: true, background: true });

module.exports = mongoose.model('Session', sessionSchema);
