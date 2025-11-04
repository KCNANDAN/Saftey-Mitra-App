// lib/screens/breach_history_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:frontend/utils/user_prefs.dart';

class BreachHistoryPage extends StatefulWidget {
  const BreachHistoryPage({super.key});

  @override
  State<BreachHistoryPage> createState() => _BreachHistoryPageState();
}

class _BreachHistoryPageState extends State<BreachHistoryPage> {
  static const String _base =
      'http://127.0.0.1:5000'; // change if your server runs elsewhere

  final List<Map<String, dynamic>> _breaches = [];
  bool _loading = false;
  bool _loadingMore = false;
  int _page = 0;
  final int _limit = 20;
  bool _hasMore = true;

  String? _sessionCode;
  String? _userPhone;

  // map
  GoogleMapController? _mapController;
  final Map<String, Marker> _markers = {};
  final Set<Circle> _circles = {};
  final CameraPosition _initialCamera =
      const CameraPosition(target: LatLng(20.5937, 78.9629), zoom: 4.0);

  @override
  void initState() {
    super.initState();
    _sessionCode = UserPrefs.sessionCode;
    _userPhone = UserPrefs.userPhone;
    _fetchInitial();
  }

  Future<void> _fetchInitial() async {
    setState(() {
      _loading = true;
      _page = 0;
      _breaches.clear();
      _hasMore = true;
    });
    await _loadPage(0);
    if (mounted) setState(() => _loading = false);
    await _fetchAndDrawSafeZone();
  }

  Future<void> _fetchAndDrawSafeZone() async {
    if (_sessionCode == null || _sessionCode!.isEmpty) return;
    try {
      final uri =
          Uri.parse('$_base/safe-zone/${Uri.encodeComponent(_sessionCode!)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['zone'] != null) {
          final zone = Map<String, dynamic>.from(decoded['zone']);
          _drawSafeZone(zone);
          if (zone['latitude'] != null && zone['longitude'] != null) {
            final lat = (zone['latitude'] as num).toDouble();
            final lng = (zone['longitude'] as num).toDouble();
            _moveCamera(LatLng(lat, lng), zoom: 13.0);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BreachHistory] fetchSafeZone error: $e');
    }
  }

  void _drawSafeZone(Map<String, dynamic> zone) {
    try {
      final lat = (zone['latitude'] as num).toDouble();
      final lng = (zone['longitude'] as num).toDouble();
      final r = (zone['radiusMeters'] is num)
          ? (zone['radiusMeters'] as num).toDouble()
          : double.tryParse(zone['radiusMeters']?.toString() ?? '') ?? 200.0;
      setState(() {
        _circles.clear();
        _circles.add(Circle(
          circleId: const CircleId('safezone'),
          center: LatLng(lat, lng),
          radius: r,
          strokeWidth: 2,
          strokeColor: Colors.orange,
          fillColor: Colors.orange.withOpacity(0.18),
        ));
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[BreachHistory] drawSafeZone error: $e');
    }
  }

  Future<void> _loadPage(int page) async {
    if (!_hasMore) return;
    if (page == 0) {
      // already cleared by caller
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final q = <String, String>{
        'limit': '$_limit',
        'page': '$page',
      };
      if (_sessionCode != null && _sessionCode!.isNotEmpty) {
        q['session'] = _sessionCode!;
      } else if (_userPhone != null && _userPhone!.isNotEmpty) {
        q['user'] = _userPhone!;
      }

      final uri =
          Uri.parse('$_base/safe-zone/breaches').replace(queryParameters: q);
      final resp = await http.get(uri).timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body is Map && body['breaches'] is List) {
          final List list = body['breaches'];
          final parsed = list.map((e) => Map<String, dynamic>.from(e)).toList();
          setState(() {
            _breaches.addAll(parsed);
            if (parsed.length < _limit) _hasMore = false;
            _page = page;
          });
          // add markers for newly loaded breaches
          for (final b in parsed) {
            _addMarkerForBreach(b);
          }
        } else {
          if (kDebugMode) {
            debugPrint('[BreachHistory] unexpected response: ${resp.body}');
          }
          setState(() => _hasMore = false);
        }
      } else {
        if (kDebugMode) {
          debugPrint('[BreachHistory] http ${resp.statusCode}: ${resp.body}');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BreachHistory] loadPage error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingMore = false;
        });
      }
    }
  }

  void _addMarkerForBreach(Map<String, dynamic> b) {
    try {
      final id = b['_id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString();
      final lat = (b['latitude'] is num)
          ? (b['latitude'] as num).toDouble()
          : double.tryParse(b['latitude']?.toString() ?? '');
      final lng = (b['longitude'] is num)
          ? (b['longitude'] as num).toDouble()
          : double.tryParse(b['longitude']?.toString() ?? '');
      if (lat == null || lng == null) return;
      final marker = Marker(
        markerId: MarkerId('breach_$id'),
        position: LatLng(lat, lng),
        infoWindow: InfoWindow(
            title: 'Breach: ${b['type'] ?? 'exit'}',
            snippet: b['timestamp'] ?? ''),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      );
      _markers['breach_$id'] = marker;
      if (mounted) setState(() {});
    } catch (e) {
      if (kDebugMode) debugPrint('[BreachHistory] addMarker error: $e');
    }
  }

  Future<void> _refresh() async {
    await _fetchInitial();
  }

  void _moveCamera(LatLng pos, {double zoom = 16.0}) {
    try {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(pos, zoom));
    } catch (e) {
      if (kDebugMode) debugPrint('[BreachHistory] moveCamera error: $e');
    }
  }

  String _prettyTime(String? iso) {
    if (iso == null) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  Widget _buildListTile(Map<String, dynamic> b) {
    final id = b['_id']?.toString() ?? '';
    final lat = b['latitude']?.toString() ?? '-';
    final lng = b['longitude']?.toString() ?? '-';
    final type = b['type']?.toString() ?? 'exit';
    final when = _prettyTime(b['timestamp'] ?? b['createdAt']?.toString());

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        title: Text('$type — ${b['user'] ?? '-'}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Time: $when'),
            Text('Location: $lat, $lng'),
            if (b['notified'] != null)
              Text('Notified: ${b['notified'] ? 'yes' : 'no'}',
                  style: const TextStyle(fontSize: 12)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.map_outlined),
              onPressed: () {
                final latNum = (b['latitude'] is num)
                    ? (b['latitude'] as num).toDouble()
                    : double.tryParse(b['latitude']?.toString() ?? '');
                final lngNum = (b['longitude'] is num)
                    ? (b['longitude'] as num).toDouble()
                    : double.tryParse(b['longitude']?.toString() ?? '');
                if (latNum == null || lngNum == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('No location available for this breach.')));
                  return;
                }
                _moveCamera(LatLng(latNum, lngNum), zoom: 15.0);
              },
            ),
          ],
        ),
        onTap: () {
          showModalBottomSheet(
            context: context,
            builder: (ctx) => Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Breach details',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text('User: ${b['user'] ?? '-'}'),
                    Text('Type: ${b['type'] ?? '-'}'),
                    Text('Time: $when'),
                    Text('Location: $lat, $lng'),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        final latNum = (b['latitude'] is num)
                            ? (b['latitude'] as num).toDouble()
                            : double.tryParse(b['latitude']?.toString() ?? '');
                        final lngNum = (b['longitude'] is num)
                            ? (b['longitude'] as num).toDouble()
                            : double.tryParse(b['longitude']?.toString() ?? '');
                        if (latNum != null && lngNum != null) {
                          _moveCamera(LatLng(latNum, lngNum), zoom: 15.0);
                        }
                      },
                      icon: const Icon(Icons.map),
                      label: const Text('View on map'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[700]),
                    )
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapHeight = MediaQuery.of(context).size.height * 0.35;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Breach History'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: mapHeight,
              child: Card(
                margin: const EdgeInsets.all(12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GoogleMap(
                    initialCameraPosition: _initialCamera,
                    myLocationEnabled: false,
                    zoomControlsEnabled: false,
                    onMapCreated: (c) => _mapController = c,
                    markers: Set<Marker>.of(_markers.values),
                    circles: _circles,
                  ),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: _breaches.length + (_hasMore ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i < _breaches.length) {
                            final b = _breaches[i];
                            return _buildListTile(b);
                          } else {
                            if (!_loadingMore) {
                              _loadPage(_page + 1);
                            }
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 18.0),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
