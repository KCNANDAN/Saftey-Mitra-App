// lib/utils/api_requests.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const String BASE_URL = 'http://127.0.0.1:5000';

Uri _buildUri(String path, [Map<String, dynamic>? query]) {
  final p = path.startsWith('/') ? path : '/$path';
  final uri = Uri.parse('$BASE_URL$p');
  if (query != null && query.isNotEmpty) {
    return uri.replace(
        queryParameters: query.map((k, v) => MapEntry(k, v.toString())));
  }
  return uri;
}

dynamic _safeDecode(String body) {
  if (body.isEmpty) return null;
  try {
    return jsonDecode(body);
  } catch (_) {
    return body;
  }
}

String _extractErrorMessage(Object? data, int status) {
  if (data is Map) {
    for (final key in ['message', 'error', 'msg', 'detail']) {
      final val = data[key];
      if (val is String && val.trim().isNotEmpty) return val;
    }
  }
  return 'Request failed with status $status';
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Object? data;
  final Uri? uri;

  ApiException(this.message, {this.statusCode, this.data, this.uri});

  @override
  String toString() =>
      'ApiException(${statusCode ?? '-'}): $message${uri != null ? ' [$uri]' : ''}';
}

Future<dynamic> _sendRequest(
  Future<http.Response> Function() doSend,
  Uri uri,
) async {
  try {
    final res = await doSend().timeout(const Duration(seconds: 20));
    final decoded = _safeDecode(res.body);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _extractErrorMessage(decoded, res.statusCode);
      throw ApiException(msg,
          statusCode: res.statusCode, data: decoded, uri: uri);
    }
    return decoded;
  } on SocketException catch (e) {
    throw ApiException(
        'Network error. Check your internet or server availability.',
        data: e.toString(),
        uri: uri);
  } on TimeoutException {
    throw ApiException('Request timed out. Please try again later.', uri: uri);
  } catch (e) {
    throw ApiException('Unexpected error: $e', uri: uri);
  }
}

Future<dynamic> sendRequest({
  required String endpoint,
  required String method,
  Map<String, dynamic>? body,
  Map<String, String>? headers,
  Map<String, dynamic>? query,
}) async {
  final path = endpoint.startsWith('/') ? endpoint : '/$endpoint';
  final uri = _buildUri(path, query);
  final completeHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    ...?headers,
  };

  if (kDebugMode) {
    debugPrint('[HTTP] $method $uri');
    if (body != null) debugPrint('  ↳ body: ${jsonEncode(body)}');
  }

  switch (method.toUpperCase()) {
    case 'GET':
      return _sendRequest(() => http.get(uri, headers: completeHeaders), uri);
    case 'POST':
      return _sendRequest(
          () => http.post(uri,
              headers: completeHeaders, body: jsonEncode(body ?? {})),
          uri);
    case 'PUT':
      return _sendRequest(
          () => http.put(uri,
              headers: completeHeaders, body: jsonEncode(body ?? {})),
          uri);
    case 'DELETE':
      // Build an http.Request, send it, convert streamed response -> http.Response
      return _sendRequest(() async {
        final req = http.Request('DELETE', uri);
        req.headers.addAll(completeHeaders);
        // include body if provided (JSON)
        req.body = jsonEncode(body ?? {});
        final streamed = await req.send();
        final response = await http.Response.fromStream(streamed);
        return response;
      }, uri);
    default:
      throw ApiException('Unsupported HTTP method: $method', uri: uri);
  }
}

/* =========================
 * Specific API functions
 * ========================= */

// -------- Auth --------
Future<dynamic> signUp(String username, String pin) async {
  return await sendRequest(
      endpoint: '/signup',
      method: 'POST',
      body: {'user': username, 'smPIN': pin});
}

Future<dynamic> signIn(String username, String pin) async {
  return await sendRequest(
      endpoint: '/signin',
      method: 'POST',
      body: {'user': username, 'smPIN': pin});
}

Future<dynamic> resetPin(String username, String newPin) async {
  return await sendRequest(
      endpoint: '/reset-pin',
      method: 'POST',
      body: {'user': username, 'smPIN': newPin});
}

// New OTP login endpoints
Future<dynamic> signinPasswordApi(String phone, String pin) async {
  return await sendRequest(
      endpoint: '/signin-password',
      method: 'POST',
      body: {'user': phone, 'smPIN': pin});
}

Future<dynamic> verifyOtpApi(String tempId, String otp) async {
  return await sendRequest(
      endpoint: '/verify-otp',
      method: 'POST',
      body: {'tempId': tempId, 'otp': otp});
}

// -------- Emergency SOS --------
Future<dynamic> sendSOS({
  required double latitude,
  required double longitude,
  required String message,
  required String userPhoneNumber,
  String? videoUrl,
  String? voiceUrl,
}) async {
  return await sendRequest(
    endpoint: '/send-sos',
    method: 'POST',
    body: {
      'latitude': latitude,
      'longitude': longitude,
      'msg': message,
      'user': userPhoneNumber,
      if (videoUrl != null) 'videoUrl': videoUrl,
      if (voiceUrl != null) 'voiceUrl': voiceUrl,
    },
  );
}

// -------- Emergency Contacts --------
Future<dynamic> addEmergencyContact(
    String userPhone, String contactPhone) async {
  return await sendRequest(
      endpoint: '/add-contacts',
      method: 'POST',
      body: {'user': userPhone, 'contact': contactPhone});
}

Future<List<String>> getEmergencyContacts(String userPhone) async {
  final resp = await sendRequest(
      endpoint: '/contacts', method: 'GET', query: {'user': userPhone});
  if (resp is Map && resp.containsKey('contacts')) {
    return List<String>.from(resp['contacts']);
  }
  return [];
}

// -------- Location / Companion --------
Future<dynamic> storeCoordinates({
  required double latitude,
  required double longitude,
  required String timestamp,
  required String userPhoneNumber,
}) async {
  return await sendRequest(
    endpoint: '/store-coordinates',
    method: 'POST',
    body: {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp,
      'user': userPhoneNumber,
    },
  );
}

Future<dynamic> findCompanion({
  required String username,
  required double latitude,
  required double longitude,
  String? sessionCode,
}) async {
  final body = {
    'user': username,
    'latitude': latitude,
    'longitude': longitude,
    if (sessionCode != null && sessionCode.isNotEmpty) 'code': sessionCode,
  };
  return await sendRequest(
    endpoint: '/find-companion',
    method: 'POST',
    body: body,
  );
}

// -------- Sessions --------
Future<dynamic> createSession(String userPhone,
    {int timeoutSeconds = 10}) async {
  final uri = Uri.parse('$BASE_URL/create-session');
  final body = jsonEncode({'user': userPhone});

  final resp = await http
      .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
      .timeout(Duration(seconds: timeoutSeconds));

  final status = resp.statusCode;
  final raw = resp.body;
  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    decoded = raw;
  }

  return {'statusCode': status, 'raw': raw, 'json': decoded};
}

Future<dynamic> joinSession(String userPhoneNumber, String sessionCode) async {
  return await sendRequest(
      endpoint: '/join-session',
      method: 'POST',
      body: {'user': userPhoneNumber, 'code': sessionCode});
}

// -------- Safe Zone (Geofence) --------
Future<dynamic> createOrUpdateSafeZone({
  required String user,
  String? session,
  required double latitude,
  required double longitude,
  required double radiusMeters,
  String? actor, // optional: the caller acting on behalf of user
}) async {
  final body = {
    'user': user,
    if (session != null && session.isNotEmpty) 'session': session,
    'latitude': latitude,
    'longitude': longitude,
    'radiusMeters': radiusMeters,
    if (actor != null && actor.isNotEmpty) 'actor': actor,
  };
  return await sendRequest(endpoint: '/safe-zone', method: 'POST', body: body);
}

Future<dynamic> getSafeZoneForSession({String? session, String? user}) async {
  final endpoint = (session != null && session.isNotEmpty)
      ? '/safe-zone/$session'
      : '/safe-zone';
  final query = (session == null && user != null) ? {'user': user} : null;
  return await sendRequest(endpoint: endpoint, method: 'GET', query: query);
}

Future<dynamic> reportSafeZoneBreach({
  required String user,
  required String session,
  required double latitude,
  required double longitude,
  String? timestamp,
}) async {
  final body = {
    'user': user,
    'session': session,
    'latitude': latitude,
    'longitude': longitude,
    if (timestamp != null) 'timestamp': timestamp,
  };
  return await sendRequest(
      endpoint: '/safe-zone/breach', method: 'POST', body: body);
}

// -------- Relationships (Family / Guardian) --------
Future<dynamic> requestRelationship({
  required String from,
  required String to,
  required String type,
  Map<String, dynamic>? grants,
}) async {
  return await sendRequest(
    endpoint: '/relationship/request',
    method: 'POST',
    body: {
      'from': from,
      'to': to,
      'type': type,
      if (grants != null) 'grants': grants,
    },
  );
}

Future<dynamic> respondRelationship({
  required String relId,
  required String to,
  required String action, // accept | reject | revoke
  Map<String, dynamic>? grants,
}) async {
  return await sendRequest(
    endpoint: '/relationship/respond',
    method: 'POST',
    body: {
      'relId': relId,
      'to': to,
      'action': action,
      if (grants != null) 'grants': grants,
    },
  );
}

Future<dynamic> listRelationships(String user) async {
  return await sendRequest(
    endpoint: '/relationship/list',
    method: 'GET',
    query: {'user': user},
  );
}

Future<dynamic> getRelationshipsForUser(String user) async {
  return await sendRequest(
    endpoint: '/relationship/for-user',
    method: 'GET',
    query: {'user': user},
  );
}

Future<dynamic> deleteRelationship(String id, {String? actor}) async {
  final query = actor != null ? {'actor': actor} : null;
  final body = actor != null ? {'actor': actor} : null;
  return await sendRequest(
    endpoint: '/relationship/$id',
    method: 'DELETE',
    body: body,
    query: query,
  );
}

// Wrapper with named arg
Future<dynamic> deleteRelationshipById(
    {required String id, String? actor}) async {
  return await deleteRelationship(id, actor: actor);
}

// -------- Misc --------
Future<dynamic> getSafetyTip() async {
  return await sendRequest(endpoint: '/safety-tip', method: 'GET');
}
