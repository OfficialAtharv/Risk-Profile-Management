import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool tripStarted = false;
  double currentSpeed = 0.0;

  void toggleTrip() {
    setState(() {
      tripStarted = !tripStarted;
      currentSpeed = 0.0;
    });
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
