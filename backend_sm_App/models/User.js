// backend_sm_App/models/User.js
const mongoose = require('../db'); // <- single import from db.js
const Schema = mongoose.Schema;

const userSchema = new Schema({
  // your existing fields, e.g.:
  user: { type: String, required: true },
  smPIN: { type: String },
  // ... rest of schema ...
});

module.exports = mongoose.model('User', userSchema);