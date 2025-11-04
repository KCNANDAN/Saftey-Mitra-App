// lib/services/socket_service.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

/// Robust socket service with single-instance, guarded init, queueing and defensive listeners.
class SockectService {
  static SockectService? _instance;
  factory SockectService() => _instance ??= SockectService._internal();
  SockectService._internal();

  IO.Socket? _socket;
  String? _url;
  String? _token;
  bool _initializing = false; // guard concurrent inits
  bool _listenersAttached = false; // avoid attaching listeners multiple times

  final Queue<Map<String, dynamic>> _outQueue = Queue<Map<String, dynamic>>();

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _partnerController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _safezoneController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<Map<String, dynamic>> get partnerLocationStream =>
      _partnerController.stream;
  Stream<Map<String, dynamic>> get safeZoneBreachStream =>
      _safezoneController.stream;

  bool get connected => _socket?.connected ?? false;
  int get pendingCount => _outQueue.length;

  /// Whether we have at least tried to initialize a socket instance
  bool get isInitialized => _socket != null;

  /// Initialize or re-init the service. Use url exactly as you need (10.0.2.2 for Android emulator).
  Future<void> init({required String url, String? token}) async {
    debugPrint(
        '[SockectService] init called url=$url tokenProvided=${token != null}');

    // Basic guard: if another init is in progress wait for it to finish
    if (_initializing) {
      debugPrint('[SockectService] init already in progress - returning early');
      return;
    }
    _initializing = true;

    try {
      _url = url;
      _token = token;

      // If socket exists and is connected and token unchanged, keep it
      if (_socket != null) {
        final alreadyConnected = _socket!.connected;
        final sameUrl = (_socket!.io.uri.toString() ?? '') == (_url ?? '');
        final sameToken = _socketAuthMatchesToken(_socket!, _token);
        if (alreadyConnected && sameUrl && sameToken) {
          debugPrint(
              '[SockectService] socket already connected with same config - skipping init');
          _initializing = false;
          return;
        }

        // If socket exists but not connected or token changed, destroy it first
        debugPrint(
            '[SockectService] existing socket found but needs re-init (connected=$alreadyConnected sameToken=$sameToken)');
        await _destroySocket();
      }

      // If token/phone missing, abort init early - caller should decide later
      if (_token == null || _token!.isEmpty) {
        debugPrint(
            '[SockectService] no token provided - aborting init (will not connect)');
        _initializing = false;
        return;
      }

      // socket.io client options - pass token in auth for modern socket.io servers
      final opts = <String, dynamic>{
        'transports': ['websocket', 'polling'],
        'reconnection': true,
        'reconnectionAttempts': 9999,
        'reconnectionDelay': 1000,
        'timeout': 20000,
        'autoConnect': false,
        'auth': {'token': _token},
      };

      debugPrint('[SockectService] creating socket with opts: ${jsonEncode({
            'transports': opts['transports'],
            'reconnection': opts['reconnection'],
            'authProvided': opts['auth'] != null,
            'autoConnect': opts['autoConnect']
          })}');

      // Create socket
      _socket = IO.io(_url!, opts);

      // Attach listeners safely (only once per socket instance)
      _attachListeners();

      // Connect explicitly
      _socket!.connect();
      debugPrint('[SockectService] socket.connect() called');
    } catch (e, st) {
      debugPrint('[SockectService] init exception: $e\n$st');
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  /// Force full reconnect (destroy + init) — only useful if you still have _url
  Future<void> forceReconnect() async {
    debugPrint('[SockectService] forceReconnect requested');
    await _destroySocket();
    if (_url != null) {
      await init(url: _url!, token: _token);
    } else {
      debugPrint('[SockectService] forceReconnect aborted: no url known');
    }
  }

  void joinSession(String code) {
    final payload = {'sessionCode': code};
    if (_socket != null && _socket!.connected) {
      try {
        _socket!.emit('join_session', payload);
        debugPrint('[SockectService] emit join_session -> $payload');
      } catch (e) {
        debugPrint('[SockectService] join_session emit error: $e - queued');
        _outQueue.add({'event': 'join_session', 'payload': payload});
      }
    } else {
      debugPrint('[SockectService] queueing join_session -> $payload');
      _outQueue.add({'event': 'join_session', 'payload': payload});
    }
  }

  Future<void> emitWithQueue(String event, Map<String, dynamic> payload) async {
    final item = {'event': event, 'payload': _sanitizePayload(payload)};
    if (_socket != null && _socket!.connected) {
      try {
        _socket!.emit(event, item['payload']);
        if (kDebugMode) {
          debugPrint('[SockectService] emitted $event: ${item['payload']}');
        }
        return;
      } catch (e) {
        debugPrint('[SockectService] emit failed, queueing: $e');
        _outQueue.add(item);
        _connectionController.add(_socket?.connected ?? false);
        return;
      }
    } else {
      debugPrint('[SockectService] socket disconnected, queueing $event');
      _outQueue.add(item);
      _connectionController.add(false);
      return;
    }
  }

  Future<void> _destroySocket() async {
    try {
      if (_socket != null) {
        debugPrint('[SockectService] destroying socket (id=${_socket?.id})');
        try {
          _socket!.offAny();
        } catch (_) {}
        try {
          _socket!.disconnect();
        } catch (_) {}
        try {
          // destroy may not exist on all client versions - guard it
          _socket!.destroy();
        } catch (_) {}
      }
    } catch (e, st) {
      debugPrint('[SockectService] _destroySocket error: $e\n$st');
    } finally {
      _socket = null;
      _listenersAttached = false;
      try {
        _connectionController.add(false);
      } catch (_) {}
    }
  }

  void dispose() {
    _destroySocket();
    try {
      _connectionController.close();
    } catch (_) {}
    try {
      _partnerController.close();
    } catch (_) {}
    try {
      _safezoneController.close();
    } catch (_) {}
  }

  void _attachListeners() {
    if (_socket == null) return;
    if (_listenersAttached) {
      debugPrint('[SockectService] listeners already attached - skipping');
      return;
    }
    _listenersAttached = true;

    _socket!.onAny((event, data) {
      debugPrint('[SockectService] onAny event=$event data=${_safeLog(data)}');
    });

    _socket!.on('connect', (_) {
      debugPrint('[SockectService] connected -> id=${_socket?.id}');
      _connectionController.add(true);
      _flushQueue();
    });

    _socket!.on('disconnect', (reason) {
      debugPrint('[SockectService] disconnected reason=$reason');
      _connectionController.add(false);
    });

    _socket!.on('connect_error', (err) {
      debugPrint('[SockectService] connect_error: $err');
    });

    _socket!.on('error', (err) {
      debugPrint('[SockectService] socket error: $err');
    });

    _socket!.on('locationUpdate', (data) {
      try {
        final map = _coerceToMap(data);
        if (map.isNotEmpty) _partnerController.add(map);
      } catch (e) {
        debugPrint('[SockectService] locationUpdate handler error: $e');
      }
    });

    _socket!.on('safezone_breach', (data) {
      try {
        final map = _coerceToMap(data);
        if (map.isNotEmpty) _safezoneController.add(map);
      } catch (e) {
        debugPrint('[SockectService] safezone_breach handler error: $e');
      }
    });
  }

  void _flushQueue() {
    if (_socket == null || !_socket!.connected) return;
    while (_outQueue.isNotEmpty) {
      final it = _outQueue.removeFirst();
      try {
        final ev = it['event']?.toString() ?? '';
        final pl = it['payload'] ?? {};
        _socket!.emit(ev, pl);
        debugPrint('[SockectService] flushed queued event $ev -> $pl');
      } catch (e) {
        debugPrint('[SockectService] flush error, requeueing: $e');
        _outQueue.addFirst(it);
        break;
      }
    }
    _connectionController.add(true);
  }

  Map<String, dynamic> _coerceToMap(Object? data) {
    final out = <String, dynamic>{};
    try {
      if (data == null) return out;
      if (data is Map<String, dynamic>) return Map.from(data);
      if (data is Map) return Map.from(data);
      if (data is String) {
        final d = jsonDecode(data);
        if (d is Map) return Map.from(d);
      }
      out['payload'] = data.toString();
    } catch (e) {
      debugPrint('[SockectService] _coerceToMap error: $e data=$data');
    }
    return out;
  }

  Map<String, dynamic> _sanitizePayload(Map<String, dynamic> p) {
    final out = <String, dynamic>{};
    for (final e in p.entries) {
      final k = e.key;
      final v = e.value;
      try {
        if (v == null || v is num || v is bool || v is String) {
          out[k] = v;
        } else if (v is DateTime) {
          out[k] = v.toIso8601String();
        } else if (v is Map) {
          out[k] = v.map((key, value) => MapEntry(key.toString(),
              value is DateTime ? value.toIso8601String() : value));
        } else if (v is List) {
          out[k] =
              v.map((x) => x is DateTime ? x.toIso8601String() : x).toList();
        } else {
          out[k] = v.toString();
        }
      } catch (err) {
        out[k] = v.toString();
      }
    }
    return out;
  }

  String _safeLog(Object? obj) {
    try {
      if (obj == null) return 'null';
      if (obj is String) return obj;
      return jsonEncode(obj);
    } catch (_) {
      return obj.toString();
    }
  }

  bool _socketAuthMatchesToken(IO.Socket s, String? token) {
    try {
      // socket.io client exposes auth on io.opts.auth sometimes; best-effort check
      final auth = (s.io.options as dynamic)?.auth;
      if (auth == null) return false;
      final tok = (auth is Map && auth['token'] != null)
          ? auth['token']?.toString()
          : null;
      return tok != null && tok == token;
    } catch (_) {
      return false;
    }
  }
}
