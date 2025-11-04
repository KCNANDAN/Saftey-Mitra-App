// lib/widgets/relationship_tile.dart
import 'package:flutter/material.dart';

class RelationshipTile extends StatelessWidget {
  final Map<String, dynamic> rel;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onDelete;

  const RelationshipTile({
    super.key,
    required this.rel,
    this.onAccept,
    this.onReject,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final from = rel['from']?.toString() ?? '-';
    final to = rel['to']?.toString() ?? '-';
    final type = rel['type']?.toString() ?? '-';
    final status = rel['status']?.toString() ?? '-';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        title: Text('$type — $from → $to'),
        subtitle:
            Text('Status: $status\nGrants: ${_prettyGrants(rel['grants'])}'),
        isThreeLine: true,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (status == 'pending' && onAccept != null)
            IconButton(
                icon: const Icon(Icons.check, color: Colors.green),
                onPressed: onAccept),
          if (status == 'pending' && onReject != null)
            IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: onReject),
          if (onDelete != null)
            IconButton(
                icon: const Icon(Icons.delete_outline), onPressed: onDelete),
        ]),
      ),
    );
  }

  String _prettyGrants(dynamic g) {
    if (g == null) return '—';
    try {
      final m = Map<String, dynamic>.from(g);
      final keys = m.keys.where((k) => k != 'expiresAt').toList();
      final enabled = keys.where((k) => m[k] == true).toList();
      return enabled.isEmpty ? 'none' : enabled.join(', ');
    } catch (_) {
      return '-';
    }
  }
}
