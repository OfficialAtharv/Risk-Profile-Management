import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool tripStarted = false;
  double currentSpeed = 0.0;
  double speedLimit = 60.0;

  void simulateSpeed() {
    if (!tripStarted) return;

    setState(() {
      currentSpeed += 20;
    });

    if (currentSpeed > speedLimit) {
      print("OVERSPEED DETECTED");
      _sendOverspeedToN8n(currentSpeed);
    }

    Future.delayed(const Duration(seconds: 2), simulateSpeed);
  }
  void toggleTrip() {
    setState(() {
      tripStarted = !tripStarted;
    });

    if (tripStarted) {
      // Simulate speed increase every 2 seconds
      Future.delayed(const Duration(seconds: 2), simulateSpeed);
    } else {
      setState(() {
        currentSpeed = 0.0;
      });
    }
  }
  Future<void> _sendOverspeedToN8n(double speed) async {
    print("CALLING N8N FUNCTION");

    final url = Uri.parse(
      'https://atharvnova.app.n8n.cloud/webhook/overspeed-alert',
    );

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'speed': speed,
          'alert': 'Overspeed detected',
        }),
      );

      print("STATUS CODE: ${response.statusCode}");
      print("RESPONSE BODY: ${response.body}");
    } catch (e) {
      print("ERROR: $e");
    }
  }

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
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: toggleTrip,
            child: Text(tripStarted ? "End Trip" : "Start Trip"),
          )
        ],
      ),
    );
  }
}
