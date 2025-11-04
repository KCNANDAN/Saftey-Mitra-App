// lib/screens/manage_family_page.dart
import 'package:flutter/material.dart';
import 'package:frontend/utils/api_requests.dart';
import 'package:frontend/utils/user_prefs.dart';
import 'package:frontend/widgets/relationship_tile.dart';

class ManageFamilyPage extends StatefulWidget {
  const ManageFamilyPage({super.key});

  @override
  State<ManageFamilyPage> createState() => _ManageFamilyPageState();
}

class _ManageFamilyPageState extends State<ManageFamilyPage> {
  final TextEditingController _toCtrl = TextEditingController();
  String _myPhone = '';
  List<dynamic> _rels = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _myPhone = UserPrefs.userPhone ?? '';
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final resp = await listRelationships(_myPhone);
      if (resp is Map &&
          resp['status'] == true &&
          resp['relationships'] != null) {
        setState(() => _rels = resp['relationships']);
      } else {
        setState(() => _rels = []);
      }
    } catch (e) {
      debugPrint('manage_family fetch error: $e');
      setState(() => _rels = []);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _invite() async {
    final to = _toCtrl.text.trim();
    if (to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter phone of person to invite')));
      return;
    }
    try {
      final grants = {
        'editSafeZone': true,
        'viewLocation': true,
        'receiveAlerts': true,
        'sosOnBreach': false,
      };
      final resp = await requestRelationship(
          from: _myPhone, to: to, type: 'guardian', grants: grants);
      if (resp is Map && resp['status'] == true) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Request sent')));
        _toCtrl.clear();
        await _fetch();
      } else {
        final msg = (resp is Map && resp['message'] != null)
            ? resp['message']
            : 'Failed';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg.toString())));
      }
    } catch (e) {
      debugPrint('invite error: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Invite failed: $e')));
    }
  }

  Future<void> _acceptRel(String id) async {
    try {
      final resp =
          await respondRelationship(relId: id, to: _myPhone, action: 'accept');
      if (resp is Map && resp['status'] == true) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Accepted')));
        await _fetch();
      }
    } catch (e) {
      debugPrint('_acceptRel error: $e');
    }
  }

  Future<void> _rejectRel(String id) async {
    try {
      final resp =
          await respondRelationship(relId: id, to: _myPhone, action: 'reject');
      if (resp is Map && resp['status'] == true) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Rejected')));
        await _fetch();
      }
    } catch (e) {
      debugPrint('_rejectRel error: $e');
    }
  }

  Future<void> _deleteRel(String id) async {
    try {
      final resp = await deleteRelationship(id, actor: _myPhone);
      if (resp is Map && resp['status'] == true) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Removed')));
        await _fetch();
      }
    } catch (e) {
      debugPrint('_deleteRel error: $e');
    }
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Family / Guardians'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _toCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      hintText: 'Phone to invite (e.g. 98765...)'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _invite, child: const Text('Invite'))
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rels.isEmpty
                      ? const Center(child: Text('No relationships yet'))
                      : RefreshIndicator(
                          onRefresh: _fetch,
                          child: ListView.builder(
                            itemCount: _rels.length,
                            itemBuilder: (ctx, i) {
                              final r = _rels[i];
                              return RelationshipTile(
                                rel: Map<String, dynamic>.from(r),
                                onAccept: r['status'] == 'pending' &&
                                        r['to'] == _myPhone
                                    ? () => _acceptRel(r['_id'] ?? r['id'])
                                    : null,
                                onReject: r['status'] == 'pending' &&
                                        r['to'] == _myPhone
                                    ? () => _rejectRel(r['_id'] ?? r['id'])
                                    : null,
                                onDelete: () => _deleteRel(r['_id'] ?? r['id']),
                              );
                            },
                          ),
                        ),
            ),
          ]),
        ),
      ),
    );
  }
}
