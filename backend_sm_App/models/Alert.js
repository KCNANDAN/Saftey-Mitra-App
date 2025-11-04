// backend_sm_App/models/Alert.js
const mongoose = require('../db');
const Schema = mongoose.Schema;

const alertSchema = new Schema({
  alertType: { type: String, default: 'SOS' }, // SOS, INFO, etc.
  msg: { type: String, required: true },
  videoUrl: { type: String, default: null },
  voiceUrl: { type: String, default: null },
  createdAt: { type: Date, default: Date.now },
  location: {
    latitude: { type: Number, required: true },
    longitude: { type: Number, required: true },
  },
  metadata: { type: Schema.Types.Mixed, default: {} }, // optional extra fields
});

alertSchema.index({ createdAt: -1 });

module.exports = mongoose.model('Alert', alertSchema);
