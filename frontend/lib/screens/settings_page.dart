import 'package:flutter/material.dart';
import 'package:frontend/screens/reset_pin_page.dart';
import 'package:frontend/utils/user_prefs.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoggingOut = false;

  void _logout() async {
    setState(() => _isLoggingOut = true);
    await UserPrefs.clearUserPhone();
    // pop until auth (or go to registration)
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final userPhone = UserPrefs.userPhone ?? 'Not signed in';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Account'),
                subtitle: Text(userPhone),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.lock_reset),
                title: const Text('Reset PIN'),
                subtitle: const Text('Change your login PIN'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ResetPinPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                subtitle: const Text('Sign out and return to login screen'),
                onTap: _isLoggingOut ? null : _logout,
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('App version: 1.0.0',
                    style: TextStyle(color: Colors.grey[700])),
              )
            ],
          ),
        ),
      ),
    );
  }
}
