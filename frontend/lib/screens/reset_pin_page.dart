import 'package:flutter/material.dart';
import 'package:frontend/utils/api_requests.dart';
import 'package:frontend/utils/user_prefs.dart';

class ResetPinPage extends StatefulWidget {
  const ResetPinPage({super.key});

  @override
  State<ResetPinPage> createState() => _ResetPinPageState();
}

class _ResetPinPageState extends State<ResetPinPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _oldPinCtrl = TextEditingController();
  final TextEditingController _newPinCtrl = TextEditingController();
  final TextEditingController _confirmPinCtrl = TextEditingController();

  bool _isLoading = false;
  String? _inlineError;

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _validPin(String v) => RegExp(r'^\d{4,6}$').hasMatch(v.trim());

  Future<void> _submit() async {
    final phone = UserPrefs.userPhone ?? '';
    if (phone.isEmpty) {
      setState(() => _inlineError = 'No user logged in. Please sign in first.');
      _showSnack('No logged-in user found.');
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final newPin = _newPinCtrl.text.trim();
    //final oldPin = _oldPinCtrl.text.trim();    -> Not used yet

    setState(() {
      _isLoading = true;
      _inlineError = null;
    });

    try {
      // Call resetPin API (backend expects user + smPIN)
      // Implementation expectation: resetPin(username, newPin)
      await resetPin(phone, newPin);

      // Optionally re-sign-in or show success
      _showSnack('PIN updated successfully.');
      Navigator.pop(context);
    } catch (e) {
      // ApiException from api_requests.dart will come through or generic error
      setState(() => _inlineError = e.toString());
      _showSnack('Failed to reset PIN. ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _oldPinCtrl.dispose();
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset PIN'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 18),
          child: Column(
            children: [
              if (_inlineError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    _inlineError!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _oldPinCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Current PIN',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Enter current PIN';
                        }
                        if (!_validPin(v)) {
                          return 'PIN should be 4–6 digits';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _newPinCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New PIN',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Enter new PIN';
                        }
                        if (!_validPin(v)) {
                          return 'PIN should be 4–6 digits';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmPinCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm New PIN',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Confirm new PIN';
                        }
                        if (v.trim() != _newPinCtrl.text.trim()) {
                          return 'PINs do not match';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff132137),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Reset PIN',
                                style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
