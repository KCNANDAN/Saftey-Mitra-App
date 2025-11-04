// lib/screens/contacts_page.dart
import 'package:flutter/material.dart';
import 'package:frontend/utils/api_requests.dart';
import 'package:frontend/utils/user_prefs.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  _EmergencyContactsScreenState createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  // Keep name/number/relation locally for UI. Backend currently stores only numbers.
  final List<Map<String, String>> contacts = [];

  final _nameController = TextEditingController();
  final _numberController = TextEditingController();
  final _relationController = TextEditingController();

  String? _userPhone; // from prefs
  bool _loading = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _userPhone = UserPrefs.userPhone;
    debugPrint('[CONTACTS] init - cached userPhone=$_userPhone');
    _loadContactsFromServer();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _relationController.dispose();
    super.dispose();
  }

  Future<void> _loadContactsFromServer() async {
    final phone = _userPhone;
    debugPrint(
        '[CONTACTS] _loadContactsFromServer called with userPhone=$phone');
    if (phone == null || phone.isEmpty) {
      debugPrint('[CONTACTS] no userPhone found, skipping load');
      return;
    }
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final remote = await getEmergencyContacts(phone);
      debugPrint('[CONTACTS] server returned ${remote.runtimeType} : $remote');

      final mapped = remote
          .map((n) => <String, String>{'name': n, 'number': n, 'relation': ''})
          .toList();

      if (!mounted) return;
      setState(() {
        contacts.clear();
        contacts.addAll(mapped);
      });

      debugPrint('[CONTACTS] loaded ${contacts.length} contacts from server');
    } catch (e) {
      debugPrint('[CONTACTS] load error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load contacts: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openAddContactSheet() {
    _nameController.clear();
    _numberController.clear();
    _relationController.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        final bottom = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add New Contact',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800])),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _numberController,
                  decoration: const InputDecoration(labelText: 'Phone Number'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _relationController,
                  decoration: const InputDecoration(labelText: 'Relation'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _adding
                        ? null
                        : () async {
                            final name = _nameController.text.trim();
                            final number = _numberController.text.trim();
                            final relation = _relationController.text.trim();

                            if ((_userPhone ?? '').isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text("No logged-in user found.")),
                              );
                              return;
                            }
                            if (number.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text("Enter a phone number")),
                              );
                              return;
                            }

                            // update sheet UI immediately
                            setSheetState(() => _adding = true);
                            setState(() => _adding = true);

                            try {
                              debugPrint(
                                  '[CONTACTS] adding contact $number for user=$_userPhone');

                              // Call API (api_requests.addEmergencyContact)
                              await addEmergencyContact(_userPhone!, number);

                              // Add to local list for immediate UX
                              if (mounted) {
                                setState(() {
                                  contacts.add({
                                    'name': name.isNotEmpty ? name : number,
                                    'number': number,
                                    'relation': relation
                                  });
                                });
                              }

                              Navigator.pop(context);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text("Contact added successfully")),
                                );
                              }

                              // Refresh from server to ensure canonical state
                              await _loadContactsFromServer();
                            } catch (e) {
                              debugPrint('[CONTACTS] add error: $e');
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("Error: $e")),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setSheetState(() => _adding = false);
                                setState(() => _adding = false);
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[800]),
                    child: _adding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Center(child: Text('Add Contact')),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _editContact(int index) {
    _nameController.text = contacts[index]['name'] ?? '';
    _numberController.text = contacts[index]['number'] ?? '';
    _relationController.text = contacts[index]['relation'] ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        final bottom = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Edit Contact',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800])),
                const SizedBox(height: 10),
                TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 8),
                TextField(
                  controller: _numberController,
                  decoration: const InputDecoration(labelText: 'Phone Number'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                TextField(
                    controller: _relationController,
                    decoration: const InputDecoration(labelText: 'Relation')),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        contacts[index] = {
                          'name': _nameController.text,
                          'number': _numberController.text,
                          'relation': _relationController.text,
                        };
                      });
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[800]),
                    child: const Center(child: Text('Save Changes')),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _deleteContact(int index) {
    final removed = contacts.removeAt(index);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Removed ${removed['number']} locally")),
    );
    // NOTE: backend delete not implemented.
  }

  @override
  Widget build(BuildContext context) {
    final logged = _userPhone ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.green),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              logged.isNotEmpty
                  ? 'Logged in as $logged. These contacts will be alerted in emergencies.'
                  : 'No logged-in user detected. Please sign in again.',
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      itemCount: contacts.length,
                      separatorBuilder: (context, index) =>
                          const Divider(color: Colors.grey),
                      itemBuilder: (context, index) {
                        final c = contacts[index];
                        return ListTile(
                          leading:
                              const Icon(Icons.person, color: Colors.green),
                          title: Text(c['name'] ?? c['number'] ?? '',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Phone: ${c['number'] ?? ''}'),
                              if ((c['relation'] ?? '').isNotEmpty)
                                Text('${c['relation']}')
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                  icon:
                                      Icon(Icons.edit, color: Colors.blue[800]),
                                  onPressed: () => _editContact(index)),
                              IconButton(
                                  icon: Icon(Icons.delete,
                                      color: Colors.red[800]),
                                  onPressed: () => _deleteContact(index)),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddContactSheet,
        backgroundColor: Colors.green[800],
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
