import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'models/trip_model.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:speed_monitor_flutter/services/firestore_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '/screens/route_screen.dart';
import 'screens/trip_history_screen.dart';
import 'auth/auth_wrapper.dart';

class _SpeedFetchResult {
  final double speedLimit;
  final String source;
  final String roadType;

  const _SpeedFetchResult({
    required this.speedLimit,
    required this.source,
    required this.roadType,
  });
}

class _OverpassRoadCandidate {
  final Map<String, dynamic> element;
  final Map<String, dynamic> tags;
  final double distanceMeters;
  final double score;
  final double? parsedMaxspeed;
  final String roadType;

  const _OverpassRoadCandidate({
    required this.element,
    required this.tags,
    required this.distanceMeters,
    required this.score,
    required this.parsedMaxspeed,
    required this.roadType,
  });
}

class _SpeedCacheEntry {
  final _SpeedFetchResult result;
  final DateTime createdAt;

  const _SpeedCacheEntry({
    required this.result,
    required this.createdAt,
  });
}

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
  static const List<String> _overpassEndpoints = [
    "https://overpass.private.coffee/api/interpreter",
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
  ];

  static const Duration _overpassTimeout = Duration(seconds: 8);
  static const Duration _speedCacheTtl = Duration(minutes: 2);
  Map<String, dynamic>? _primaryEmergencyContact;
  bool _isLoadingPrimaryContact = false;
  bool _isTracking = false;
  double _speed = 0.0;
  double? _speedLimit;
  String _speedLimitSource = "loading";
  String _roadTypeLabel = "--";
  bool _isFetchingSpeedLimit = false;

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
  StreamSubscription<Position>? _previewPositionStream;
  DateTime? _lastSpeedLimitFetch;
  DateTime? _lastOverspeedIncrementAt;
  Position? _lastSpeedLimitFetchPosition;

  final Map<String, _SpeedCacheEntry> _speedLimitCache = {};
  final math.Random _random = math.Random();
  int _speedFetchRequestId = 0;

  String _speedLimitDisplayText() {
    if (_isFetchingSpeedLimit && _speedLimit == null) {
      return "Fetching...";
    }

    if (_speedLimit == null) {
      return "--";
    }

    return _speedLimit!.toStringAsFixed(0);
  }

  @override
  void initState() {
    super.initState();
    _initTTS();
    _startPreviewLocationUpdates();
    _loadPrimaryEmergencyContact();
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

  Future<void> _loadPrimaryEmergencyContact() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      setState(() {
        _isLoadingPrimaryContact = true;
      });

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('emergency_contacts')
          .where('isPrimary', isEqualTo: true)
          .limit(1)
          .get();

      if (!mounted) return;

      if (snapshot.docs.isNotEmpty) {
        print('Primary contact loaded: ${snapshot.docs.first.data()}');
        setState(() {
          _primaryEmergencyContact = snapshot.docs.first.data();
          _isLoadingPrimaryContact = false;
        });
      } else {
        setState(() {
          _primaryEmergencyContact = null;
          _isLoadingPrimaryContact = false;
        });
      }
    } catch (e) {
      print('Failed to load primary emergency contact: $e');

      if (!mounted) return;
      setState(() {
        _primaryEmergencyContact = null;
        _isLoadingPrimaryContact = false;
      });
    }
  }
  @override
  void dispose() {
    _positionStream?.cancel();
    _previewPositionStream?.cancel();
    super.dispose();
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

  Future<void> _startPreviewLocationUpdates() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print("❌ Location service disabled");
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      print("❌ Location permission denied");
      return;
    }

    _previewPositionStream?.cancel();

    _previewPositionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((Position position) async {
      if (position.accuracy > 35) return;

      if (mounted) {
        setState(() {
          _lastPosition = position;
        });
      }

      _mapController.move(
        LatLng(position.latitude, position.longitude),
        17,
      );

      await _fetchSpeedLimit(position.latitude, position.longitude);
    });
  }

  Future<void> _startTracking() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print("❌ Location service disabled");
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      print("❌ Location permission denied");
      return;
    }

    _positionStream?.cancel();

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).listen((Position position) async {
      if (position.accuracy > 35) return;
      if (!_isTracking) return;

      if (_lastPosition != null) {
        final distanceInMeters = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        _totalDistance += distanceInMeters;
      }

      _lastPosition = position;

      _mapController.move(
        LatLng(position.latitude, position.longitude),
        17,
      );

      double speedKmh = position.speed * 3.6;
      if (speedKmh < 3) {
        speedKmh = 0;
      }

      setState(() {
        _speed = speedKmh;
      });

      if (_currentTripId != null) {
        FirestoreService().saveSpeedLog(
          _currentTripId!,
          speedKmh,
          position.latitude,
          position.longitude,
        );
      }

      final currentLimit = _speedLimit;

      if (currentLimit != null && _speed > currentLimit) {
        final now = DateTime.now();

        if (_lastOverspeedIncrementAt == null ||
            now.difference(_lastOverspeedIncrementAt!).inSeconds >= 5) {
          _overspeedCount++;
          _lastOverspeedIncrementAt = now;

          print("Overspeed Count: $_overspeedCount");

          await _sendOverspeedToWebhook(
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
            await _triggerContinuousOverspeedWarning();
          }
        }
      } else {
        _alertSent = false;
      }

      if (currentLimit != null && speedKmh < currentLimit - 5) {
        _alertSent = false;
      }
    });
  }

  Future<void> _fetchSpeedLimit(double lat, double lon) async {
    if (_lastSpeedLimitFetch != null &&
        DateTime.now().difference(_lastSpeedLimitFetch!).inSeconds < 5) {
      return;
    }

    if (_lastSpeedLimitFetchPosition != null) {
      final movedDistance = Geolocator.distanceBetween(
        _lastSpeedLimitFetchPosition!.latitude,
        _lastSpeedLimitFetchPosition!.longitude,
        lat,
        lon,
      );

      if (movedDistance < 20) {
        return;
      }
    }

    _lastSpeedLimitFetch = DateTime.now();
    _lastSpeedLimitFetchPosition = Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.now(),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 0,
      speedAccuracy: 1,
    );

    final int requestId = ++_speedFetchRequestId;

    if (mounted) {
      setState(() {
        _isFetchingSpeedLimit = true;
        if (_speedLimit == null) {
          _speedLimitSource = "loading";
          _roadTypeLabel = "--";
        }
      });
    }

    print("➡️ _fetchSpeedLimit called");
    print("➡️ lat=$lat lon=$lon");

    try {
      final cached = _getCachedSpeedLimit(lat, lon);
      if (cached != null) {
        print("✅ Using cached speed limit");
        _applyResolvedSpeedLimit(
          cached.speedLimit,
          cached.source,
          cached.roadType,
          requestId,
        );
        return;
      }

      final result = await _fetchSpeedLimitWithFailover(lat, lon);

      if (result != null) {
        _storeCachedSpeedLimit(lat, lon, result);
        _applyResolvedSpeedLimit(
          result.speedLimit,
          result.source,
          result.roadType,
          requestId,
        );
        return;
      }

      print("⚠️ All Overpass endpoints failed, using fallback");
      _applyFallbackSpeedLimit(_roadTypeLabel == "--" ? null : _roadTypeLabel);
    } catch (e) {
      print("Speed limit fetch error: $e");
      _applyFallbackSpeedLimit(_roadTypeLabel == "--" ? null : _roadTypeLabel);
    }
  }

  Future<_SpeedFetchResult?> _fetchSpeedLimitWithFailover(
      double lat,
      double lon,
      ) async {
    final endpoints = [..._overpassEndpoints]..shuffle(_random);

    Object? lastError;

    for (int round = 0; round < 2; round++) {
      for (final endpoint in endpoints) {
        try {
          print("🌐 Trying Overpass endpoint: $endpoint (round ${round + 1})");

          final result = await _fetchFromSingleEndpoint(
            endpoint: endpoint,
            lat: lat,
            lon: lon,
          );

          if (result != null) {
            print("✅ Speed limit resolved from $endpoint");
            return result;
          }
        } catch (e) {
          lastError = e;
          print("❌ Endpoint failed: $endpoint");
          print("❌ Error: $e");
        }
      }

      if (round == 0) {
        await Future.delayed(const Duration(milliseconds: 700));
      }
    }

    print("❌ All endpoints exhausted. Last error: $lastError");
    return null;
  }

  Future<_SpeedFetchResult?> _fetchFromSingleEndpoint({
    required String endpoint,
    required double lat,
    required double lon,
  }) async {
    final query = _buildOverpassQuery(lat, lon);

    final response = await http
        .post(
      Uri.parse(endpoint),
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "User-Agent": "SpeedMonitorFlutter/1.0",
        "Accept": "application/json",
      },
      body: query,
    )
        .timeout(_overpassTimeout);

    if (response.statusCode != 200) {
      throw Exception("Overpass non-200: ${response.statusCode}");
    }

    final data = jsonDecode(response.body);
    final elements = (data["elements"] as List?) ?? [];

    print("Overpass elements count: ${elements.length}");

    if (elements.isEmpty) {
      return null;
    }

    final candidate = _chooseBestRoadCandidate(
      lat: lat,
      lon: lon,
      elements: elements,
    );

    if (candidate == null) {
      return null;
    }

    final double finalLimit;
    final String finalSource;

    if (candidate.parsedMaxspeed != null) {
      finalLimit = candidate.parsedMaxspeed!;
      finalSource = "maxspeed";
    } else {
      finalLimit = _fallbackByRoadType(candidate.roadType);
      finalSource = "fallback";
    }

    print("🎯 CHOSEN ROAD TYPE: ${candidate.roadType}");
    print("🎯 DISTANCE: ${candidate.distanceMeters.toStringAsFixed(1)} m");
    print("🎯 SCORE: ${candidate.score.toStringAsFixed(2)}");
    print(
      "🎯 RAW MAXSPEED: ${candidate.tags["maxspeed"] ?? candidate.tags["maxspeed:forward"] ?? candidate.tags["maxspeed:backward"]}",
    );
    print("✅ finalLimit to set: $finalLimit");
    print("✅ source: $finalSource");

    return _SpeedFetchResult(
      speedLimit: finalLimit,
      source: finalSource,
      roadType: candidate.roadType,
    );
  }

  String _buildOverpassQuery(double lat, double lon) {
    return """
[out:json][timeout:12];
(
  way(around:35,$lat,$lon)
    ["highway"]
    ["highway"!~"footway|path|cycleway|steps|bridleway|corridor|proposed|construction|raceway|escape|bus_guideway"];
  way(around:70,$lat,$lon)
    ["highway"]
    ["highway"!~"footway|path|cycleway|steps|bridleway|corridor|proposed|construction|raceway|escape|bus_guideway"];
);
out tags center;
""";
  }

  _OverpassRoadCandidate? _chooseBestRoadCandidate({
    required double lat,
    required double lon,
    required List elements,
  }) {
    _OverpassRoadCandidate? best;

    for (final rawElement in elements) {
      if (rawElement is! Map<String, dynamic>) continue;

      final tagsRaw = rawElement["tags"];
      if (tagsRaw is! Map) continue;

      final tags = Map<String, dynamic>.from(tagsRaw);
      final roadType = tags["highway"]?.toString() ?? "unknown";

      final center = rawElement["center"];
      if (center == null || center["lat"] == null || center["lon"] == null) {
        continue;
      }

      final roadLat = (center["lat"] as num).toDouble();
      final roadLon = (center["lon"] as num).toDouble();

      final distance = Geolocator.distanceBetween(
        lat,
        lon,
        roadLat,
        roadLon,
      );

      final parsedMaxspeed = _extractBestMaxSpeed(tags);

      final score = _scoreRoadCandidate(
        distanceMeters: distance,
        roadType: roadType,
        hasMaxspeed: parsedMaxspeed != null,
      );

      final candidate = _OverpassRoadCandidate(
        element: rawElement,
        tags: tags,
        distanceMeters: distance,
        score: score,
        parsedMaxspeed: parsedMaxspeed,
        roadType: roadType,
      );

      print(
        "Road Tags: $tags | distance=$distance | score=$score | parsedMaxspeed=$parsedMaxspeed",
      );

      if (best == null || candidate.score > best.score) {
        best = candidate;
      }
    }

    return best;
  }

  double _scoreRoadCandidate({
    required double distanceMeters,
    required String roadType,
    required bool hasMaxspeed,
  }) {
    double score = 0;

    score += hasMaxspeed ? 1000 : 0;
    score -= distanceMeters * 2.5;
    score += _roadPriorityScore(roadType);

    return score;
  }

  double _roadPriorityScore(String roadType) {
    switch (roadType) {
      case "motorway":
        return 120;
      case "trunk":
        return 100;
      case "primary":
        return 90;
      case "secondary":
        return 80;
      case "tertiary":
        return 70;
      case "unclassified":
        return 55;
      case "residential":
        return 50;
      case "service":
        return 20;
      case "living_street":
        return 10;
      default:
        return 0;
    }
  }

  double? _extractBestMaxSpeed(Map<String, dynamic> tags) {
    return _parseMaxSpeed(tags["maxspeed"]?.toString()) ??
        _parseMaxSpeed(tags["maxspeed:forward"]?.toString()) ??
        _parseMaxSpeed(tags["maxspeed:backward"]?.toString());
  }

  void _applyResolvedSpeedLimit(
      double speedLimit,
      String source,
      String roadType,
      int requestId,
      ) {
    if (requestId != _speedFetchRequestId) {
      print("⚠️ Ignoring stale speed fetch response");
      return;
    }

    if (mounted) {
      setState(() {
        _speedLimit = speedLimit;
        _speedLimitSource = source;
        _roadTypeLabel = roadType;
        _isFetchingSpeedLimit = false;
      });
    }

    print("Updated Speed Limit: $_speedLimit");
  }

  String _cacheKey(double lat, double lon) {
    final latBucket = (lat * 1000).round() / 1000;
    final lonBucket = (lon * 1000).round() / 1000;
    return "$latBucket,$lonBucket";
  }

  _SpeedFetchResult? _getCachedSpeedLimit(double lat, double lon) {
    final key = _cacheKey(lat, lon);
    final cached = _speedLimitCache[key];
    if (cached == null) return null;

    if (DateTime.now().difference(cached.createdAt) > _speedCacheTtl) {
      _speedLimitCache.remove(key);
      return null;
    }

    return cached.result;
  }

  void _storeCachedSpeedLimit(double lat, double lon, _SpeedFetchResult result) {
    final key = _cacheKey(lat, lon);
    _speedLimitCache[key] = _SpeedCacheEntry(
      result: result,
      createdAt: DateTime.now(),
    );
  }

  double? _parseMaxSpeed(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    final value = raw.toLowerCase().trim();

    if (value == "signals" ||
        value == "variable" ||
        value == "none" ||
        value == "national" ||
        value == "implicit" ||
        value == "walk") {
      return null;
    }

    final numberMatch = RegExp(r'(\d+(\.\d+)?)').firstMatch(value);
    if (numberMatch == null) return null;

    double parsed = double.tryParse(numberMatch.group(1)!) ?? 0;

    if (parsed <= 0) return null;

    if (value.contains("mph")) {
      parsed = parsed * 1.60934;
    } else if (value.contains("knots")) {
      parsed = parsed * 1.852;
    }

    return parsed > 0 ? parsed : null;
  }

  double _fallbackByRoadType(String? roadType) {
    switch (roadType) {
      case "motorway":
        return 100;
      case "trunk":
        return 80;
      case "primary":
        return 65;
      case "secondary":
        return 55;
      case "tertiary":
        return 45;
      case "residential":
        return 30;
      case "service":
        return 20;
      case "living_street":
        return 15;
      default:
        return 50;
    }
  }

  void _applyFallbackSpeedLimit([String? roadType]) {
    final effectiveRoadType =
    roadType == null || roadType == "--" || roadType == "unknown"
        ? (_roadTypeLabel == "--" ? "unknown" : _roadTypeLabel)
        : roadType;

    final fallback = _fallbackByRoadType(effectiveRoadType);

    if (mounted) {
      setState(() {
        _speedLimit = fallback;
        _speedLimitSource = "fallback";
        _roadTypeLabel = effectiveRoadType;
        _isFetchingSpeedLimit = false;
      });
    }
    print("⚠️ Using fallback speed limit");
    print("Fallback Speed Limit: $_speedLimit");
  }

  Future<void> _createNewTrip() async {
    _totalDistance = 0.0;
    _lastOverspeedIncrementAt = null;

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );

      print("Initial position fetched: ${position.latitude}, ${position.longitude}");

      _lastPosition = position;

      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      final place = placemarks.first;
      final area = place.subLocality ?? '';
      final city = place.locality ?? '';
      final startLocationName = area.isNotEmpty ? "$area, $city" : city;

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
    } catch (e) {
      print("❌ _createNewTrip error: $e");
    }
  }

  Future<void> _endCurrentTrip() async {
    if (_currentTrip == null || _currentTripId == null) return;
    if (_lastPosition == null) {
      print("No last position available");
      return;
    }

    final position = _lastPosition!;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("User not logged in");
      return;
    }

    final endTime = DateTime.now();
    final startTime = _currentTrip!.startTime;
    final difference = endTime.difference(startTime);

    final formattedDuration =
        "${difference.inHours.toString().padLeft(2, '0')}:"
        "${(difference.inMinutes % 60).toString().padLeft(2, '0')}:"
        "${(difference.inSeconds % 60).toString().padLeft(2, '0')}";

    final placemarks = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );

    final place = placemarks.first;
    final area = place.subLocality ?? '';
    final city = place.locality ?? '';
    final endLocationName = area.isNotEmpty ? "$area, $city" : city;

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

  void _stopTracking() {
    _positionStream?.cancel();
    setState(() {
      _speed = 0;
    });
  }

  Future<void> _sendOverspeedEmail(Position position) async {
    String username = 'atharv21.novagenx@gmail.com';
    String password = 'kzpmxlhlxcrnvhxo';

    final recipientEmail = _primaryEmergencyContact?['email']?.toString().trim();

    if (recipientEmail == null || recipientEmail.isEmpty) {
      print('No primary emergency contact email found');
      return;
    }

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
      "https://n8nworkflownode3.app.n8n.cloud/webhook/safety-alert",
    );

    try {
      await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "eventType": "overspeed",
          "userId": FirebaseAuth.instance.currentUser?.uid ?? "unknown",
          "overspeedCount": _overspeedCount,
          "speed": _speed,
          "limit": _speedLimit,
          "latitude": position.latitude,
          "longitude": position.longitude,
          "tripId": _currentTripId ?? "noTrip",
          "contactName": _primaryEmergencyContact?['name']?.toString().trim() ?? "",
          "contactPhone": _primaryEmergencyContact?['phone']?.toString().trim() ?? "",
          "contactEmail": _primaryEmergencyContact?['email']?.toString().trim() ?? "",
        }),
      );

      print("Webhook contact email: ${_primaryEmergencyContact?['email']}");
      print("Webhook contact phone: ${_primaryEmergencyContact?['phone']}");
      print("Webhook contact name: ${_primaryEmergencyContact?['name']}");

      print("✅ Overspeed webhook sent successfully");
    } catch (e) {
      print("❌ Overspeed webhook error: $e");
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

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color primaryText =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
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
                            label: _speedLimit == null
                                ? "Limit ${_speedLimitDisplayText()}"
                                : "Limit ${_speedLimitDisplayText()} km/h",
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
                      const SizedBox(height: 8),
                      Text(
                        "Source: $_speedLimitSource | Road: $_roadTypeLabel",
                        style: TextStyle(
                          color: secondaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
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
                                options: const MapOptions(
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
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: _speed),
                  duration: const Duration(milliseconds: 200),
                  builder: (context, animatedValue, child) {
                    double progress = animatedValue / 120;
                    progress = progress.clamp(0.0, 1.0);

                    final bool isOverLimit =
                        _speedLimit != null && animatedValue > _speedLimit!;

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
                                color: isOverLimit
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
                              isOverLimit ? Colors.redAccent : Colors.blueAccent,
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
                                color: isOverLimit
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
                  onPressed: () async {
                    setState(() {
                      _speed += 10;
                    });

                    final currentLimit = _speedLimit;

                    if (currentLimit != null && _speed > currentLimit) {
                      _overspeedCount++;

                      print("Overspeed Count (TEST): $_overspeedCount");

                      await _sendOverspeedToWebhook(
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
                        await _triggerContinuousOverspeedWarning();
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

                    final currentLimit = _speedLimit;
                    if (currentLimit != null && _speed < currentLimit - 5) {
                      _alertSent = false;
                    }
                  },
                  child: const Text("Decrease Speed (Test)"),
                ),
                const SizedBox(height: 26),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GestureDetector(
                    onTap: () async {
                      setState(() {
                        _isTracking = !_isTracking;
                      });

                      if (_isTracking) {
                        await _createNewTrip();
                        await _startTracking();
                      } else {
                        await _endCurrentTrip();
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
    final Color primaryText =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
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