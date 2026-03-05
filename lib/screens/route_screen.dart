import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

// ✅ MAP
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class PlaceSuggestion {
  final String label;
  final double lat;
  final double lon;

  PlaceSuggestion({
    required this.label,
    required this.lat,
    required this.lon,
  });
}

class RouteScreen extends StatefulWidget {
  const RouteScreen({super.key});

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  // -------------------------
  // CONFIG
  // -------------------------
  static const bool useSmartRouteDeviation = true; // Smart OSRM mode ON
  static const int deviationSeconds = 120; // 60s + 60s
  static const double routeToleranceMeters = 300;
  static const int cooldownMinutesAfterAlert = 10;
  static const double ignoreIfSpeedBelowKmh = 5;

  // -------------------------
  // UI State
  // -------------------------
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();
  StreamSubscription<Position>? _geoSub;

  bool _geofenceActive = false;
  bool _geofenceTriggeredOnce = false;

  double? _distFromStartM;
  double? _distFromEndM;

  double? _minDistToAnyRouteM;
  int _routesCount = 0;

  bool _isStartActive = true;
  Timer? _debounce;
  bool _isLoading = false;

  List<PlaceSuggestion> _suggestions = [];
  PlaceSuggestion? _selectedStart;
  PlaceSuggestion? _selectedEnd;

  // -------------------------
  // MAP State
  // -------------------------
  final MapController _mapController = MapController();
  LatLng? _currentLatLng; // live GPS

  // -------------------------
  // Smart Route State
  // -------------------------
  final List<List<_LL>> _osrmRoutes = [];
  DateTime? _outsideSince;
  DateTime? _cooldownUntil;

  // -------------------------
  // Permissions
  // -------------------------
  Future<bool> _ensureLocationPermission() async {
    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  // -------------------------
  // Webhook (UNCHANGED)
  // -------------------------
  Future<void> _sendGeofenceToWebhook({
    required double lat,
    required double lon,
    required double distFromStartM,
    required double distFromEndM,
  }) async {
    final url =
    Uri.parse("https://novanode3.app.n8n.cloud/webhook/geofence-alert");

    try {
      await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "overspeedCount": 0,
          "speed": 0,
          "limit": 0,
          "latitude": lat,
          "longitude": lon,
          "tripId": "geofence",

          "event": "geofence_violation",
          "startLocation": _selectedStart?.label,
          "endLocation": _selectedEnd?.label,
          "startLat": _selectedStart?.lat,
          "startLon": _selectedStart?.lon,
          "endLat": _selectedEnd?.lat,
          "endLon": _selectedEnd?.lon,
          "distanceFromStart": distFromStartM,
          "distanceFromEnd": distFromEndM,
          "mapsLink": "https://www.google.com/maps?q=$lat,$lon",
        }),
      );

      print("✅ Geofence webhook sent");
    } catch (e) {
      print("❌ Webhook error: $e");
    }
  }
  Future<void> _setStartAsCurrentLocation() async {
    final ok = await _ensureLocationPermission();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enable location permission")),
        );
      }
      return;
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );

    setState(() {
      _selectedStart = PlaceSuggestion(
        label: "Current Location",
        lat: pos.latitude,
        lon: pos.longitude,
      );
      _startController.text = "Current Location";
      _suggestions = [];
    });

    // Move map to current location
    _mapController.move(LatLng(pos.latitude, pos.longitude), 14);

    // If destination already selected, you can optionally fetch routes immediately
    // (not mandatory)
  }
  // -------------------------
  // OSRM Routes Fetch
  // -------------------------
  Future<void> _fetchOsrmRoutes() async {
    _osrmRoutes.clear();
    _routesCount = 0;
    _minDistToAnyRouteM = null;

    if (_selectedStart == null || _selectedEnd == null) return;

    final start = _selectedStart!;
    final end = _selectedEnd!;

    final url = Uri.parse(
      "https://router.project-osrm.org/route/v1/driving/"
          "${start.lon},${start.lat};${end.lon},${end.lat}"
          "?alternatives=true&overview=full&geometries=geojson",
    );

    try {
      final res = await http.get(url, headers: {
        "User-Agent": "speed_monitor_flutter_app",
      });

      if (res.statusCode != 200) {
        print("❌ OSRM error: ${res.statusCode} ${res.body}");
        return;
      }

      final data = jsonDecode(res.body);
      final routes = (data["routes"] as List?) ?? [];

      for (final r in routes) {
        final coords = r["geometry"]?["coordinates"];
        if (coords is List) {
          final pts = <_LL>[];
          for (final c in coords) {
            if (c is List && c.length >= 2) {
              final lon = (c[0] as num).toDouble();
              final lat = (c[1] as num).toDouble();
              pts.add(_LL(lat, lon));
            }
          }
          final down = _downsample(pts);
          if (down.length >= 2) _osrmRoutes.add(down);
        }
      }

      setState(() {
        _routesCount = _osrmRoutes.length;
      });

      // ✅ After loading routes, zoom map to fit
      _fitMapToRoutes();

      print("✅ OSRM routes loaded: $_routesCount");
    } catch (e) {
      print("❌ OSRM fetch error: $e");
    }
  }

  List<_LL> _downsample(List<_LL> pts) {
    if (pts.length <= 500) return pts;
    final step = (pts.length / 500).ceil();
    final out = <_LL>[];
    for (int i = 0; i < pts.length; i += step) out.add(pts[i]);
    if (out.last.lat != pts.last.lat || out.last.lon != pts.last.lon) {
      out.add(pts.last);
    }
    return out;
  }

  void _fitMapToRoutes() {
    // Prefer route bounds. If no routes, just center between start & end.
    LatLngBounds? bounds;

    for (final route in _osrmRoutes) {
      for (final p in route) {
        final ll = LatLng(p.lat, p.lon);
        if (bounds == null) {
          bounds = LatLngBounds(ll, ll);
        } else {
          bounds.extend(ll);
        }
      }
    }

    // Also include start/end points
    if (_selectedStart != null) {
      final s = LatLng(_selectedStart!.lat, _selectedStart!.lon);
      bounds ??= LatLngBounds(s, s);
      bounds.extend(s);
    }
    if (_selectedEnd != null) {
      final e = LatLng(_selectedEnd!.lat, _selectedEnd!.lon);
      bounds ??= LatLngBounds(e, e);
      bounds.extend(e);
    }

    if (bounds == null) return;

    // Add padding to the bounds (approx)
    final center = bounds.center;
    // `fitCamera` is available in newer flutter_map; fallback by moving to center.
    // We'll do simple center move and keep zoom reasonable.
    _mapController.move(center, 12);
  }

  // -------------------------
  // Distance to any route
  // -------------------------
  double _minDistanceToAnyRouteMeters(double lat, double lon) {
    if (_osrmRoutes.isEmpty) return double.infinity;
    double best = double.infinity;
    for (final route in _osrmRoutes) {
      final d = _minDistanceToPolylineMeters(lat, lon, route);
      if (d < best) best = d;
    }
    return best;
  }

  double _minDistanceToPolylineMeters(double lat, double lon, List<_LL> line) {
    if (line.length < 2) return double.infinity;

    double best = double.infinity;

    final mPerDegLat = 111320.0;
    final mPerDegLon = 111320.0 * math.cos(lat * math.pi / 180.0);

    final px = lon * mPerDegLon;
    final py = lat * mPerDegLat;

    for (int i = 0; i < line.length - 1; i++) {
      final a = line[i];
      final b = line[i + 1];

      final ax = a.lon * mPerDegLon;
      final ay = a.lat * mPerDegLat;
      final bx = b.lon * mPerDegLon;
      final by = b.lat * mPerDegLat;

      final d = _pointToSegmentDistance(px, py, ax, ay, bx, by);
      if (d < best) best = d;
      if (best <= 5) return best;
    }

    return best;
  }

  double _pointToSegmentDistance(
      double px,
      double py,
      double ax,
      double ay,
      double bx,
      double by,
      ) {
    final vx = bx - ax;
    final vy = by - ay;
    final wx = px - ax;
    final wy = py - ay;

    final c1 = vx * wx + vy * wy;
    if (c1 <= 0) {
      return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
    }

    final c2 = vx * vx + vy * vy;
    if (c2 <= c1) {
      return math.sqrt((px - bx) * (px - bx) + (py - by) * (py - by));
    }

    final t = c1 / c2;
    final projX = ax + t * vx;
    final projY = ay + t * vy;

    return math.sqrt(
        (px - projX) * (px - projX) + (py - projY) * (py - projY));
  }

  bool _inCooldown() {
    if (_cooldownUntil == null) return false;
    return DateTime.now().isBefore(_cooldownUntil!);
  }

  // -------------------------
  // Start / Stop
  // -------------------------
  Future<void> _startGeofencing() async {
    if (_selectedStart == null || _selectedEnd == null) return;

    final ok = await _ensureLocationPermission();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enable location permission")),
        );
      }
      return;
    }

    setState(() {
      _geofenceActive = true;
      _geofenceTriggeredOnce = false;
      _distFromStartM = null;
      _distFromEndM = null;
      _minDistToAnyRouteM = null;
      _routesCount = 0;
    });

    if (useSmartRouteDeviation) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Fetching routes (OSRM)...")),
        );
      }
      await _fetchOsrmRoutes();
      if (_osrmRoutes.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Could not load routes. Using old 1km rule.")),
        );
      }
    }

    _outsideSince = null;

    _geoSub?.cancel();
    _geoSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 10,
      ),
    ).listen((pos) async {
      if (!_geofenceActive) return;

      // ✅ update live marker + follow camera softly
      final curr = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _currentLatLng = curr;
      });
      _mapController.move(curr, _mapController.camera.zoom);

      final dStart = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        _selectedStart!.lat,
        _selectedStart!.lon,
      );

      final dEnd = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        _selectedEnd!.lat,
        _selectedEnd!.lon,
      );

      setState(() {
        _distFromStartM = dStart;
        _distFromEndM = dEnd;
      });

      final speedKmh = (pos.speed * 3.6);
      if (speedKmh < ignoreIfSpeedBelowKmh) {
        _outsideSince = null;
        return;
      }

      final canUseSmart = useSmartRouteDeviation && _osrmRoutes.isNotEmpty;

      if (canUseSmart) {
        final minD = _minDistanceToAnyRouteMeters(pos.latitude, pos.longitude);
        setState(() => _minDistToAnyRouteM = minD);

        final nearAnyRoute = minD <= routeToleranceMeters;

        if (nearAnyRoute) {
          _outsideSince = null;
          return;
        } else {
          _outsideSince ??= DateTime.now();
          final outsideFor =
              DateTime.now().difference(_outsideSince!).inSeconds;

          if (!_geofenceTriggeredOnce &&
              !_inCooldown() &&
              outsideFor >= deviationSeconds) {
            _geofenceTriggeredOnce = true;
            _cooldownUntil = DateTime.now()
                .add(const Duration(minutes: cooldownMinutesAfterAlert));

            await _sendGeofenceToWebhook(
              lat: pos.latitude,
              lon: pos.longitude,
              distFromStartM: dStart,
              distFromEndM: dEnd,
            );

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text("Geofence alert sent ✅ (Smart Route)")),
              );
            }
          }
        }

        return;
      }

      // OLD fallback rule (unchanged)
      if (!_geofenceTriggeredOnce && dStart > 1000 && dEnd > 1000) {
        _geofenceTriggeredOnce = true;

        await _sendGeofenceToWebhook(
          lat: pos.latitude,
          lon: pos.longitude,
          distFromStartM: dStart,
          distFromEndM: dEnd,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Geofence alert sent ✅ (Old Rule)")),
          );
        }
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Geofencing started ✅")),
      );
    }
  }

  void _stopGeofencing() {
    _geoSub?.cancel();
    setState(() {
      _geofenceActive = false;
      _distFromStartM = null;
      _distFromEndM = null;
      _minDistToAnyRouteM = null;
      _routesCount = 0;
      _currentLatLng = null;
    });

    _outsideSince = null;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Geofencing stopped")),
    );
  }

  // -------------------------
  // Photon Search (same)
  // -------------------------
  Future<void> _searchPhoton(String query) async {
    final q = query.trim();
    if (q.length < 3) {
      setState(() => _suggestions = []);
      return;
    }

    setState(() => _isLoading = true);

    final url = Uri.parse(
      "https://photon.komoot.io/api/?q=${Uri.encodeComponent(q)}&limit=6",
    );

    try {
      final res = await http.get(
        url,
        headers: {"User-Agent": "speed_monitor_flutter_app"},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final features = (data["features"] as List?) ?? [];

        final results = <PlaceSuggestion>[];

        for (final f in features) {
          final props = f["properties"] ?? {};
          final coords = f["geometry"]?["coordinates"];

          if (coords is List && coords.length >= 2) {
            final lon = (coords[0] as num).toDouble();
            final lat = (coords[1] as num).toDouble();

            final name = (props["name"] ?? "").toString();
            final city = (props["city"] ?? "").toString();
            final state = (props["state"] ?? "").toString();
            final country = (props["country"] ?? "").toString();

            final parts = [name, city, state, country]
                .where((e) => e.trim().isNotEmpty)
                .toList();

            final label = parts.isEmpty ? "Unknown place" : parts.join(", ");

            results.add(PlaceSuggestion(label: label, lat: lat, lon: lon));
          }
        }

        setState(() => _suggestions = results);
      } else {
        setState(() => _suggestions = []);
      }
    } catch (_) {
      setState(() => _suggestions = []);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _searchPhoton(value);
    });
  }

  void _selectSuggestion(PlaceSuggestion s) {
    setState(() {
      if (_isStartActive) {
        _selectedStart = s;
        _startController.text = s.label;
      } else {
        _selectedEnd = s;
        _endController.text = s.label;
      }
      _suggestions = [];
    });

    FocusScope.of(context).unfocus();

    // ✅ show markers on map and move camera
    if (_selectedStart != null && _selectedEnd != null) {
      final center = LatLng(
        (_selectedStart!.lat + _selectedEnd!.lat) / 2,
        (_selectedStart!.lon + _selectedEnd!.lon) / 2,
      );
      _mapController.move(center, 12);
    } else if (_selectedStart != null) {
      _mapController.move(LatLng(_selectedStart!.lat, _selectedStart!.lon), 14);
    } else if (_selectedEnd != null) {
      _mapController.move(LatLng(_selectedEnd!.lat, _selectedEnd!.lon), 14);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _geoSub?.cancel();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  // -------------------------
  // Build polylines for map
  // -------------------------
  List<Polyline> _buildRoutePolylines() {
    if (_osrmRoutes.isEmpty) return [];

    final polylines = <Polyline>[];

    for (int i = 0; i < _osrmRoutes.length; i++) {
      final route = _osrmRoutes[i];
      final pts = route.map((p) => LatLng(p.lat, p.lon)).toList();

      polylines.add(
        Polyline(
          points: pts,
          strokeWidth: i == 0 ? 6 : 4,
          // Use different opacity for alternatives; color kept consistent.
          color: i == 0
              ? Colors.blueAccent
              : Colors.blueAccent.withOpacity(0.45),
        ),
      );
    }

    return polylines;
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    if (_selectedStart != null) {
      markers.add(
        Marker(
          width: 44,
          height: 44,
          point: LatLng(_selectedStart!.lat, _selectedStart!.lon),
          child: const Icon(Icons.my_location, size: 34, color: Colors.green),
        ),
      );
    }

    if (_selectedEnd != null) {
      markers.add(
        Marker(
          width: 44,
          height: 44,
          point: LatLng(_selectedEnd!.lat, _selectedEnd!.lon),
          child: const Icon(Icons.flag, size: 34, color: Colors.redAccent),
        ),
      );
    }

    if (_currentLatLng != null) {
      markers.add(
        Marker(
          width: 44,
          height: 44,
          point: _currentLatLng!,
          child:
          const Icon(Icons.directions_car, size: 34, color: Colors.black87),
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final polylines = _buildRoutePolylines();
    final markers = _buildMarkers();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ✅ MAP TOP
            SizedBox(
              height: 260,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(18.5204, 73.8567),
                    initialZoom: 12,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.speedmonitor',
                    ),
                    if (polylines.isNotEmpty)
                      PolylineLayer(polylines: polylines),
                    if (markers.isNotEmpty) MarkerLayer(markers: markers),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ✅ REST UI (same layout, scrollable)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Route Watch",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color:
                        Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _SearchField(
                      label: "Start (From)",
                      controller: _startController,
                      icon: Icons.my_location,
                      onTap: () async {
                        setState(() => _isStartActive = true);

                        final action = await showModalBottomSheet<String>(
                          context: context,
                          builder: (context) {
                            return SafeArea(
                              child: Wrap(
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.my_location),
                                    title: const Text("Use Current Location"),
                                    onTap: () => Navigator.pop(context, "current"),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.edit_location_alt),
                                    title: const Text("Enter Manually"),
                                    onTap: () => Navigator.pop(context, "manual"),
                                  ),
                                ],
                              ),
                            );
                          },
                        );

                        if (action == "current") {
                          await _setStartAsCurrentLocation();
                        } else {
                          // manual: just focus the field and let Photon search work
                          // nothing special needed
                        }
                      },
                      onChanged: _onQueryChanged,
                    ),
                    const SizedBox(height: 10),

                    _SearchField(
                      label: "Destination (To)",
                      controller: _endController,
                      icon: Icons.location_on,
                      onTap: () => setState(() => _isStartActive = false),
                      onChanged: _onQueryChanged,
                    ),

                    const SizedBox(height: 10),

                    // Suggestions list
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.black12),
                          color: Theme.of(context).cardColor.withOpacity(0.6),
                        ),
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : (_suggestions.isEmpty
                            ? Center(
                          child: Text(
                            "Type to search places...",
                            style: TextStyle(
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withOpacity(0.7),
                            ),
                          ),
                        )
                            : ListView.separated(
                          itemCount: _suggestions.length,
                          separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final s = _suggestions[index];
                            return ListTile(
                              leading: Icon(
                                _isStartActive
                                    ? Icons.place
                                    : Icons.flag,
                              ),
                              title: Text(s.label),
                              subtitle: Text(
                                "${s.lat.toStringAsFixed(5)}, ${s.lon.toStringAsFixed(5)}",
                              ),
                              onTap: () => _selectSuggestion(s),
                            );
                          },
                        )),
                      ),
                    ),

                    const SizedBox(height: 12),

                    ElevatedButton.icon(
                      onPressed: () {
                        if (_selectedStart == null || _selectedEnd == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  "Please select Start and Destination from suggestions"),
                            ),
                          );
                          return;
                        }

                        if (_geofenceActive) {
                          _stopGeofencing();
                        } else {
                          _startGeofencing();
                        }
                      },
                      icon: Icon(
                          _geofenceActive ? Icons.stop : Icons.play_arrow),
                      label: Text(_geofenceActive
                          ? "Stop Geofencing"
                          : "Start Geofencing"),
                    ),

                    const SizedBox(height: 10),

                    ElevatedButton(
                      onPressed: () async {
                        if (_selectedStart == null || _selectedEnd == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    "Select start and destination first")),
                          );
                          return;
                        }

                        double fakeLat = _selectedStart!.lat + 0.02;
                        double fakeLon = _selectedStart!.lon + 0.02;

                        await _sendGeofenceToWebhook(
                          lat: fakeLat,
                          lon: fakeLon,
                          distFromStartM: 2000,
                          distFromEndM: 2000,
                        );

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text("Test Geofence Alert Sent")),
                        );
                      },
                      child: const Text("TEST GEOFENCE ALERT"),
                    ),

                    if (_geofenceActive)
                      Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.black12),
                          color:
                          Theme.of(context).cardColor.withOpacity(0.6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Geofencing Status",
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Text("Routes loaded: $_routesCount"),
                            Text(
                              "Min distance to any route: "
                                  "${_minDistToAnyRouteM == null ? '--' : _minDistToAnyRouteM!.toStringAsFixed(0)} m",
                            ),
                            Text(
                              "Rule: Outside ALL routes > ${routeToleranceMeters.toStringAsFixed(0)}m for $deviationSeconds sec",
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (_inCooldown())
                              const Text(
                                "Cooldown active (preventing repeated alerts)",
                                style: TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LL {
  final double lat;
  final double lon;
  const _LL(this.lat, this.lon);
}

class _SearchField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;

  const _SearchField({
    required this.label,
    required this.controller,
    required this.icon,
    required this.onTap,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onTap: onTap,
          onChanged: onChanged,
          decoration: InputDecoration(
            prefixIcon: Icon(icon),
            hintText: "Type at least 3 letters...",
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }
}