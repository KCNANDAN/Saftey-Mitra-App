// lib/utils/user_prefs.dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class UserPrefs {
  static const String _kPhoneKey = 'sm_user_phone';
  static const String _kTokenKey = 'sm_token';
  static const String _kSessionKey = 'sm_session_code';

  // new key for local breach history
  static const String _kBreachHistoryKey = 'sm_breach_history';

  static SharedPreferences? _prefs;

  /// Call once at app startup:
  static Future<void> init() async {
    if (_prefs != null) return;
    _prefs = await SharedPreferences.getInstance();
    if (kDebugMode) {
      debugPrint(
          '[USERPREFS] init completed, phone=${_prefs!.getString(_kPhoneKey)} tokenExists=${_prefs!.containsKey(_kTokenKey)} session=${_prefs!.getString(_kSessionKey)}');
    }
  }

  // ---------------- Phone ----------------
  static String? get userPhone {
    try {
      return _prefs?.getString(_kPhoneKey);
    } catch (e) {
      if (kDebugMode) debugPrint('[USERPREFS] get userPhone error: $e');
      return null;
    }
  }

  static Future<void> setUserPhone(String phone) async {
    if (_prefs == null) await init();
    await _prefs!.setString(_kPhoneKey, phone);
    if (kDebugMode) debugPrint('[USERPREFS] saved phone: $phone');
  }

  static Future<void> clearUserPhone() async {
    if (_prefs == null) await init();
    await _prefs!.remove(_kPhoneKey);
    if (kDebugMode) debugPrint('[USERPREFS] cleared phone');
  }

  static bool get isLoggedIn {
    final p = userPhone;
    return p != null && p.isNotEmpty;
  }

  // ---------------- Token ----------------
  /// Returns the stored JWT token or null
  static String? getToken() {
    try {
      return _prefs?.getString(_kTokenKey);
    } catch (e) {
      if (kDebugMode) debugPrint('[USERPREFS] getToken error: $e');
      return null;
    }
  }

  /// Persist token
  static Future<void> setToken(String token) async {
    if (_prefs == null) await init();
    await _prefs!.setString(_kTokenKey, token);
    if (kDebugMode) debugPrint('[USERPREFS] saved token (len=${token.length})');
  }

  /// Remove token
  static Future<void> clearToken() async {
    if (_prefs == null) await init();
    await _prefs!.remove(_kTokenKey);
    if (kDebugMode) debugPrint('[USERPREFS] cleared token');
  }

  // ---------------- Session code (optional) ----------------
  /// store the last-known session code (useful for auto-join after login)
  static String? get sessionCode {
    try {
      return _prefs?.getString(_kSessionKey);
    } catch (e) {
      if (kDebugMode) debugPrint('[USERPREFS] get sessionCode error: $e');
      return null;
    }
  }

  static Future<void> setSessionCode(String code) async {
    if (_prefs == null) await init();
    await _prefs!.setString(_kSessionKey, code);
    if (kDebugMode) debugPrint('[USERPREFS] saved session code: $code');
  }

  static Future<void> clearSessionCode() async {
    if (_prefs == null) await init();
    await _prefs!.remove(_kSessionKey);
    if (kDebugMode) debugPrint('[USERPREFS] cleared session code');
  }

  // ---------------- Breach history (local cache) ----------------
  /// Adds a breach record to local history. Newest-first.
  static Future<void> addBreach(Map<String, dynamic> breach) async {
    if (_prefs == null) await init();
    List<Map<String, dynamic>> history = getBreachHistory();
    breach['timestamp'] =
        breach['timestamp'] ?? DateTime.now().toIso8601String();
    history.insert(0, Map<String, dynamic>.from(breach));
    // keep only last 200 entries to avoid bloat
    if (history.length > 200) history = history.sublist(0, 200);
    await _prefs!.setString(_kBreachHistoryKey, jsonEncode(history));
    if (kDebugMode) {
      debugPrint('[USERPREFS] added breach, total=${history.length}');
    }
  }

  static List<Map<String, dynamic>> getBreachHistory() {
    try {
      final jsonStr = _prefs?.getString(_kBreachHistoryKey);
      if (jsonStr == null || jsonStr.isEmpty) return [];
      final List decoded = jsonDecode(jsonStr);
      return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[USERPREFS] getBreachHistory error: $e');
      return [];
    }
  }

  static Future<void> clearBreachHistory() async {
    if (_prefs == null) await init();
    await _prefs!.remove(_kBreachHistoryKey);
    if (kDebugMode) debugPrint('[USERPREFS] cleared breach history');
  }
}
