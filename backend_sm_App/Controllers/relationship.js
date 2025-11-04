// backend_sm_App/Controllers/relationship.js
const Relationship = require('../models/Relationship');

/**
 * POST /relationship/request
 * body: { from, to, type, message?, grants? }
 * Creates a pending relationship request from -> to
 */
async function requestRelationship(req, res) {
  try {
    const { from, to, type } = req.body;
    const grants = req.body.grants || {};

    if (!from || !to || !type) {
      return res.status(400).json({ status: false, message: 'from, to and type are required' });
    }
    if (from === to) {
      return res.status(400).json({ status: false, message: 'Cannot create relationship to self' });
    }

    // avoid duplicate pending or accepted entries
    const existing = await Relationship.findOne({
      from, to, type, status: { $in: ['pending', 'accepted'] }
    }).lean().exec();

    if (existing) {
      return res.status(409).json({ status: false, message: 'Relationship already requested or exists', existing });
    }

    const directionalDefault = ['guardian', 'parent', 'child', 'friend'].includes(type);

    const doc = new Relationship({
      from,
      to,
      type,
      directional: directionalDefault,
      status: 'pending',
      grants: {
        editSafeZone: !!grants.editSafeZone,
        viewLocation: !!grants.viewLocation,
        receiveAlerts: !!grants.receiveAlerts,
        sosOnBreach: !!grants.sosOnBreach,
        expiresAt: grants.expiresAt || null,
      },
      createdBy: from,
    });

    await doc.save();

    // TODO: send push/SMS to `to` about pending request (left as integration point)
    return res.status(201).json({ status: true, message: 'Relationship request created', relId: doc._id, rel: doc });
  } catch (e) {
    console.error('requestRelationship error', e);
    return res.status(500).json({ status: false, message: 'server error' });
  }
}

/**
 * POST /relationship/respond
 * body: { relId, to, action: accept|reject|revoke, grants? }
 * Only the 'to' user may accept or reject an incoming request.
 */
async function respondRelationship(req, res) {
  try {
    const { relId, to, action } = req.body;
    const grants = req.body.grants || {};

    if (!relId || !to || !action) {
      return res.status(400).json({ status: false, message: 'relId, to and action required' });
    }

    const rel = await Relationship.findById(relId).exec();
    if (!rel) return res.status(404).json({ status: false, message: 'Relationship not found' });

    if (String(rel.to) !== String(to)) {
      return res.status(403).json({ status: false, message: 'Only the recipient can respond to this request' });
    }

    if (action === 'accept') {
      rel.status = 'accepted';
      // allow the recipient to update grants at acceptance time
      rel.grants = {
        editSafeZone: !!grants.editSafeZone || !!rel.grants.editSafeZone,
        viewLocation: !!grants.viewLocation || !!rel.grants.viewLocation,
        receiveAlerts: !!grants.receiveAlerts || !!rel.grants.receiveAlerts,
        sosOnBreach: !!grants.sosOnBreach || !!rel.grants.sosOnBreach,
        expiresAt: grants.expiresAt || rel.grants.expiresAt || null
      };
      await rel.save();
      // TODO: notify `from` via push/SMS (integration point)
      return res.json({ status: true, message: 'Accepted', rel });
    } else if (action === 'reject' || action === 'revoke') {
      rel.status = action === 'reject' ? 'rejected' : 'revoked';
      await rel.save();
      return res.json({ status: true, message: `${action}ed`, rel });
    } else {
      return res.status(400).json({ status: false, message: 'Unknown action' });
    }
  } catch (e) {
    console.error('respondRelationship error', e);
    return res.status(500).json({ status: false, message: 'server error' });
  }
}

/**
 * GET /relationship/list?user=<user>
 * returns incoming & outgoing relationships for given user
 */
async function listRelationships(req, res) {
  try {
    const user = req.query.user;
    if (!user) return res.status(400).json({ status: false, message: 'user query required' });

    const rels = await Relationship.find({
      $or: [{ from: user }, { to: user }]
    }).sort({ updatedAt: -1 }).lean().exec();

    return res.json({ status: true, relationships: rels });
  } catch (e) {
    console.error('listRelationships error', e);
    return res.status(500).json({ status: false, message: 'server error' });
  }
}

/**
 * GET /relationship/for-user?user=<user>&type=<type>
 * quick fetch of relationships where to=user (useful for server-side notifications)
 */
async function getRelationshipsForUser(req, res) {
  try {
    const user = req.query.user;
    if (!user) return res.status(400).json({ status: false, message: 'user query required' });

    const rels = await Relationship.find({ to: user, status: 'accepted' }).lean().exec();
    return res.json({ status: true, relationships: rels });
  } catch (e) {
    console.error('getRelationshipsForUser error', e);
    return res.status(500).json({ status: false, message: 'server error' });
  }
}

/**
 * DELETE /relationship/:id
 * Removes a relationship (either side may call); no strict auth here — client must provide actor param (future: enforce via JWT)
 */
async function deleteRelationship(req, res) {
  try {
    const id = req.params.id;
    const actor = req.body.actor || req.query.actor || null;
    if (!id) return res.status(400).json({ status: false, message: 'id required' });

    const rel = await Relationship.findById(id).exec();
    if (!rel) return res.status(404).json({ status: false, message: 'not found' });

    // simple allow: either from or to can delete
    if (actor && (actor === rel.from || actor === rel.to)) {
      await Relationship.deleteOne({ _id: id }).exec();
      return res.json({ status: true, message: 'relationship removed' });
    } else {
      return res.status(403).json({ status: false, message: 'actor not allowed to delete this relationship' });
    }
  } catch (e) {
    console.error('deleteRelationship error', e);
    return res.status(500).json({ status: false, message: 'server error' });
  }
}

module.exports = {
  requestRelationship,
  respondRelationship,
  listRelationships,
  getRelationshipsForUser,
  deleteRelationship
};
