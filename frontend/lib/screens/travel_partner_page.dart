// lib/screens/travel_partner_page.dart
// Travel Partner main screen (cleaned / defensive)

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:frontend/widgets/relationship_tile.dart';
import 'package:frontend/utils/api_requests.dart';
import 'package:frontend/utils/user_prefs.dart';
import 'package:frontend/services/socket_service.dart';

class TravelPartnerPage extends StatefulWidget {
  const TravelPartnerPage({super.key});

  @override
  State<TravelPartnerPage> createState() => _TravelPartnerPageState();
}

class _TravelPartnerPageState extends State<TravelPartnerPage> {
  String? _userPhone;
  String? _sessionCode;
  bool _isSharing = false;
  bool _isCreating = false;
  bool _isJoining = false;
  bool _isFinding = false;
  Timer? _shareTimer;
  bool _sharingActive = false;
  Position? _lastPosition;
  String _findResponsePretty = '';
  final TextEditingController _joinCodeCtrl = TextEditingController();

  // Socket service singleton instance
  final SockectService _sockService = SockectService();
  StreamSubscription<bool>? _connSub;
  StreamSubscription<Map<String, dynamic>>? _partnerSub;
  StreamSubscription<Map<String, dynamic>>? _safeZoneBreachSub;

  bool _socketConnected = false;

  // pending queue polling
  Timer? _queuePollTimer;
  int _pendingQueueCount = 0;

  final List<Map<String, dynamic>> _liveUpdates = [];

  GoogleMapController? _mapController;
  final Map<String, Marker> _markers = {};
  final CameraPosition _initialCamera =
      const CameraPosition(target: LatLng(20.5937, 78.9629), zoom: 4);

  // NOTE: update to your backend IP when testing on device/emulator
  static const String socketServerUrl = 'http://127.0.0.1:5000';

  bool _disposed = false;

  // Safe zone state (server-backed)
  Map<String, dynamic>? _safeZone; // { latitude, longitude, radiusMeters }
  bool _safeZoneBreached = false;

  // Circles for map overlay
  final Set<Circle> _circles = {};

  @override
  void initState() {
    super.initState();
    _userPhone = UserPrefs.userPhone;
    debugPrint('[TP] initState userPhone=$_userPhone');

    // Defer heavy async work to after first frame so UI won't block.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.microtask(() async {
        try {
          await _initSockService();
        } catch (e, st) {
          debugPrint('[TP] _initSockService failed (ignored): $e\n$st');
        }

        try {
          await _warmUpLocation();
        } catch (e, st) {
          debugPrint('[TP] _warmUpLocation failed (ignored): $e\n$st');
        }

        try {
          _queuePollTimer?.cancel();
          _queuePollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (!mounted || _disposed) return;
            try {
              final cnt = _sock_service_pendingCountSafe();
              if (cnt != _pendingQueueCount) {
                setState(() => _pendingQueueCount = cnt);
              }
            } catch (e) {
              // ignore
            }
          });
        } catch (e, st) {
          debugPrint('[TP] queue timer start failed: $e\n$st');
        }
      });
    });
  }

  int _sock_service_pendingCountSafe() {
    try {
      return _sockService.pendingCount;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _initSockService() async {
    try {
      final token = UserPrefs.getToken() ?? _userPhone;
      if (kDebugMode) debugPrint('[TP] sock init token=${token ?? 'null'}');

      await _sockService.init(url: socketServerUrl, token: token);

      // connection status subscription
      try {
        _connSub = _sock_service_connectionSub();
      } catch (e) {
        debugPrint('[TP] connectionStream listen error: $e');
      }

      // partner updates stream (service exposes partner_location or locationUpdate)
      try {
        final maybePartnerStream = _sockService.partnerLocationStream;
        _partnerSub = maybePartnerStream.listen((data) {
          debugPrint('[TP] partner_location (via service): $data');
          final mapData = _normalizeIncomingDataToMap(data);
          if (mapData.isNotEmpty) {
            if (mounted && !_disposed) {
              setState(() {
                _liveUpdates.insert(0, mapData);
                if (_liveUpdates.length > 100) _liveUpdates.removeLast();
              });
            } else {
              _liveUpdates.insert(0, mapData);
              if (_liveUpdates.length > 100) _liveUpdates.removeLast();
            }
            _upsertMarkerFromUpdate(mapData);
          }
        }, onError: (e) {
          debugPrint('[TP] partner stream error: $e');
        });
      } catch (e) {
        debugPrint('[TP] partnerLocationStream listen error: $e');
      }

      // safezone_breach subscription (only if service exposes it) --> runtime-safe
      try {
        final dynamic svc = _sockService;
        final dynamic maybeBreachStream = svc.safeZoneBreachStream;
        if (maybeBreachStream != null) {
          _safeZoneBreachSub =
              (maybeBreachStream as Stream).cast<Map<String, dynamic>>().listen(
            (payload) {
              debugPrint('[TP] received safezone_breach payload: $payload');
              try {
                final user = (payload['user'] ?? '').toString();
                if (_userPhone != null && user == _userPhone) {
                  final lat = (payload['latitude'] is num)
                      ? (payload['latitude'] as num).toDouble()
                      : double.tryParse(
                              payload['latitude']?.toString() ?? '') ??
                          0.0;
                  final lng = (payload['longitude'] is num)
                      ? (payload['longitude'] as num).toDouble()
                      : double.tryParse(
                              payload['longitude']?.toString() ?? '') ??
                          0.0;

                  final pos = Position(
                    latitude: lat,
                    longitude: lng,
                    timestamp: DateTime.tryParse(
                            payload['timestamp']?.toString() ?? '') ??
                        DateTime.now(),
                    accuracy: 0.0,
                    altitude: 0.0,
                    heading: 0.0,
                    speed: 0.0,
                    speedAccuracy: 0.0,
                    headingAccuracy: 0.0,
                    altitudeAccuracy: 0.0,
                  );

                  _showBreachDialog(_safeZone, pos);
                } else {
                  final mapData = _normalizeIncomingDataToMap(payload);
                  if (mapData.isNotEmpty) {
                    if (mounted && !_disposed) {
                      setState(() {
                        _liveUpdates.insert(0, mapData);
                        if (_liveUpdates.length > 100) {
                          _liveUpdates.removeLast();
                        }
                      });
                    } else {
                      _liveUpdates.insert(0, mapData);
                      if (_liveUpdates.length > 100) _liveUpdates.removeLast();
                    }
                  }
                }
              } catch (e, st) {
                debugPrint('[TP] handling safezone_breach error: $e\n$st');
              }
            },
            onError: (e) {
              debugPrint('[TP] safeZoneBreach stream error: $e');
            },
          );
        } else {
          debugPrint('[TP] safeZoneBreachStream not present on service');
        }
      } catch (e) {
        debugPrint(
            '[TP] subscribing to safeZoneBreachStream failed (ignored): $e');
      }

      // after socket init, try fetch safe zone for session (if we have session or user)
      try {
        await Future.delayed(const Duration(milliseconds: 200));
        if ((_sessionCode != null && _sessionCode!.isNotEmpty) ||
            (_userPhone != null)) {
          final resp = await getSafeZoneForSession(
              session: _sessionCode, user: _userPhone);
          debugPrint('[GEOFENCE] getSafeZone resp: $resp');
          if (resp is Map && resp['status'] == true && resp['zone'] != null) {
            if (mounted && !_disposed) {
              setState(() {
                _safeZone = Map<String, dynamic>.from(resp['zone']);
              });
            } else {
              _safeZone = Map<String, dynamic>.from(resp['zone']);
            }
            _updateGeofenceCircle();
          }
        }
      } catch (e) {
        debugPrint('[GEOFENCE] fetch zone error: $e');
      }
    } catch (e, st) {
      debugPrint('[TP] socket service init error: $e\n$st');
    }
  }

  StreamSubscription<bool> _sock_service_connectionSub() {
    return _sockService.connectionStream.listen((connected) {
      if (mounted && !_disposed) {
        setState(() {
          _socketConnected = connected;
        });
      } else {
        _socketConnected = connected;
      }
    });
  }

  Map<String, dynamic> _normalizeIncomingDataToMap(Object data) {
    Map<String, dynamic> mapData = {};
    try {
      if (data is Map<String, dynamic>) {
        mapData = Map<String, dynamic>.from(data);
      } else if (data is Map) {
        mapData = Map<String, dynamic>.from(data);
      } else if (data is String) {
        final decoded = jsonDecode(data);
        if (decoded is Map) mapData = Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      debugPrint('[TP] normalizeIncomingDataToMap error: $e');
    }
    return mapData;
  }

  Future<void> _warmUpLocation() async {
    try {
      final ready = await _ensureLocationReady();
      debugPrint('[TP] _warmUpLocation ready=$ready');
      if (!ready) return;
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high);
      debugPrint('[TP] warmUp pos=$pos');
      if (mounted && !_disposed) {
        setState(() => _lastPosition = pos);
      }
    } catch (e, st) {
      debugPrint('[TP] warmUp error: $e\n$st');
    }
  }

  @override
  void dispose() {
    debugPrint('[TP] dispose called');
    _disposed = true;
    _sharingActive = false;
    _shareTimer?.cancel();
    _shareTimer = null;
    _joinCodeCtrl.dispose();

    try {
      _connSub?.cancel();
    } catch (_) {}
    try {
      _partnerSub?.cancel();
    } catch (_) {}
    try {
      _safeZoneBreachSub?.cancel();
    } catch (_) {}

    try {
      _sockService.dispose();
    } catch (_) {}

    _queuePollTimer?.cancel();
    _queuePollTimer = null;

    _mapController?.dispose();
    super.dispose();
  }

  // ---------------- Emit via service (replaces inline socket emits) ----------------
  Future<void> _emitLocationViaService({
    required String user,
    required double latitude,
    required double longitude,
    String? session,
  }) async {
    final payload = {
      'user': user,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().toIso8601String(),
      if (session != null) 'session': session,
      'clientId': UniqueKey().toString(),
    };

    debugPrint('[EMIT-SRV] queueing emit: $payload');

    try {
      if (mounted && !_disposed) {
        setState(() {
          _liveUpdates.insert(0, Map<String, dynamic>.from(payload));
          if (_liveUpdates.length > 100) _liveUpdates.removeLast();
        });
      } else {
        _liveUpdates.insert(0, Map<String, dynamic>.from(payload));
        if (_liveUpdates.length > 100) _liveUpdates.removeLast();
      }
      _upsertMarkerFromUpdate(payload);
    } catch (e, st) {
      debugPrint('[EMIT-SRV] local insert failed: $e\n$st');
    }

    try {
      await _sockService.emitWithQueue('update_location', payload);
      debugPrint('[EMIT-SRV] enqueued to sock service');
    } catch (e, st) {
      debugPrint('[EMIT-SRV] emitWithQueue error: $e\n$st');
    }
  }

  void _upsertMarkerFromUpdate(Map<String, dynamic> u) {
    try {
      final user = (u['user'] ?? 'unknown').toString();
      final lat = (u['latitude'] is num)
          ? (u['latitude'] as num).toDouble()
          : double.tryParse(u['latitude']?.toString() ?? '') ?? 0.0;
      final lng = (u['longitude'] is num)
          ? (u['longitude'] as num).toDouble()
          : double.tryParse(u['longitude']?.toString() ?? '') ?? 0.0;
      final ts = u['timestamp'] ?? '';

      if (lat == 0.0 && lng == 0.0) return;

      final markerId = 'm_$user';
      final marker = Marker(
        markerId: MarkerId(markerId),
        position: LatLng(lat, lng),
        infoWindow: InfoWindow(
            title: user,
            snippet:
                '$ts${u['session'] != null ? ' (session ${u['session']})' : ''}'),
        icon: BitmapDescriptor.defaultMarkerWithHue(user == _userPhone
            ? BitmapDescriptor.hueAzure
            : BitmapDescriptor.hueRed),
      );

      _markers[markerId] = marker;

      if (user == _userPhone && _mapController != null) {
        try {
          _moveCameraTo(LatLng(lat, lng));
        } catch (e, st) {
          debugPrint('[MAP] moveCamera async error: $e\n$st');
        }
      }
    } catch (e, st) {
      debugPrint('[MAP] upsert marker failed: $e\n$st');
    }
  }

  Future<void> _moveCameraTo(LatLng pos) async {
    try {
      if (_mapController != null) {
        await _mapController!
            .animateCamera(CameraUpdate.newLatLngZoom(pos, 16.0));
      }
    } catch (e, st) {
      debugPrint('[MAP] moveCamera error: $e\n$st');
    }
  }

  // ---------------- helpers ----------------
  void _showSnack(String msg) {
    if (!mounted || _disposed) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _ensureLocationReady() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnack('Location services are disabled. Please enable them.');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      _showSnack('Location permission denied.');
      return false;
    }
    if (permission == LocationPermission.deniedForever) {
      _showSnack(
          'Location permission permanently denied. Enable it in settings.');
      return false;
    }

    return true;
  }

  // ---------------- GEO helpers ----------------
  double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0; // Earth radius in meters
    final phi1 = lat1 * (pi / 180.0);
    final phi2 = lat2 * (pi / 180.0);
    final dPhi = (lat2 - lat1) * (pi / 180.0);
    final dLambda = (lng2 - lng1) * (pi / 180.0);
    final a = (sin(dPhi / 2) * sin(dPhi / 2)) +
        cos(phi1) * cos(phi2) * (sin(dLambda / 2) * sin(dLambda / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  bool _isInsideSafeZone(Position pos, Map<String, dynamic>? zone) {
    if (zone == null) return true;
    try {
      final centerLat = (zone['latitude'] is num)
          ? (zone['latitude'] as num).toDouble()
          : double.parse(zone['latitude'].toString());
      final centerLng = (zone['longitude'] is num)
          ? (zone['longitude'] as num).toDouble()
          : double.parse(zone['longitude'].toString());
      final radius = (zone['radiusMeters'] is num)
          ? (zone['radiusMeters'] as num).toDouble()
          : double.parse(zone['radiusMeters'].toString());
      final dist =
          _distanceMeters(centerLat, centerLng, pos.latitude, pos.longitude);
      return dist <= radius;
    } catch (e) {
      debugPrint('[GEOFENCE] parse error: $e');
      return true;
    }
  }

  // Update drawn circle on map
  void _updateGeofenceCircle() {
    if (_safeZone == null) {
      if (mounted && !_disposed) {
        setState(() => _circles.clear());
      } else {
        _circles.clear();
      }
      return;
    }
    try {
      final centerLat = (_safeZone!['latitude'] is num)
          ? (_safeZone!['latitude'] as num).toDouble()
          : double.parse(_safeZone!['latitude'].toString());
      final centerLng = (_safeZone!['longitude'] is num)
          ? (_safeZone!['longitude'] as num).toDouble()
          : double.parse(_safeZone!['longitude'].toString());
      final radius = (_safeZone!['radiusMeters'] is num)
          ? (_safeZone!['radiusMeters'] as num).toDouble()
          : double.parse(_safeZone!['radiusMeters'].toString());

      final circle = Circle(
        circleId: const CircleId('safezone'),
        center: LatLng(centerLat, centerLng),
        radius: radius,
        strokeWidth: 2,
        strokeColor: Colors.orange,
        fillColor: Colors.orange.withOpacity(0.2),
      );

      if (mounted && !_disposed) {
        setState(() {
          _circles.clear();
          _circles.add(circle);
        });
      } else {
        _circles.clear();
        _circles.add(circle);
      }
    } catch (e) {
      debugPrint('[GEOFENCE] updateCircle error: $e');
    }
  }

  // ---------------- Create/Join/Start/Stop ----------------
  Future<void> _createSession() async {
    if ((_userPhone ?? '').trim().isEmpty) {
      _showSnack('No user phone saved. Sign in first.');
      return;
    }
    if (_isCreating) return;
    if (mounted && !_disposed) setState(() => _isCreating = true);

    try {
      final respWrapper = await createSession(_userPhone!).timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw Exception('createSession timeout'),
      );
      debugPrint('[API] createSession response (wrapper): $respWrapper');

      final status = respWrapper['statusCode'];
      final raw = respWrapper['raw'];
      final json = respWrapper['json'];

      debugPrint('[API] createSession raw body: $raw');

      String? code;

      if (json is Map && json['code'] != null) {
        code = json['code']?.toString();
      }
      if (code == null &&
          json is Map &&
          json['data'] is Map &&
          json['data']['code'] != null) {
        code = json['data']['code']?.toString();
      }
      if (code == null && json is Map && json['message'] != null) {
        final msg = json['message']?.toString() ?? '';
        final m = RegExp(r'([A-Za-z0-9]{4,})').firstMatch(msg);
        if (m != null) code = m.group(1);
      }
      if (code == null && raw is String) {
        final m = RegExp(r'([A-Za-z0-9]{4,})').firstMatch(raw);
        if (m != null) code = m.group(1);
      }

      if (code == null || code.isEmpty) {
        debugPrint(
            '[API] createSession: could not find code - status=$status raw=$raw json=$json');
        _showSnack('No session code returned — check backend (see logs).');
        return;
      }

      if (mounted && !_disposed) setState(() => _sessionCode = code);

      try {
        _sockService.joinSession(code);
        await UserPrefs.setSessionCode(code);
      } catch (e, st) {
        debugPrint('[TP] joinSession via service failed: $e\n$st');
      }

      try {
        await Clipboard.setData(ClipboardData(text: code));
        _showSnack('Session created. Code copied to clipboard.');
      } catch (e, st) {
        debugPrint('[API] Clipboard write failed: $e\n$st');
        _showSnack('Session created (clipboard failed).');
      }
    } catch (e, st) {
      debugPrint('[API] createSession error: $e\n$st');
      _showSnack('Failed to create session: ${e.toString()}');
    } finally {
      if (mounted && !_disposed) setState(() => _isCreating = false);
    }
  }

  Future<void> _joinSession() async {
    final code = _joinCodeCtrl.text.trim();
    if (code.isEmpty) {
      _showSnack('Enter session code to join.');
      return;
    }
    if ((_userPhone ?? '').trim().isEmpty) {
      _showSnack('No user phone saved. Sign in first.');
      return;
    }
    if (mounted && !_disposed) setState(() => _isJoining = true);
    try {
      final resp = await joinSession(_userPhone!, code);
      debugPrint('[API] joinSession response: $resp');
      if (mounted && !_disposed) setState(() => _sessionCode = code);

      try {
        _sockService.joinSession(code);
        await UserPrefs.setSessionCode(code);
      } catch (e, st) {
        debugPrint('[TP] joinSession via service failed: $e\n$st');
      }

      _showSnack('Joined session: $code');
    } catch (e, st) {
      debugPrint('[API] joinSession error: $e\n$st');
      _showSnack('Failed to join: $e');
    } finally {
      if (mounted && !_disposed) setState(() => _isJoining = false);
    }
  }

  Future<void> _shareSessionCode() async {
    if (_sessionCode == null || _sessionCode!.isEmpty) {
      _showSnack('Create a session first to get a code to share.');
      return;
    }
    final textToShare =
        'Join my Safety Mitra session with this code: $_sessionCode';
    try {
      await Share.share(textToShare, subject: 'Safety Mitra Session Code');
    } catch (e) {
      debugPrint('[SHARE] failed: $e');
      _showSnack('Share failed.');
    }
  }

  Future<void> _sendCoordinateOnceWithTimeout(Position pos) async {
    try {
      final isoTs = DateTime.now().toIso8601String();
      debugPrint(
          '[API] storeCoordinates call lat=${pos.latitude} lng=${pos.longitude}');
      await storeCoordinates(
        latitude: pos.latitude,
        longitude: pos.longitude,
        timestamp: isoTs,
        userPhoneNumber: _userPhone!,
      ).timeout(const Duration(seconds: 8));
      debugPrint(
          '[API] storeCoordinates OK at ${pos.latitude}, ${pos.longitude}');
    } catch (e, st) {
      debugPrint('[API] storeCoordinates failed (ignored): $e\n$st');
    }
  }

  // UPDATED: include actor when saving safe zone
  Future<void> _saveSafeZoneToServer(double lat, double lng, double radius,
      {String? targetUser}) async {
    // targetUser: optional - if set, you are editing someone else's zone
    final userForZone = targetUser ?? (UserPrefs.userPhone ?? '');
    if (userForZone.isEmpty) {
      _showSnack('No target user specified or not signed in.');
      return;
    }
    final actor = UserPrefs.userPhone;
    if (actor == null || actor.isEmpty) {
      _showSnack('Sign in first to save safe zone.');
      return;
    }

    // Optional client-side permission check (best-effort)
    try {
      final allowed = await canEditZone(userForZone);
      if (!allowed) {
        debugPrint(
            '[GEOFENCE] client: $actor cannot edit zone for $userForZone');
        _showSnack(
            'You do not have permission to edit the zone for $userForZone');
        return;
      }
    } catch (e) {
      debugPrint('[GEOFENCE] canEditZone error (ignored): $e');
      // continue - server will enforce permissions anyway
    }

    // Make request and include actor explicitly
    try {
      debugPrint(
          '[GEOFENCE] creating/updating zone user=$userForZone actor=$actor lat=$lat lng=$lng r=$radius');
      final resp = await createOrUpdateSafeZone(
        user: userForZone,
        session: _sessionCode,
        latitude: lat,
        longitude: lng,
        radiusMeters: radius,
        actor: actor, // <<-- CRITICAL: include actor
      );
      debugPrint('[GEOFENCE] createOrUpdateSafeZone response: $resp');

      if (resp is Map && resp['status'] == true) {
        final zone = resp['zone'];
        if (mounted && !_disposed) {
          setState(() {
            _safeZone = zone is Map<String, dynamic>
                ? Map<String, dynamic>.from(zone)
                : {
                    'user': userForZone,
                    'latitude': lat,
                    'longitude': lng,
                    'radiusMeters': radius
                  };
          });
          _updateGeofenceCircle();
        } else {
          _safeZone = zone is Map<String, dynamic>
              ? Map<String, dynamic>.from(zone)
              : {
                  'user': userForZone,
                  'latitude': lat,
                  'longitude': lng,
                  'radiusMeters': radius
                };
        }
        _showSnack('Safe zone saved on server.');
      } else {
        final msg = resp is Map && resp['message'] != null
            ? resp['message']
            : resp.toString();
        _showSnack('Save failed: $msg');
      }
    } catch (e, st) {
      debugPrint('[GEOFENCE] createOrUpdateSafeZone error: $e\n$st');
      _showSnack('Failed to save safe zone: $e');
    }
  }

  /// Returns true if the currently signed-in user is allowed to edit the
  /// safe zone of [targetUser]. Owner may always edit their own zone.
  Future<bool> canEditZone(String targetUser) async {
    try {
      final me = UserPrefs.userPhone;
      if (me == null) return false;
      if (me == targetUser) return true;

      // fetch relationships for the current user (we already import listRelationships)
      final resp = await listRelationships(me);
      if (resp is Map &&
          resp['status'] == true &&
          resp['relationships'] != null) {
        final rels = List<Map<String, dynamic>>.from(resp['relationships']);
        for (final r in rels) {
          try {
            final status = (r['status'] ?? '').toString();
            if (status != 'accepted') continue;

            final from = (r['from'] ?? '').toString();
            final to = (r['to'] ?? '').toString();
            final grants = r['grants'] is Map
                ? Map<String, dynamic>.from(r['grants'])
                : <String, dynamic>{};
            final edit = grants['editSafeZone'] == true;

            if (!edit) continue;

            // allow if relationship connects the two users in either direction
            if ((from == me && to == targetUser) ||
                (from == targetUser && to == me)) {
              return true;
            }
          } catch (_) {
            // ignore per-item errors and continue to next relationship
            continue;
          }
        }
      }
      return false;
    } catch (e, st) {
      debugPrint('[GEOFENCE] canEditZone error: $e\n$st');
      return false;
    }
  }

  Future<void> _startSharing() async {
    debugPrint(
        '[SHARE] startSharing called isSharing=$_isSharing session=$_sessionCode socketConnected=$_socketConnected');
    if (_isSharing) {
      _showSnack('Already sharing');
      debugPrint('[SHARE] already sharing - returning early');
      return;
    }
    if (_sessionCode == null || _sessionCode!.isEmpty) {
      _showSnack('Create or join a session first.');
      return;
    }
    if (mounted && !_disposed) setState(() => _isSharing = true);
    _sharingActive = true;

    final ready = await _ensureLocationReady();
    if (!ready) {
      if (mounted && !_disposed) setState(() => _isSharing = false);
      _sharingActive = false;
      return;
    }

    Future<Position> getPositionWithTimeout() {
      return Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high)
          .timeout(const Duration(seconds: 10));
    }

    try {
      final pos = await getPositionWithTimeout();
      debugPrint('[SHARE] initial position: $pos');
      _lastPosition = pos;
      _sendCoordinateOnceWithTimeout(pos);

      if ((_userPhone ?? '').isNotEmpty) {
        try {
          await _emitLocationViaService(
            user: _userPhone!,
            latitude: pos.latitude,
            longitude: pos.longitude,
            session: _sessionCode,
          );
        } catch (e, st) {
          debugPrint('[SHARE] emit initial failed: $e\n$st');
        }
      }

      // GEOFENCE check for initial pos
      if (_safeZone != null) {
        final inside = _isInsideSafeZone(pos, _safeZone);
        if (!inside && !_safeZoneBreached) {
          _safeZoneBreached = true;
          _showSnack('You left your safe zone!');
          // emit + report
          try {
            await _sockService.emitWithQueue('safezone_breach', {
              'user': _userPhone,
              'latitude': pos.latitude,
              'longitude': pos.longitude,
              'session': _sessionCode,
              'timestamp': DateTime.now().toIso8601String(),
            });
          } catch (e) {
            debugPrint('[GEOFENCE] socket emit error: $e');
          }
          try {
            await reportSafeZoneBreach(
              user: _userPhone!,
              session: _sessionCode ?? '',
              latitude: pos.latitude,
              longitude: pos.longitude,
            );
          } catch (e) {
            debugPrint('[GEOFENCE] report breach API error: $e');
          }

          // show breach dialog to user and offer SOS
          _showBreachDialog(_safeZone, pos);
        }
      }
    } catch (e, st) {
      debugPrint('[SHARE] initial get position failed: $e\n$st');
      _showSnack('Could not get current position: ${e.toString()}');
      if (mounted && !_disposed) setState(() => _isSharing = false);
      _sharingActive = false;
      return;
    }

    bool tickRunning = false;
    _shareTimer?.cancel();
    _shareTimer = Timer.periodic(const Duration(seconds: 10), (t) async {
      debugPrint(
          '[TIMER] tick (active=$_sharingActive) socketConnected=$_socketConnected');
      if (_disposed || !_sharingActive) {
        debugPrint('[TIMER] disposed or not active -> cancelling timer');
        try {
          t.cancel();
        } catch (_) {}
        return;
      }
      if (tickRunning) {
        debugPrint('[TIMER] previous tick still running, skipping');
        return;
      }
      tickRunning = true;
      try {
        final pos = await getPositionWithTimeout();
        debugPrint('[TIMER] got position: $pos');
        _lastPosition = pos;
        _sendCoordinateOnceWithTimeout(pos);
        if ((_userPhone ?? '').isNotEmpty) {
          await _emitLocationViaService(
            user: _userPhone!,
            latitude: pos.latitude,
            longitude: pos.longitude,
            session: _sessionCode,
          );
        }

        // GEOFENCE check (periodic)
        if (_safeZone != null) {
          final inside = _isInsideSafeZone(pos, _safeZone);
          if (!inside && !_safeZoneBreached) {
            _safeZoneBreached = true;
            _showSnack('You left your safe zone!');
            // emit + report
            try {
              await _sockService.emitWithQueue('safezone_breach', {
                'user': _userPhone,
                'latitude': pos.latitude,
                'longitude': pos.longitude,
                'session': _sessionCode,
                'timestamp': DateTime.now().toIso8601String(),
              });
            } catch (e) {
              debugPrint('[GEOFENCE] socket emit error: $e');
            }
            try {
              await reportSafeZoneBreach(
                user: _userPhone!,
                session: _sessionCode ?? '',
                latitude: pos.latitude,
                longitude: pos.longitude,
              );
            } catch (e) {
              debugPrint('[GEOFENCE] report breach API error: $e');
            }

            // show breach dialog
            _showBreachDialog(_safeZone, pos);
          } else if (inside && _safeZoneBreached) {
            _safeZoneBreached = false;
            _showSnack('You returned to the safe zone.');
            try {
              await _sockService.emitWithQueue('safezone_recovered', {
                'user': _userPhone,
                'session': _sessionCode,
                'timestamp': DateTime.now().toIso8601String(),
              });
            } catch (e) {
              debugPrint('[GEOFENCE] recovered emit error: $e');
            }
          }
        }
      } catch (e, st) {
        debugPrint('[TIMER] Periodic location error (ignored): $e\n$st');
      } finally {
        tickRunning = false;
      }
    });

    if (mounted && !_disposed) {
      _showSnack('Started sharing location to session ${_sessionCode!}.');
    }
    debugPrint('[SHARE] started sharing (timer created)');
  }

  Future<void> _stopSharing() async {
    debugPrint(
        '[SHARE] stopSharing called (isSharing=$_isSharing sharingActive=$_sharingActive)');
    _sharingActive = false;
    try {
      _shareTimer?.cancel();
      _shareTimer = null;
      debugPrint('[SHARE] timer cancelled');
    } catch (e, st) {
      debugPrint('[SHARE] Timer cancel error: $e\n$st');
    }

    if (mounted && !_disposed) {
      try {
        setState(() {
          _isSharing = false;
        });
      } catch (e, st) {
        debugPrint('[SHARE] setState on stopSharing failed: $e\n$st');
      }
    } else {
      _isSharing = false;
    }

    _showSnack('Stopped sharing location.');
    debugPrint('[SHARE] stopped sharing');
  }

  Future<void> _findCompanion() async {
    if ((_userPhone ?? '').trim().isEmpty) {
      _showSnack('No user phone saved. Sign in first.');
      return;
    }

    if (mounted && !_disposed) setState(() => _isFinding = true);
    try {
      Position pos = _lastPosition ??
          await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high);

      final resp = await findCompanion(
        username: _userPhone!,
        latitude: pos.latitude,
        longitude: pos.longitude,
        sessionCode: _sessionCode,
      );

      debugPrint('[API] findCompanion raw: $resp');
      final pretty = const JsonEncoder.withIndent('  ').convert(resp);
      if (mounted && !_disposed) setState(() => _findResponsePretty = pretty);

      if (mounted && !_disposed) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(child: Text(pretty)),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('[API] findCompanion error: $e\n$st');
      _showSnack('Find failed: $e');
    } finally {
      if (mounted && !_disposed) setState(() => _isFinding = false);
    }
  }

  Future<void> _simulateBreach() async {
    if ((_userPhone ?? '').isEmpty || (_sessionCode ?? '').isEmpty) {
      _showSnack('Need user phone + active session to simulate breach.');
      return;
    }

    try {
      double lat;
      double lng;

      if (_lastPosition != null) {
        lat = _lastPosition!.latitude + 0.01; // offset
        lng = _lastPosition!.longitude + 0.01;
      } else {
        lat = 12.9716 + 0.01;
        lng = 77.5946 + 0.01;
      }

      final body = {
        "user": _userPhone!,
        "session": _sessionCode!,
        "latitude": lat,
        "longitude": lng,
        "timestamp": DateTime.now().toIso8601String(),
      };

      debugPrint('[BREACH] Simulating breach with payload=$body');

      await reportSafeZoneBreach(
        user: _userPhone!,
        session: _sessionCode!,
        latitude: lat,
        longitude: lng,
      );

      try {
        await _sockService.emitWithQueue('safezone_breach', body);
      } catch (_) {}

      _showSnack('Simulated safe zone breach sent.');
    } catch (e, st) {
      debugPrint('[BREACH] simulate error: $e\n$st');
      _showSnack('Simulate breach failed: $e');
    }
  }

  // ---------------- Simple breach dialog ----------------
  Future<void> _showBreachDialog(
      Map<String, dynamic>? zone, Position pos) async {
    if (!mounted || _disposed) return;
    try {
      final lat = pos.latitude.toStringAsFixed(6);
      final lng = pos.longitude.toStringAsFixed(6);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Safe zone breach'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('You left your safe zone.\nLocation: $lat, $lng'),
              if (zone != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Zone center: ${zone['latitude']?.toStringAsFixed(6) ?? '-'}, ${zone['longitude']?.toStringAsFixed(6) ?? '-'}\nradius: ${zone['radiusMeters']?.toStringAsFixed(0) ?? '-'} m',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Dismiss'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  if (_userPhone != null) {
                    await sendSOS(
                      latitude: pos.latitude,
                      longitude: pos.longitude,
                      message: 'Auto SOS: left safe zone!',
                      userPhoneNumber: _userPhone!,
                    );
                    _showSnack('SOS triggered (server notified contacts).');
                  } else {
                    _showSnack('No user phone known; cannot send SOS.');
                  }
                } catch (e) {
                  debugPrint('[BREACH_DIALOG] SOS send failed: $e');
                  _showSnack('Failed to send SOS: $e');
                }
              },
              child: const Text('Send SOS'),
            ),
          ],
        ),
      );
    } catch (e, st) {
      debugPrint('[BREACH_DIALOG] error: $e\n$st');
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final loggedText = (_userPhone ?? '').isNotEmpty
        ? 'Logged in as $_userPhone'
        : 'Not logged in';

    final createBtn = ElevatedButton(
      onPressed: _isCreating ? null : _createSession,
      child: _isCreating
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2))
          : const Text('Create Session'),
    );

    final joinBtn = ElevatedButton(
      onPressed: _isJoining ? null : _joinSession,
      child: _isJoining
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2))
          : const Text('Join'),
    );

    final startSharingBtn = ElevatedButton.icon(
      onPressed: (_sessionCode != null && !_isSharing)
          ? _startSharing
          : (_isSharing ? _stopSharing : null),
      icon: Icon(_isSharing ? Icons.stop : Icons.play_arrow),
      label: Text(_isSharing ? 'Stop Sharing' : 'Start Sharing'),
      style: ElevatedButton.styleFrom(
          backgroundColor:
              (_sessionCode != null) ? Colors.green[700] : Colors.grey),
    );

    final setSafeZoneBtn = ElevatedButton.icon(
      onPressed: () async {
        if (_lastPosition == null) {
          _showSnack('No location available to set safe-zone center.');
          return;
        }
        final center = _lastPosition!;
        // targetUser is the owner of the zone; for now it is the logged-in user.
        final targetUser = _userPhone ?? '';
        // check permission before showing dialog
        bool allowed = true;
        try {
          allowed = await canEditZone(targetUser);
        } catch (e) {
          debugPrint('[GEOFENCE] permission check failed: $e');
          allowed = false;
        }
        if (!allowed) {
          _showSnack(
              'You do not have permission to edit this user\'s safe zone.');
          return;
        }

        final radiusCtrl = TextEditingController(text: '200');
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Set Safe Zone'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    'Center: ${center.latitude.toStringAsFixed(6)}, ${center.longitude.toStringAsFixed(6)}'),
                const SizedBox(height: 8),
                TextField(
                  controller: radiusCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Radius (meters)'),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              TextButton(
                onPressed: () async {
                  final r = double.tryParse(radiusCtrl.text.trim()) ?? 200.0;
                  if (mounted && !_disposed) {
                    setState(() {
                      _safeZone = {
                        'latitude': center.latitude,
                        'longitude': center.longitude,
                        'radiusMeters': r,
                      };
                      _safeZoneBreached = false;
                    });
                  } else {
                    _safeZone = {
                      'latitude': center.latitude,
                      'longitude': center.longitude,
                      'radiusMeters': r,
                    };
                    _safeZoneBreached = false;
                  }
                  Navigator.pop(ctx);
                  _updateGeofenceCircle();
                  // CALL updated save function (includes actor)
                  await _saveSafeZoneToServer(
                      center.latitude, center.longitude, r);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
      icon: const Icon(Icons.circle_outlined),
      label: const Text('Set Safe Zone'),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[700]),
    );

    final double updatesHeight = MediaQuery.of(context).size.height * 0.26;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Travel Partner'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                Icon(
                  _socketConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: _socketConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                if (_pendingQueueCount > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('Queued: $_pendingQueueCount',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.white)),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Force Reconnect',
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    _showSnack('Reconnecting socket...');
                    await _sockService.forceReconnect();
                  },
                ),
                IconButton(
                  tooltip: 'Relationships',
                  icon: const Icon(Icons.group),
                  onPressed: () async {
                    try {
                      final user = _userPhone;
                      if (user == null || user.isEmpty) {
                        _showSnack('Sign in first to view relationships.');
                        return;
                      }
                      final resp = await getRelationshipsForUser(user);
                      if (!mounted || _disposed) return;
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (ctx) => Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Relationships',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18)),
                                const SizedBox(height: 12),
                                if (resp is Map &&
                                    resp['relationships'] != null)
                                  ...List<Widget>.from((resp['relationships']
                                          as List)
                                      .map((r) => RelationshipTile(
                                          rel: Map<String, dynamic>.from(r))))
                                else
                                  const Text('No relationships'),
                              ],
                            ),
                          ),
                        ),
                      );
                    } catch (e) {
                      debugPrint('[TP] open relationships failed: $e');
                      _showSnack('Failed to load relationships: $e');
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(loggedText),
              const SizedBox(height: 12),
              SizedBox(
                height: 240,
                child: Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: GoogleMap(
                      initialCameraPosition: _initialCamera,
                      myLocationEnabled: _lastPosition != null,
                      myLocationButtonEnabled: true,
                      zoomControlsEnabled: false,
                      onMapCreated: (c) {
                        _mapController = c;
                        _updateGeofenceCircle();
                        if (_lastPosition != null) {
                          _moveCameraTo(LatLng(_lastPosition!.latitude,
                              _lastPosition!.longitude));
                        }
                      },
                      markers: Set<Marker>.of(_markers.values),
                      circles: _circles,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: createBtn),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                            controller: _joinCodeCtrl,
                            decoration: const InputDecoration(
                                hintText: 'Enter session code',
                                border: OutlineInputBorder())),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(width: 80, child: joinBtn),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      const Text('Session code: '),
                      Expanded(
                          child: Text(_sessionCode ?? '— none —',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold))),
                      IconButton(
                          tooltip: 'Share Code',
                          icon: const Icon(Icons.share),
                          onPressed:
                              _sessionCode == null ? null : _shareSessionCode),
                      IconButton(
                          tooltip: 'Copy Code',
                          icon: const Icon(Icons.copy),
                          onPressed: _sessionCode == null
                              ? null
                              : () async {
                                  if (_sessionCode != null &&
                                      _sessionCode!.isNotEmpty) {
                                    try {
                                      await Clipboard.setData(
                                          ClipboardData(text: _sessionCode!));
                                      _showSnack(
                                          'Copied session code to clipboard.');
                                    } catch (e, st) {
                                      debugPrint(
                                          '[UI] Clipboard write failed: $e\n$st');
                                      _showSnack('Copy failed.');
                                    }
                                  } else {
                                    _showSnack(
                                        'No session code available to copy.');
                                  }
                                })
                    ])
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    children: [
                      Row(children: [
                        Expanded(child: startSharingBtn),
                        const SizedBox(width: 12),
                        Expanded(child: setSafeZoneBtn)
                      ]),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Last: ${_lastPosition != null ? '${_lastPosition!.latitude.toStringAsFixed(6)}, ${_lastPosition!.longitude.toStringAsFixed(6)}' : '—'}',
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                          'Sends your coordinates every 10 seconds while sharing.'),
                      if (_safeZone != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Text(
                            'Safe zone: ${_safeZone!['latitude']?.toStringAsFixed(6) ?? '-'}, ${_safeZone!['longitude']?.toStringAsFixed(6) ?? '-'} radius ${_safeZone!['radiusMeters']?.toStringAsFixed(0) ?? '-'} m',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black87),
                          ),
                        )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(children: [
                    Row(children: [
                      ElevatedButton.icon(
                          onPressed: _isFinding ? null : _findCompanion,
                          icon: const Icon(Icons.person_search),
                          label: const Text('Find')),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(_findResponsePretty.isEmpty
                              ? 'Shows raw response for now. We can prettify later.'
                              : 'Result available')),
                    ]),
                    if (_findResponsePretty.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Text(_findResponsePretty,
                              style: const TextStyle(fontSize: 12))),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _simulateBreach,
                      icon: const Icon(Icons.warning),
                      label: const Text('Simulate Breach'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: updatesHeight,
                child: Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Text('Live updates',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Icon(
                                _socketConnected
                                    ? Icons.cloud_done
                                    : Icons.cloud_off,
                                color: _socketConnected
                                    ? Colors.green
                                    : Colors.red),
                            const SizedBox(width: 8),
                            Text(_socketConnected
                                ? 'Socket connected'
                                : 'Socket disconnected'),
                          ]),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _liveUpdates.isEmpty
                                ? const Center(
                                    child: Text('No live updates yet'))
                                : ListView.builder(
                                    itemCount: _liveUpdates.length,
                                    itemBuilder: (ctx, i) {
                                      final u = _liveUpdates[i];
                                      final ts = u['timestamp'] ?? '';
                                      final latStr = (u['latitude'] is num)
                                          ? (u['latitude'] as num)
                                              .toStringAsFixed(6)
                                          : (u['latitude']?.toString() ?? '-');
                                      final lngStr = (u['longitude'] is num)
                                          ? (u['longitude'] as num)
                                              .toStringAsFixed(6)
                                          : (u['longitude']?.toString() ?? '-');
                                      return ListTile(
                                        dense: true,
                                        title: Text(
                                            '${u['user'] ?? 'unknown'} → $latStr, $lngStr'),
                                        subtitle: Text(
                                            '$ts ${u['session'] != null ? ' (session ${u['session']})' : ''}'),
                                      );
                                    },
                                  ),
                          )
                        ]),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ]),
          ),
        ),
      ),
    );
  }
}
