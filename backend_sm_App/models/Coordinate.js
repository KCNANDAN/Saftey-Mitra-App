// backend_sm_App/models/Coordinate.js
const mongoose = require('../db'); // <- single import from db.js
const Schema = mongoose.Schema;

const coordinateSchema = new Schema({
  user: { type: String, required: true },
  latitude: { type: Number, required: true },
  longitude: { type: Number, required: true },
  timestamp: { type: String },
  session: { type: String },
});

module.exports = mongoose.model('Coordinate', coordinateSchema);
