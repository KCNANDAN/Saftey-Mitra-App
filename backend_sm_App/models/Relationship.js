// backend_sm_App/models/Relationship.js
const mongoose = require('../db');
const Schema = mongoose.Schema;

const relationshipSchema = new Schema({
  from: { type: String, required: true },      // requester / role-holder (guardian/spouse etc.)
  to: { type: String, required: true },        // target (dependent)
  type: { type: String, required: true },      // guardian | spouse | parent | child | friend
  directional: { type: Boolean, default: true },// guardian/parent are directional; spouse false
  status: { type: String, default: 'pending' },// pending | accepted | rejected | revoked
  grants: {
    editSafeZone: { type: Boolean, default: false },
    viewLocation: { type: Boolean, default: false },
    receiveAlerts: { type: Boolean, default: false },
    sosOnBreach: { type: Boolean, default: false },
    expiresAt: { type: String, default: null },
  },
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now },
  createdBy: { type: String }, // who initiated (redundant w/from but handy)
});

relationshipSchema.pre('save', function (next) {
  this.updatedAt = Date.now();
  next();
});

// indexes for quick lookup
relationshipSchema.index({ to: 1 });
relationshipSchema.index({ from: 1 });
relationshipSchema.index({ status: 1 });

module.exports = mongoose.model('Relationship', relationshipSchema);
