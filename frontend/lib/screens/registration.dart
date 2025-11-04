// lib/screens/registration.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:frontend/utils/api_requests.dart'; // signIn/signUp + ApiException
import 'package:frontend/utils/user_prefs.dart';
import 'package:frontend/screens/signin_otp_page.dart'; // <-- added

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  _RegistrationScreenState createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late TextEditingController _phoneController;
  late TextEditingController _pinController;

  final String _pinForUser = "";
  final bool _isPinScreen = false;
  bool _isPinResendAvailable = false;
  Timer? _timer;
  int _resendCounter = 30;

  bool _isLoading = false;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _phoneController = TextEditingController(text: UserPrefs.userPhone ?? '');
    _pinController = TextEditingController();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  bool _validPhone(String v) => RegExp(r'^\d{8,13}$').hasMatch(v.trim());
  bool _validPin(String v) => RegExp(r'^\d{4,6}$').hasMatch(v.trim());

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _setLoading(bool v) {
    if (!mounted) return;
    setState(() {
      _isLoading = v;
      if (v) _inlineError = null;
    });
  }

  // ---------- CHANGED: navigate to OTP flow instead of switching to local PIN UI ----------
  void _sendPin() {
    final phone = _phoneController.text.trim();
    final pin = _pinController.text.trim();

    if (!_validPhone(phone)) {
      setState(
          () => _inlineError = 'Enter a valid phone number (8–13 digits).');
      _showSnack('Please enter a valid phone number.');
      return;
    }
    if (!_validPin(pin)) {
      setState(() => _inlineError = 'Enter a valid PIN (4–6 digits).');
      _showSnack('Please enter a valid PIN (4–6 digits).');
      return;
    }

    // Navigate to OTP page and prefill phone + pin (OTP flow will request OTP automatically)
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SignInOtpPage(initialPhone: phone, initialPin: pin),
      ),
    );
  }
  // -------------------------------------------------------------------------

  void _startResendTimer() {
    _timer?.cancel();
    setState(() {
      _resendCounter = 30;
      _isPinResendAvailable = false;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendCounter == 0) {
        setState(() => _isPinResendAvailable = true);
        t.cancel();
      } else {
        setState(() => _resendCounter--);
      }
    });
  }

  void _resendPin() {
    _startResendTimer();
    _showSnack('PIN prompt resent (UI only).');
  }

  Future<void> _verifyPin() async {
    final pin = _pinController.text;
    if (!_validPin(pin)) {
      setState(() => _inlineError = 'Enter a valid PIN (4–6 digits).');
      _showSnack('Please enter a valid PIN (4–6 digits).');
      return;
    }

    _setLoading(true);
    try {
      // Try sign in
      await signIn(_pinForUser, pin);

      // persist phone and token
      await UserPrefs.setUserPhone(_pinForUser);
      await UserPrefs.setToken(_pinForUser); // fallback token = phone
      debugPrint('[USERPREFS] saved phone: ${UserPrefs.userPhone}');

      if (!mounted) return;
      _showSnack('Signed in successfully.');
      Navigator.pushReplacementNamed(context, '/home');
      return;
    } on ApiException catch (e) {
      final msg = e.message.toLowerCase();
      final status = e.statusCode ?? 0;
      final fallback = status == 401 ||
          status == 404 ||
          msg.contains('not found') ||
          msg.contains('invalid');
      if (!fallback) {
        if (!mounted) return;
        setState(() => _inlineError = e.message);
        _showSnack(e.message);
        _setLoading(false);
        return;
      }
      // else: sign up below
    } catch (_) {
      if (!mounted) return;
      setState(() => _inlineError = 'Could not sign in. Please try again.');
      _showSnack('Could not sign in. Please try again.');
      _setLoading(false);
      return;
    }

    try {
      // Sign up + sign in
      await signUp(_pinForUser, pin);
      await signIn(_pinForUser, pin);

      // persist phone and token
      await UserPrefs.setUserPhone(_pinForUser);
      await UserPrefs.setToken(_pinForUser); // fallback token = phone
      debugPrint('[USERPREFS] saved phone: ${UserPrefs.userPhone}');

      if (!mounted) return;
      _showSnack('Account created & signed in.');
      Navigator.pushReplacementNamed(context, '/home');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _inlineError = e.message);
      _showSnack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _inlineError = 'Sign up failed. Please try again.');
      _showSnack('Sign up failed. Please try again.');
    } finally {
      _setLoading(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0),
      end: const Offset(0.0, -0.15),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.fastOutSlowIn,
    ));

    final title = _isPinScreen ? 'Enter PIN' : 'Phone Registration';

    return Scaffold(
      body: Stack(
        children: [
          SlideTransition(
            position: slideAnimation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height / 8),
                    Text(title,
                        style: const TextStyle(
                            fontSize: 28.0, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    if (_inlineError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _inlineError!,
                          style: const TextStyle(
                              color: Colors.red, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 24),
                    if (!_isPinScreen) ...[
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: InputDecoration(
                          labelText: "Enter Phone Number",
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _sendPin,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 48.0, vertical: 16.0),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(38.0)),
                          backgroundColor: const Color(0xff132137),
                        ),
                        child: const Text("Continue",
                            style:
                                TextStyle(fontSize: 18, color: Colors.white)),
                      ),
                    ] else ...[
                      Text("PIN for $_pinForUser",
                          style: const TextStyle(
                              fontSize: 18.0, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _pinController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: InputDecoration(
                          labelText: "Enter PIN (4–6 digits)",
                          counterText: "",
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0)),
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _verifyPin,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 48.0, vertical: 16.0),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(38.0)),
                          backgroundColor: const Color(0xff132137),
                        ),
                        child: const Text("Verify",
                            style:
                                TextStyle(fontSize: 18, color: Colors.white)),
                      ),
                      const SizedBox(height: 16),
                      if (_isPinResendAvailable)
                        InkWell(
                          onTap: _isLoading ? null : _resendPin,
                          child: const Text("Resend",
                              style: TextStyle(
                                  fontSize: 16.0,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold)),
                        )
                      else
                        Text("Resend available in $_resendCounter seconds",
                            style: const TextStyle(
                                fontSize: 16.0, color: Colors.grey)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
