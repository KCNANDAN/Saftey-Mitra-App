// lib/screens/relationship_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frontend/utils/api_requests.dart';
import 'package:frontend/utils/user_prefs.dart';

class RelationshipsPage extends StatefulWidget {
  const RelationshipsPage({super.key});

  @override
  State<RelationshipsPage> createState() => _RelationshipsPageState();
}

class _RelationshipsPageState extends State<RelationshipsPage> {
  List<Map<String, dynamic>> _rels = [];
  bool _loading = false;
  String? _user;

  @override
  void initState() {
    super.initState();
    _user = UserPrefs.userPhone;
    _fetch();
  }

  Future<void> _fetch() async {
    if (_user == null) return;
    setState(() => _loading = true);
    try {
      final resp = await listRelationships(_user!);
      if (resp is Map && resp['relationships'] != null) {
        final list = (resp['relationships'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        setState(() => _rels = list);
      } else {
        setState(() => _rels = []);
      }
    } catch (e) {
      debugPrint('[Rels] fetch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load relationships: $e')));
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _respond(String relId, String action) async {
    try {
      await respondRelationship(relId: relId, to: _user!, action: action);
      await _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Action failed: $e')));
      }
    }
  }

  Future<void> _delete(String relId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm delete'),
        content:
            const Text('Are you sure you want to remove this relationship?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await deleteRelationshipById(id: relId, actor: _user);
      await _fetch();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relationships'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetch,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rels.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('No relationships')),
                      ],
                    )
                  : ListView.builder(
                      itemCount: _rels.length,
                      itemBuilder: (ctx, i) {
                        final r = _rels[i];
                        final id = r['_id']?.toString() ?? '';
                        final status = r['status'] ?? 'pending';
                        return Card(
                          child: ListTile(
                            title: Text('${r['type']} - ${r['from']} → ${r['to']}'),
                            subtitle: Text('Status: $status'),
                            trailing: PopupMenuButton<String>(
                              onSelected: (action) {
                                if (action == 'accept') _respond(id, 'accept');
                                if (action == 'reject') _respond(id, 'reject');
                                if (action == 'delete') _delete(id);
                              },
                              itemBuilder: (_) => <PopupMenuEntry<String>>[
                                if (status == 'pending' && r['to'] == _user)
                                  const PopupMenuItem(
                                      value: 'accept', child: Text('Accept')),
                                if (status == 'pending' && r['to'] == _user)
                                  const PopupMenuItem(
                                      value: 'reject', child: Text('Reject')),
                                const PopupMenuItem(
                                    value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final toCtrl = TextEditingController();
          final typeCtrl = TextEditingController();
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Request Relationship'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: toCtrl,
                      decoration:
                          const InputDecoration(labelText: 'To (phone)')),
                  TextField(
                      controller: typeCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Type (guardian|friend|spouse)')),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                TextButton(
                  onPressed: () async {
                    final to = toCtrl.text.trim();
                    final type = typeCtrl.text.trim();
                    Navigator.pop(ctx);
                    try {
                      await requestRelationship(from: _user!, to: to, type: type);
                      await _fetch();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Request failed: $e')));
                      }
                    }
                  },
                  child: const Text('Send'),
                ),
              ],
            ),
          );
        },
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
