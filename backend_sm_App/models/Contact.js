const mongoose = require('../db');
const Schema = mongoose.Schema;


const contactSchema = new mongoose.Schema({
  user: String,
  contacts: [String],
});

module.exports = mongoose.model("Contact", contactSchema);
