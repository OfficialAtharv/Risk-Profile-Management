import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

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
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();
  StreamSubscription<Position>? _geoSub;
  bool _geofenceActive = false;
  bool _geofenceTriggeredOnce = false;

  double? _distFromStartM;
  double? _distFromEndM;
  bool _isStartActive = true;

  Timer? _debounce;
  bool _isLoading = false;

  List<PlaceSuggestion> _suggestions = [];
  PlaceSuggestion? _selectedStart;
  PlaceSuggestion? _selectedEnd;
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
  Future<void> _sendGeofenceToWebhook({
    required double lat,
    required double lon,
    required double distFromStartM,
    required double distFromEndM,
  }) async {
    // ✅ Use the SAME webhook URL as your main.dart (overspeed)
    final url = Uri.parse("https://novanode3.app.n8n.cloud/webhook/geofence-alert");

    try {
      await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          // ✅ existing keys (so your workflow triggers)
          "overspeedCount": 0,
          "speed": 0,
          "limit": 0,
          "latitude": lat,
          "longitude": lon,
          "tripId": "geofence",

          // ✅ new keys (for geofence email message)
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
  Future<void> _startGeofencing() async {
    // 1) Start/End must be selected
    if (_selectedStart == null || _selectedEnd == null) return;

    // 2) Permission
    final ok = await _ensureLocationPermission();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enable location permission")),
        );
      }
      return;
    }

    // 3) Reset flags
    setState(() {
      _geofenceActive = true;
      _geofenceTriggeredOnce = false;
      _distFromStartM = null;
      _distFromEndM = null;
    });

    // 4) Start location stream
    _geoSub?.cancel();
    _geoSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 10, // update after ~10 meters
      ),
    ).listen((pos) async {
      // Distance from Start
      final dStart = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        _selectedStart!.lat,
        _selectedStart!.lon,
      );

      // Distance from End
      final dEnd = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        _selectedEnd!.lat,
        _selectedEnd!.lon,
      );

      // Update UI
      if (mounted) {
        setState(() {
          _distFromStartM = dStart;
          _distFromEndM = dEnd;
        });
      }

      // ✅ Rule: if user is >1km away from BOTH start and end
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
            const SnackBar(content: Text("Geofence alert sent ✅")),
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
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Geofencing stopped")),
    );
  }

  Future<void> _searchPhoton(String query) async {
    final q = query.trim();

    // Don’t call API for very small input
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

            results.add(
              PlaceSuggestion(label: label, lat: lat, lon: lon),
            );
          }
        }

        setState(() => _suggestions = results);
      } else {
        setState(() => _suggestions = []);
      }
    } catch (e) {
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
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _geoSub?.cancel();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Route Watch ",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 12),

              _SearchField(
                label: "Start (From)",
                controller: _startController,
                icon: Icons.my_location,
                onTap: () => setState(() => _isStartActive = true),
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
                          _isStartActive ? Icons.place : Icons.flag,
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

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (_selectedStart == null || _selectedEnd == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Please select Start and Destination from suggestions"),
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
                      icon: Icon(_geofenceActive ? Icons.stop : Icons.play_arrow),
                      label: Text(_geofenceActive ? "Stop Geofencing" : "Start Geofencing"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),

                  ),
                ],
              ),
              const SizedBox(height: 10),

              ElevatedButton(
                onPressed: () async {

                  if (_selectedStart == null || _selectedEnd == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Select start and destination first")),
                    );
                    return;
                  }

                  // Fake far away coordinates (2km away)
                  double fakeLat = _selectedStart!.lat + 0.02;
                  double fakeLon = _selectedStart!.lon + 0.02;

                  await _sendGeofenceToWebhook(
                    lat: fakeLat,
                    lon: fakeLon,
                    distFromStartM: 2000,
                    distFromEndM: 2000,
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Test Geofence Alert Sent")),
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
                    color: Theme.of(context).cardColor.withOpacity(0.6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Geofencing Status",
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      // Text(
                      //   "Distance from Start: "
                      //       "${_distFromStartM == null ? '--' : (_distFromStartM! / 1000).toStringAsFixed(2)} km",
                      // ),
                      // Text(
                      //   "Distance from Destination: "
                      //       "${_distFromEndM == null ? '--' : (_distFromEndM! / 1000).toStringAsFixed(2)} km",
                      // ),
                      const SizedBox(height: 6),
                      const Text(
                        "Rule: Alert triggers when BOTH distances > 1.00 km",
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                "Next: We will check current GPS and trigger alert if user goes 1km away.",
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.color
                      ?.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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