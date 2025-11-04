// backend_sm_App/db.js
const mongoose = require('mongoose');
require('dotenv').config();

const uri = process.env.MONGO_URI || ''; // keep your .env value

const opts = {
  useNewUrlParser: true,
  useUnifiedTopology: true,
  serverSelectionTimeoutMS: 10000,
  // remove insecure TLS flags if you fixed TLS; add only for temporary testing:
  // tls: true,
  // tlsAllowInvalidCertificates: true,
};

mongoose.connect(uri, opts)
  .then(() => console.log('MongoDB connected'))
  .catch(err => console.error('MongoDB Connection Error:', err));

// Export the mongoose instance so models can use the same object.
module.exports = mongoose;
