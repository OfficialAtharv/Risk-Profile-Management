import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'models/trip_model.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:speed_monitor_flutter/services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '/screens/route_screen.dart';
import 'screens/trip_history_screen.dart';
import 'auth/auth_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final prefs = await SharedPreferences.getInstance();
  final isDarkMode = prefs.getBool('isDarkMode') ?? false;

  themeNotifier.value = isDarkMode ? ThemeMode.dark : ThemeMode.light;

  runApp(const SpeedMonitorApp());
}

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

class SpeedMonitorApp extends StatelessWidget {
  const SpeedMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          home: const AuthWrapper(),
        );
      },
    );
  }
}

class SpeedMonitorScreen extends StatefulWidget {
  final Function(Trip) onTripCreated;

  const SpeedMonitorScreen({
    super.key,
    required this.onTripCreated,
  });

  @override
  State<SpeedMonitorScreen> createState() => _SpeedMonitorScreenState();
}

class _SpeedMonitorScreenState extends State<SpeedMonitorScreen> {
  bool _isTracking = false;
  double _speed = 0.0;
  double? _speedLimit;
  bool _alertSent = false;
  double _totalDistance = 0.0;
  Position? _lastPosition;
  Trip? _currentTrip;
  String? _currentTripId;
  final MapController _mapController = MapController();
  int _overspeedCount = 0;
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;

  StreamSubscription<Position>? _positionStream;

  Future<void> _startTracking() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      return;
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).listen((Position position) {
      if (position.accuracy > 35) return;
      if (_isTracking) {
        if (_lastPosition != null) {
          double distanceInMeters = Geolocator.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );

          _totalDistance += distanceInMeters;
        }

        _lastPosition = position;
        _fetchSpeedLimit(position.latitude, position.longitude);
        _mapController.move(
          LatLng(position.latitude, position.longitude),
          17,
        );
      }

      double speedKmh = position.speed * 3.6;

      if (speedKmh < 3) {
        speedKmh = 0;
      }

      setState(() {
        _speed = speedKmh;
      });

      if (_isTracking && _currentTripId != null) {
        FirestoreService().saveSpeedLog(
          _currentTripId!,
          speedKmh,
          position.latitude,
          position.longitude,
        );
      }

      if (_speedLimit != null && _speedLimit != null && _speed > _speedLimit!!) {
        _overspeedCount++;

        print("Overspeed Count: $_overspeedCount");

        _sendOverspeedToWebhook(
          Position(
            longitude: _lastPosition?.longitude ?? 0,
            latitude: _lastPosition?.latitude ?? 0,
            timestamp: DateTime.now(),
            accuracy: 1,
            altitude: 0,
            altitudeAccuracy: 1,
            heading: 0,
            headingAccuracy: 1,
            speed: _speed / 3.6,
            speedAccuracy: 1,
          ),
        );

        if (_overspeedCount == 5 && !_isSpeaking) {
          _triggerContinuousOverspeedWarning();
        }
      } else {
        _alertSent = false;
      }

      if (speedKmh < _speedLimit! - 5) {
        _alertSent = false;
      }
    });
  }

  DateTime? _lastSpeedLimitFetch;

  Future<void> _fetchSpeedLimit(double lat, double lon) async {
    if (_lastSpeedLimitFetch != null &&
        DateTime.now().difference(_lastSpeedLimitFetch!).inSeconds < 30) {
      return;
    }
    print("Fetching speed for: $lat, $lon");
    _lastSpeedLimitFetch = DateTime.now();

    final query = """
  [out:json];
  way(around:50,$lat,$lon)["highway"];
  out tags;
  """;

    try {
      final response = await http.post(
        Uri.parse("https://overpass-api.de/api/interpreter"),
        body: query,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data["elements"] != null && data["elements"].isNotEmpty) {
          for (var element in data["elements"]) {
            final tags = element["tags"];
            print("Road Tags: $tags");
            if (tags != null && tags["maxspeed"] != null) {
              String raw = tags["maxspeed"].toString();
              raw = raw.replaceAll(RegExp(r'[^0-9]'), '');

              double? parsed = double.tryParse(raw);

              if (parsed != null) {
                setState(() {
                  _speedLimit = parsed;
                });

                print("Updated Speed Limit: $_speedLimit");
                return;
              }
            }
          }
        }
      }
    } catch (e) {
      print("Speed limit fetch error: $e");
    }
    if (_speedLimit == null) {
      setState(() {
        _speedLimit = 60;
      });
    }
  }

  void _stopTracking() {
    _positionStream?.cancel();
    setState(() {
      _speed = 0;
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _createNewTrip() async {
    _totalDistance = 0.0;
    _lastPosition = null;

    Position position = await Geolocator.getCurrentPosition();
    _fetchSpeedLimit(position.latitude, position.longitude);

    List<Placemark> placemarks =
    await placemarkFromCoordinates(position.latitude, position.longitude);

    Placemark place = placemarks.first;
    String area = place.subLocality ?? '';
    String city = place.locality ?? '';
    String startLocationName = area.isNotEmpty ? "$area, $city" : city;

    _currentTrip = Trip(
      startTime: DateTime.now(),
      startLat: position.latitude,
      startLng: position.longitude,
      startLocation: startLocationName,
    );

    print("START LOCATION: $startLocationName");
    print("Current user: ${FirebaseAuth.instance.currentUser?.uid}");
    _currentTripId = await FirestoreService().saveTrip(_currentTrip!);
    widget.onTripCreated(_currentTrip!);
    print("Trip Started with ID: $_currentTripId");
  }

  Future<void> _endCurrentTrip() async {
    if (_currentTrip == null || _currentTripId == null) return;
    if (_lastPosition == null) {
      print("No last position available");
      return;
    }

    Position position = _lastPosition!;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("User not logged in");
      return;
    }

    DateTime endTime = DateTime.now();
    DateTime startTime = _currentTrip!.startTime;
    Duration difference = endTime.difference(startTime);
    String formattedDuration =
        "${difference.inHours.toString().padLeft(2, '0')}:"
        "${(difference.inMinutes % 60).toString().padLeft(2, '0')}:"
        "${(difference.inSeconds % 60).toString().padLeft(2, '0')}";

    List<Placemark> placemarks =
    await placemarkFromCoordinates(position.latitude, position.longitude);

    Placemark place = placemarks.first;
    String area = place.subLocality ?? '';
    String city = place.locality ?? '';
    String endLocationName = area.isNotEmpty ? "$area, $city" : city;

    _currentTrip!.endTrip(
      endTime: endTime,
      endLat: position.latitude,
      endLng: position.longitude,
      duration: formattedDuration,
      distance: _totalDistance,
      endLocation: endLocationName,
    );

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('trips')
        .doc(_currentTripId)
        .update(_currentTrip!.toMap());

    print("Trip updated successfully: $_currentTripId");
  }

  Future<void> _initTTS() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    await _flutterTts.awaitSpeakCompletion(true);
    await _flutterTts.setSharedInstance(true);
    await _flutterTts.setQueueMode(1);
  }

  @override
  void initState() {
    super.initState();
    _initTTS();

    _flutterTts.setCompletionHandler(() {
      print("Speech Completed");
      _isSpeaking = false;
      _overspeedCount = 0;
    });

    _flutterTts.setErrorHandler((msg) {
      print("TTS Error: $msg");
      _isSpeaking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color primaryText = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final Color secondaryText =
    (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)
        .withOpacity(0.68);

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [
              Color(0xFF040B1A),
              Color(0xFF071225),
              Color(0xFF0A1730),
            ]
                : [
              const Color(0xFFF7F9FC),
              Colors.white,
              const Color(0xFFF2F5FA),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
            child: Column(
              children: [
                const SizedBox(height: 4),

                /// HEADER
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: isDark
                        ? const LinearGradient(
                      colors: [
                        Color(0xFF0C1830),
                        Color(0xFF0A1426),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                        : LinearGradient(
                      colors: [
                        Colors.white,
                        Colors.grey.shade100,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.black.withOpacity(0.05),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withOpacity(0.30)
                            : Colors.black.withOpacity(0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Image.asset(
                        "assets/images/jeevan4.png",
                        height: 48,
                        scale: 2.0,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "JEEVAN",
                          style: TextStyle(
                            color: primaryText,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0E223E)
                              : Colors.blue.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withOpacity(0.05)
                                : Colors.blue.withOpacity(0.12),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF25D366),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "GPS Strong",
                              style: TextStyle(
                                color: primaryText,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                /// MAP CARD
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: isDark
                        ? const LinearGradient(
                      colors: [
                        Color(0xFF11284C),
                        Color(0xFF0A1830),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                        : LinearGradient(
                      colors: [
                        Colors.white,
                        Colors.blueGrey.shade50,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.black.withOpacity(0.05),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.blueAccent.withOpacity(0.08)
                            : Colors.blue.withOpacity(0.08),
                        blurRadius: 28,
                        spreadRadius: 2,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _TopInfoPill(
                            icon: Icons.gps_fixed_rounded,
                            label: "GPS Strong",
                            textColor: primaryText,
                            backgroundColor: isDark
                                ? Colors.black.withOpacity(0.28)
                                : Colors.white.withOpacity(0.85),
                            iconColor: const Color(0xFF22C55E),
                          ),
                          const Spacer(),
                          _TopInfoPill(
                            icon: Icons.speed_rounded,
                            label: "Limit ${_speedLimit?.toStringAsFixed(0) ?? "--"} km/h",
                            textColor: _speedLimit != null && _speed > _speedLimit!
                                ? Colors.redAccent
                                : primaryText,
                            backgroundColor: isDark
                                ? (_speedLimit != null && _speed > _speedLimit!
                                ? Colors.redAccent.withOpacity(0.14)
                                : Colors.black.withOpacity(0.28))
                                : (_speedLimit != null && _speed > _speedLimit!
                                ? Colors.redAccent.withOpacity(0.10)
                                : Colors.white.withOpacity(0.85)),
                            iconColor: _speedLimit != null && _speed > _speedLimit!
                                ? Colors.redAccent
                                : Colors.blueAccent,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: SizedBox(
                          height: 190,
                          child: Stack(
                            children: [
                              FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter: LatLng(18.5204, 73.8567),
                                  initialZoom: 16,
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName: 'com.example.speedmonitor',
                                  ),
                                  MarkerLayer(
                                    markers: _lastPosition == null
                                        ? []
                                        : [
                                      Marker(
                                        width: 40,
                                        height: 40,
                                        point: LatLng(
                                          _lastPosition!.latitude,
                                          _lastPosition!.longitude,
                                        ),
                                        child: const Icon(
                                          Icons.my_location,
                                          color: Colors.blueAccent,
                                          size: 35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.black.withOpacity(0.14),
                                      Colors.transparent,
                                      Colors.black.withOpacity(0.18),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                              Center(
                                child: Container(
                                  width: 62,
                                  height: 62,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF0C1830).withOpacity(0.82)
                                        : Colors.white.withOpacity(0.88),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.blueAccent.withOpacity(0.20),
                                        blurRadius: 20,
                                        spreadRadius: 2,
                                      )
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.location_on_outlined,
                                    color: Color(0xFF4DA3FF),
                                    size: 34,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                /// SPEED METER (kept logic same, only surrounding section spacing preserved)
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: _speed),
                  duration: const Duration(milliseconds: 200),
                  builder: (context, animatedValue, child) {
                    double progress = animatedValue / 120;
                    progress = progress.clamp(0.0, 1.0);

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 300,
                          height: 300,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: animatedValue > 60
                                    ? Colors.redAccent.withOpacity(0.08)
                                    : Colors.blueAccent.withOpacity(0.10),
                                blurRadius: 40,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 260,
                          height: 260,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 10,
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              animatedValue > 60 ? Colors.redAccent : Colors.blueAccent,
                            ),
                          ),
                        ),
                        Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1C1C2E), Color(0xFF2D2D44)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: animatedValue > 60
                                    ? Colors.redAccent.withOpacity(0.6)
                                    : Colors.blueAccent.withOpacity(0.5),
                                blurRadius: 30,
                                spreadRadius: 5,
                              )
                            ],
                          ),
                          child: SingleChildScrollView(
                            child: SizedBox(
                              width: 220,
                              height: 220,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    animatedValue.toStringAsFixed(1),
                                    style: TextStyle(
                                      color: primaryText,
                                      fontSize: 60,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    "km/h",
                                    style: TextStyle(
                                      color: secondaryText,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 26),

                /// STATS
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: "Distance",
                        value: (_totalDistance / 1000).toStringAsFixed(2),
                        unit: "km",
                        icon: Icons.near_me_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: _StatCard(
                        title: "Time",
                        value: "00:00",
                        unit: "",
                        icon: Icons.access_time_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: _StatCard(
                        title: "Max Speed",
                        value: "0",
                        unit: "km/h",
                        icon: Icons.trending_up_rounded,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _speed += 10;
                    });

                    if (_speedLimit != null && _speedLimit != null && _speed > _speedLimit!!) {
                      _overspeedCount++;

                      print("Overspeed Count (TEST): $_overspeedCount");

                      _sendOverspeedToWebhook(
                        Position(
                          longitude: _lastPosition?.longitude ?? 0,
                          latitude: _lastPosition?.latitude ?? 0,
                          timestamp: DateTime.now(),
                          accuracy: 1,
                          altitude: 0,
                          altitudeAccuracy: 1,
                          heading: 0,
                          headingAccuracy: 1,
                          speed: _speed / 3.6,
                          speedAccuracy: 1,
                        ),
                      );

                      if (_overspeedCount == 5 && !_isSpeaking) {
                        _triggerContinuousOverspeedWarning();
                      }
                    }
                  },
                  child: const Text("Increase Speed (Test)"),
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _speed -= 20;
                      if (_speed < 0) _speed = 0;
                    });

                    if (_speed < _speedLimit! - 5) {
                      _alertSent = false;
                    }
                  },
                  child: const Text("Decrease Speed (Test)"),
                ),

                const SizedBox(height: 26),

                /// START / STOP BUTTON
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isTracking = !_isTracking;
                      });

                      if (_isTracking) {
                        _createNewTrip();
                        _startTracking();
                      } else {
                        _endCurrentTrip();
                        _stopTracking();
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: LinearGradient(
                          colors: _isTracking
                              ? const [Color(0xFFFF5A5F), Color(0xFFFF7A59)]
                              : const [Color(0xFF4D8DFF), Color(0xFF2F6BFF)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _isTracking
                                ? const Color(0xFFFF5A5F).withOpacity(0.35)
                                : const Color(0xFF2F6BFF).withOpacity(0.35),
                            blurRadius: 24,
                            spreadRadius: 2,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Text(
                        _isTracking ? "Stop Trip" : "Start Trip",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendOverspeedEmail(Position position) async {
    String username = 'atharv21.novagenx@gmail.com';
    String password = 'kzpmxlhlxcrnvhxo';

    final smtpServer = gmail(username, password);

    final message = Message()
      ..from = Address(username, 'Speed Monitor Alert')
      ..recipients.add('28.atharvkulkarni@gmail.com')
      ..subject = '🚨 Overspeed Alert!'
      ..text = '''
            Overspeed detected!
            Speed: ${_speed.toStringAsFixed(1)} km/h
            Limit: $_speedLimit km/h
            Latitude: ${position.latitude}
            Longitude: ${position.longitude}
            Google Maps:
            https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}
''';

    try {
      await send(message, smtpServer);
      print('Email sent');
    } catch (e) {
      print('Email failed: $e');
    }
  }

  Future<void> _sendOverspeedToWebhook(Position position) async {
    final url = Uri.parse(
      "https://novanode3.app.n8n.cloud/webhook/overspeed",
    );

    try {
      await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": FirebaseAuth.instance.currentUser?.uid ?? "unknown",
          "overspeedCount": _overspeedCount,
          "speed": _speed,
          "limit": _speedLimit,
          "latitude": position.latitude,
          "longitude": position.longitude,
          "tripId": _currentTripId ?? "noTrip",
        }),
      );

      print("Webhook sent successfully");
    } catch (e) {
      print("Webhook error: $e");
    }
  }

  Future<void> _triggerContinuousOverspeedWarning() async {
    if (_isSpeaking) return;

    _isSpeaking = true;

    print("🔥 VOICE ALERT TRIGGERED 🔥");

    await _flutterTts.stop();

    await _flutterTts.speak(
      "Warning. You are continuously exceeding the speed limit.",
    );
  }
}

class _TopInfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color textColor;
  final Color backgroundColor;
  final Color iconColor;

  const _TopInfoPill({
    required this.icon,
    required this.label,
    required this.textColor,
    required this.backgroundColor,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color primaryText = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final Color secondaryText =
    (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)
        .withOpacity(0.65);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: isDark
            ? const LinearGradient(
          colors: [
            Color(0xFF0C1630),
            Color(0xFF0A1326),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
            : LinearGradient(
          colors: [
            Colors.white,
            Colors.grey.shade100,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.22)
                : Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: const Color(0xFF4DA3FF),
            size: 18,
          ),
          const SizedBox(height: 18),
          Text(
            value,
            style: TextStyle(
              color: primaryText,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (unit.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              unit,
              style: TextStyle(
                color: secondaryText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: secondaryText,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

////////////////////////////////////////////////////////////
/// MAIN SCREEN WITH BOTTOM NAVIGATION
////////////////////////////////////////////////////////////

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  List<Trip> _tripHistory = [];
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          SpeedMonitorScreen(
            onTripCreated: (trip) {
              setState(() {
                _tripHistory.add(trip);
                print("Trip added. Count: ${_tripHistory.length}");
              });
            },
          ),
          const TripHistoryScreen(),
          const RouteScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF091427) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.25 : 0.08),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: isDark ? const Color(0xFF091427) : Colors.white,
          elevation: 0,
          selectedItemColor: const Color(0xFF4D8DFF),
          unselectedItemColor: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.color
              ?.withOpacity(0.6),
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.speed),
              label: "Dashboard",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              label: "Trips",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.alt_route),
              label: 'Route',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: "Settings",
            ),
          ],
        ),
      ),
    );
  }
}