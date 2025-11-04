// backend_sm_App/models/Breach.js
const mongoose = require('../db');
const Schema = mongoose.Schema;

const breachSchema = new Schema({
  user: { type: String, required: true },        // phone string
  session: { type: String, required: true },     // session code
  latitude: { type: Number },
  longitude: { type: Number },
  type: { type: String, default: 'exit' },       // exit / recovered / simulated / manual
  timestamp: { type: String, default: () => new Date().toISOString() },
  notified: { type: Boolean, default: false },   // whether SOS/contacts were notified
  createdAt: { type: Date, default: Date.now },
});

breachSchema.index({ session: 1, createdAt: -1 });

module.exports = mongoose.model('Breach', breachSchema);
