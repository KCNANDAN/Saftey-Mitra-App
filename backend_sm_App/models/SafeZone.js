// models/SafeZone.js
const mongoose = require('mongoose');

const SafeZoneSchema = new mongoose.Schema({
  session: { type: String, required: false }, // session code (optional)
  user: { type: String, required: true },     // owner phone
  latitude: { type: Number, required: true },
  longitude: { type: Number, required: true },
  radiusMeters: { type: Number, required: true },
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now },
});

// update updatedAt on save
SafeZoneSchema.pre('save', function(next) {
  this.updatedAt = Date.now();
  next();
});

module.exports = mongoose.model('SafeZone', SafeZoneSchema);
