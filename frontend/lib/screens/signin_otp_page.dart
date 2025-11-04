// lib/screens/signin_otp_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:frontend/utils/api_requests.dart';
import 'package:frontend/utils/user_prefs.dart';
import 'package:frontend/services/socket_service.dart';

class SignInOtpPage extends StatefulWidget {
  final String? initialPhone;
  final String? initialPin;
  const SignInOtpPage({super.key, this.initialPhone, this.initialPin});

  @override
  State<SignInOtpPage> createState() => _SignInOtpPageState();
}

class _SignInOtpPageState extends State<SignInOtpPage> {
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _pinCtrl = TextEditingController();
  final TextEditingController _otpCtrl = TextEditingController();

  String? _tempId;
  bool _loading = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    try {
      final p = UserPrefs.userPhone;
      if (p != null && p.isNotEmpty && (widget.initialPhone == null)) {
        _phoneCtrl.text = p;
      } else if (widget.initialPhone != null) {
        _phoneCtrl.text = widget.initialPhone!;
      }

      if (widget.initialPin != null) {
        _pinCtrl.text = widget.initialPin!;
      }

      // If both phone & pin were provided, automatically request OTP
      if (widget.initialPhone != null && widget.initialPin != null) {
        // small delay so UI is ready
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) _requestOtp();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _setStatus(String? m) {
    if (!mounted) return;
    setState(() => _statusMessage = m);
  }

  void _showSnack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  bool _validPhone(String v) => RegExp(r'^\d{8,13}$').hasMatch(v.trim());
  bool _validPin(String v) => RegExp(r'^\d{4,6}$').hasMatch(v.trim());

  /// Request OTP from backend: uses signinPasswordApi (tries /signin-password then /signin)
  Future<void> _requestOtp() async {
    final phone = _phoneCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    if (phone.isEmpty || pin.isEmpty) {
      _showSnack('Enter phone and PIN');
      return;
    }
    if (!_validPhone(phone)) {
      _showSnack('Enter valid phone (8–13 digits)');
      return;
    }
    if (!_validPin(pin)) {
      _showSnack('Enter a valid PIN (4–6 digits)');
      return;
    }

    setState(() {
      _loading = true;
      _statusMessage = null;
      _tempId = null;
    });

    try {
      debugPrint('[SignInOtp] about to call signinPasswordApi for $phone');
      final resp = await signinPasswordApi(phone, pin);

      if (resp is Map && resp['status'] == true) {
        final tid = resp['tempId']?.toString();
        if (tid != null && tid.isNotEmpty) {
          setState(() {
            _tempId = tid;
            _statusMessage = 'OTP requested. Check server logs / SMS.';
          });
          _showSnack('OTP requested. Check server logs / SMS.');
        } else {
          // Server returned immediate sign-in (no OTP)
          final user = resp['user'];
          final userPhone =
              (user is Map ? (user['user']?.toString() ?? phone) : phone);

          // Persist phone and token (if provided)
          await UserPrefs.setUserPhone(userPhone);
          final token = resp['token']?.toString();
          if (token != null && token.isNotEmpty) {
            await UserPrefs.setToken(token);
          } else {
            await UserPrefs.setToken(userPhone);
          }

          // Force socket to reconnect with new token
          try {
            await SockectService().forceReconnect();
          } catch (e, st) {
            debugPrint('[SignInOtp] forceReconnect error: $e\n$st');
          }

          _showSnack('Signed in as $userPhone');
          if (!mounted) return;
          Navigator.of(context).pushReplacementNamed('/home');
        }
      } else {
        final msg = (resp is Map)
            ? (resp['message'] ?? resp.toString())
            : resp.toString();
        _setStatus('Request failed: $msg');
        _showSnack('Request failed: $msg');
      }
    } on ApiException catch (e) {
      debugPrint('[SignInOtp] requestOtp error: $e');
      _setStatus('Request error: $e');
      _showSnack('Network or server error: $e');
    } catch (e) {
      debugPrint('[SignInOtp] unexpected requestOtp error: $e');
      _setStatus('Request error: $e');
      _showSnack('Network or server error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Verify OTP and sign in: endpoint '/verify-otp'
  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    final tid = _tempId;
    final phone = _phoneCtrl.text.trim();
    if (tid == null || tid.isEmpty) {
      _showSnack('Request OTP first');
      return;
    }
    if (otp.isEmpty) {
      _showSnack('Enter OTP');
      return;
    }

    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    try {
      final resp = await verifyOtpApi(tid, otp);

      if (resp is Map && resp['status'] == true) {
        final token = resp['token']?.toString();
        final user = resp['user'];
        final userPhone =
            (user is Map ? (user['user']?.toString() ?? phone) : phone);

        // Persist phone using UserPrefs
        await UserPrefs.setUserPhone(userPhone);

        // Persist token using UserPrefs wrapper (if returned)
        if (token != null && token.isNotEmpty) {
          await UserPrefs.setToken(token);
        } else {
          // fallback: store phone as token so socket has an auth value (temporary)
          await UserPrefs.setToken(userPhone);
        }

        // Force socket to reconnect with new token (service reads token from UserPrefs)
        try {
          await SockectService().forceReconnect();
        } catch (e, st) {
          debugPrint('[SignInOtp] forceReconnect error: $e\n$st');
        }

        // Auto-join session if we have one saved (optional)
        try {
          final savedSession = UserPrefs.sessionCode;
          if (savedSession != null && savedSession.isNotEmpty) {
            SockectService().joinSession(savedSession);
            debugPrint('[SignInOtp] auto-joining saved session $savedSession');
          }
        } catch (e, st) {
          debugPrint('[SignInOtp] auto-join session failed: $e\n$st');
        }

        _showSnack('Signed in as $userPhone');
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        final msg = (resp is Map)
            ? (resp['message'] ?? resp.toString())
            : resp.toString();
        _setStatus('Verify failed: $msg');
        _showSnack('Verify failed: $msg');
      }
    } on ApiException catch (e) {
      debugPrint('[SignInOtp] verifyOtp error: $e');
      _setStatus('Verify error: $e');
      _showSnack('Verify error: $e');
    } catch (e) {
      debugPrint('[SignInOtp] verifyOtp unexpected error: $e');
      _setStatus('Verify error: $e');
      _showSnack('Verify error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildStepOne() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone (e.g. 829...)'),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _pinCtrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'PIN'),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _loading ? null : _requestOtp,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Request OTP'),
        ),
      ],
    );
  }

  Widget _buildStepTwo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('tempId: ${_tempId ?? "—"}',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        TextFormField(
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'OTP'),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _loading ? null : _verifyOtp,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Verify OTP & Sign In'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final stepOtp = _tempId != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in (PIN → OTP)')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(children: [
            if (_statusMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(_statusMessage!,
                    style: const TextStyle(color: Colors.blue)),
              ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (!stepOtp) _buildStepOne() else _buildStepTwo(),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _tempId = null;
                          _otpCtrl.clear();
                          _statusMessage = null;
                        });
                      },
                      child: const Text('Start over'),
                    )
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
