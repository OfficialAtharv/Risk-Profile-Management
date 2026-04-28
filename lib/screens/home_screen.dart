import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool isTripActive = false;

  double currentSpeed = 0.0;
  double speedLimit = 60.0;

  double? currentLat;
  double? currentLng;

  DateTime? lastBelowSpeedTime;
  List<double> speedBuffer = [];

  Position? lastApiPosition;

  @override
  void initState() {
    super.initState();
    checkPermission().then((_) {
      // startSpeedTracking();
    });
  }

  // 🔐 LOCATION PERMISSION
  Future<void> checkPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
  }

  // 📡 START GPS TRACKING
  void startSpeedTracking() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      currentLat = position.latitude;
      currentLng = position.longitude;

      double speedKmh = (position.speed * 3.6);

      handleSpeedUpdate(speedKmh);

      _maybeFetchSpeedLimit(position);
    });
  }

  // 🧠 MAIN LOGIC
  void handleSpeedUpdate(double speed) {
    setState(() {
      currentSpeed = speed;
    });

    speedBuffer.add(speed);
    if (speedBuffer.length > 5) {
      speedBuffer.removeAt(0);
    }

    double avgSpeed =
        speedBuffer.reduce((a, b) => a + b) / speedBuffer.length;

    // 🚗 START TRIP
    if (!isTripActive) {
      if (avgSpeed > 15 && avgSpeed < 150) {
        startTrip();
      }
    }

    // 🛑 END TRIP
    if (isTripActive) {
      if (avgSpeed < 5) {
        lastBelowSpeedTime ??= DateTime.now();

        if (DateTime.now()
            .difference(lastBelowSpeedTime!)
            .inMinutes >
            3) {
          endTrip();
        }
      } else {
        lastBelowSpeedTime = null;
      }
    }

    // 🚨 OVERSPEED
    if (isTripActive && speed > speedLimit) {
      print("OVERSPEED DETECTED");
      _sendOverspeedToN8n(speed);
    }
  }

  // 🚗 START TRIP
  void startTrip() {
    print("🚗 Trip Started");

    setState(() {
      isTripActive = true;
    });
  }

  // 🛑 END TRIP
  void endTrip() {
    print("🛑 Trip Ended");

    setState(() {
      isTripActive = false;
      currentSpeed = 0;
    });
  }

  // 🌐 SMART SPEED LIMIT FETCH (FIXED)
  void _maybeFetchSpeedLimit(Position position) {
    if (lastApiPosition == null) {
      lastApiPosition = position;
      _fetchSpeedLimit(position);
      return;
    }

    double distance = Geolocator.distanceBetween(
      lastApiPosition!.latitude,
      lastApiPosition!.longitude,
      position.latitude,
      position.longitude,
    );

    // Call API only if moved 200m+
    if (distance > 200) {
      lastApiPosition = position;
      _fetchSpeedLimit(position);
    }
  }

  Future<void> _fetchSpeedLimit(Position position) async {
    final url = Uri.parse(
        "https://overpass-api.de/api/interpreter");

    final query = """
    [out:json];
    way(around:50,${position.latitude},${position.longitude})["maxspeed"];
    out tags limit 1;
    """;

    try {
      final response = await http
          .post(url, body: query)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['elements'].isNotEmpty) {
          String rawSpeed =
          data['elements'][0]['tags']['maxspeed'];

          double parsed =
              double.tryParse(rawSpeed.replaceAll(RegExp(r'[^0-9]'), '')) ??
                  60;

          setState(() {
            speedLimit = parsed;
          });

          print("Speed Limit Updated: $speedLimit");
        }
      } else {
        print("Overpass Error: ${response.statusCode}");
      }
    } catch (e) {
      print("Speed API Failed, using fallback: $speedLimit");
    }
  }

  // 📡 WEBHOOK
  Future<void> _sendOverspeedToN8n(double speed) async {
    final url = Uri.parse(
      'https://n8nworkflownode3.app.n8n.cloud/webhook/safety-alert',
    );

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'eventType': 'overspeed',
          'userId': 'test-user',
          'speed': speed,
          'limit': speedLimit,
          'latitude': currentLat,
          'longitude': currentLng,
          'tripId': 'auto-trip',
        }),
      );

      print("STATUS: ${response.statusCode}");
    } catch (e) {
      print("Webhook Error: $e");
    }
  }

  // 🎨 UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Speed Monitor"),
        centerTitle: true,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "${currentSpeed.toStringAsFixed(1)} km/h",
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Limit: ${speedLimit.toStringAsFixed(0)} km/h",
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 20),
          Text(
            isTripActive ? "🚗 Trip Active" : "🛑 Idle",
            style: TextStyle(
              fontSize: 18,
              color: isTripActive ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}