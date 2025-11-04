// backend_sm_App/utils/permissions.js
//
// Small permission utility used by controllers to centralize checks.
// Exports: canActOn(actor, action, target) -> Promise<boolean>
//
const Relationship = require('../models/Relationship');

/**
 * canActOn(actor, action, target)
 * - actor: string (phone or user id) performing the action
 * - action: 'editSafeZone' | 'viewLocation' | 'receiveAlerts' | 'sosOnBreach'
 * - target: string (phone or user id) the actor wants to act upon
 *
 * Behavior:
 *  - returns true if actor === target
 *  - queries accepted relationships where (from=actor,to=target) OR (directional=false and both directions accepted)
 *  - returns true if any matching relationship grants the requested action
 */
async function canActOn(actor, action, target) {
  try {
    if (!actor || !target) return false;
    if (actor === target) return true;

    // find accepted relationships where actor->target
    const rels = await Relationship.find({
      $or: [{ from: actor, to: target }, { from: target, to: actor }],
      status: 'accepted'
    }).lean().exec();

    if (!rels || rels.length === 0) return false;

    // check direct actor->target first
    for (const r of rels) {
      if (r.from === actor && r.to === target) {
        if (r.grants && r.grants[action]) return true;
        // if relationship is non-directional (spouse), fall through to check mirrored
      }
    }

    // also accept non-directional relationships where both sides accepted and grants allow
    for (const r of rels) {
      if (r.directional === false && r.grants && r.grants[action]) return true;
    }

    // If actor is the 'to' side and relationship is non-directional, allow if grants permit
    for (const r of rels) {
      if (r.to === actor && r.from === target && r.directional === false && r.grants && r.grants[action]) return true;
    }

    return false;
  } catch (e) {
    console.error('canActOn error', e);
    return false;
  }
}

module.exports = { canActOn };
