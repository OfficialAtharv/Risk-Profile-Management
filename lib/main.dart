import 'package:flutter/material.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:speed_monitor_flutter/screens/trip_details_screen.dart';
import 'models/trip_model.dart';
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/firestore_service.dart';
import 'package:speed_monitor_flutter/services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';





void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const SpeedMonitorApp());
}


class SpeedMonitorApp extends StatelessWidget {
  const SpeedMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MainScreen(),
    );
  }
}

class SpeedMonitorScreen extends StatefulWidget {
  final Function(Trip) onTripCreated;

  const SpeedMonitorScreen({
    super.key,
    required this.onTripCreated,});


  @override
  State<SpeedMonitorScreen> createState() => _SpeedMonitorScreenState();
}

class _SpeedMonitorScreenState extends State<SpeedMonitorScreen> {
  bool _isTracking = false;
  double _speed = 0.0;
  double _speedLimit = 60;
  bool _alertSent = false;
  double _totalDistance = 0.0;
  Position? _lastPosition;
  Trip? _currentTrip;
  String? _currentTripId;

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
      }

      double speedKmh = position.speed * 3.6;

      if (speedKmh < 3){
        speedKmh = 0;
      }

      setState(() {
        _speed = speedKmh;
      });
      // 🔹 Save speed log if trip is active
      if (_isTracking && _currentTripId != null) {
        FirestoreService().saveSpeedLog(
          _currentTripId!,
          speedKmh,
          position.latitude,
          position.longitude,
        );
      }


      if (speedKmh > _speedLimit && !_alertSent) {
        _alertSent = true;
        _sendOverspeedEmail(position);
      }

      if (speedKmh < _speedLimit - 5) {
        _alertSent = false;
      }


    });
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

    _currentTrip = Trip(
      startTime: DateTime.now(),
      startLat: position.latitude,
      startLng: position.longitude,
    );


    _currentTripId =
    await FirestoreService().saveTrip(_currentTrip!);

    widget.onTripCreated(_currentTrip!);

    print("Trip Started with ID: $_currentTripId");
  }

  Future<void> _endCurrentTrip() async {
    if (_currentTrip == null) return;

    Position position = await Geolocator.getCurrentPosition();

    DateTime endTime = DateTime.now();
    DateTime startTime = _currentTrip!.startTime;

    Duration difference = endTime.difference(startTime);

    String formattedDuration =
        "${difference.inHours.toString().padLeft(2, '0')}:"
        "${(difference.inMinutes % 60).toString().padLeft(2, '0')}:"
        "${(difference.inSeconds % 60).toString().padLeft(2, '0')}";

    _currentTrip!.endTrip(
      endTime: endTime,
      endLat: position.latitude,
      endLng: position.longitude,
      duration: formattedDuration,
      distance: _totalDistance,
    );
    await FirebaseFirestore.instance
        .collection('trips')
        .doc(_currentTripId)
        .update(_currentTrip!.toMap());

    print("Trip updated: $_currentTripId");




    print("Trip Ended");
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF141E30), Color(0xFF243B55)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [

              const SizedBox(height: 10),

              // 🔹 APP TITLE
              const Text(
                "Speed Monitor",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 20),

              // 🔹 MAP PLACEHOLDER
              Container(
                height: 160,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.4),
                      Colors.black.withOpacity(0.2),
                    ],
                  ),
                ),
                child: const Center(
                  child: Text(
                    "Live Map (Coming Soon)",
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 🔹 SPEED LIMIT + GPS STATUS
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Speed Limit Badge
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red,
                      ),
                      child: const Text(
                        "60",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // GPS Status
                    Row(
                      children: const [
                        Icon(Icons.gps_fixed, color: Colors.green),
                        SizedBox(width: 6),
                        Text(
                          "GPS Strong",
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // 🔹 SPEED METER
              // 🔹 SPEED METER WITH ANIMATED ARC
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: _speed),
                duration: const Duration(milliseconds: 200),
                builder: (context, animatedValue, child) {
                  double progress = animatedValue / 120; // assume max 120 km/h
                  progress = progress.clamp(0.0, 1.0);

                  return Stack(
                    alignment: Alignment.center,
                    children: [
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
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                animatedValue.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 60,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text(
                                "km/h",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),




              const SizedBox(height: 30),

              // 🔹 TRIP STATS
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _StatCard(
                      title: "Distance",
                      value: "${(_totalDistance / 1000).toStringAsFixed(2)} km",
                    ),
                    const _StatCard(title: "Time", value: "00:00"),
                    const _StatCard(title: "Max", value: "0 km/h"),
                  ],
                ),
              ),


              const Spacer(),
              // ElevatedButton(
              //   onPressed: () async {
              //     Position position = await Geolocator.getCurrentPosition();
              //     _sendOverspeedEmail(position);
              //   },
              //   child: const Text("Test Email"),
              // ),

              // 🔹 START BUTTON
              Padding(
                padding: const EdgeInsets.only(bottom: 40),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 70, vertical: 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(40),
                      gradient: LinearGradient(
                        colors: _isTracking
                            ? [Colors.redAccent, Colors.deepOrange]
                            : [Colors.blueAccent, Colors.cyan],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _isTracking
                              ? Colors.redAccent.withOpacity(0.6)
                              : Colors.blueAccent.withOpacity(0.6),
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: Text(
                      _isTracking ? "Stop Trip" : "Start Trip",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
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

}

// 🔹 Reusable Stat Card
class _StatCard extends StatelessWidget {


  final String title;
  final String value;

  const _StatCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
        ),
      ],
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
  @override
  Widget build(BuildContext context) {
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
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF141E30),
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.white54,
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
            icon: Icon(Icons.settings),
            label: "Settings",
          ),
        ],
      ),
    );
  }

}

////////////////////////////////////////////////////////////
/// TRIP HISTORY SCREEN
////////////////////////////////////////////////////////////

class TripHistoryScreen extends StatelessWidget {
  const TripHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return Scaffold(
      backgroundColor: const Color(0xFF141E30),
      body: StreamBuilder<List<Trip>>(
        stream: firestoreService.getTrips(),
        builder: (context, snapshot) {

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                "No Trips Yet 🚗",
                style: TextStyle(color: Colors.white70, fontSize: 18),
              ),
            );
          }

          final trips = snapshot.data!;

          return ListView.builder(
            itemCount: trips.length,
            itemBuilder: (context, index) {
              final trip = trips[index];

              return FutureBuilder<List<Placemark>>(
                future: placemarkFromCoordinates(
                    trip.startLat, trip.startLng),
                builder: (context, locationSnapshot) {

                  String location = "Loading location...";

                  if (locationSnapshot.hasData &&
                      locationSnapshot.data!.isNotEmpty) {
                    final place = locationSnapshot.data!.first;
                    location =
                    "${place.locality}, ${place.administrativeArea}";
                  }

                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TripDetailsScreen(trip: trip),
                        ),
                      );
                    },

                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF1E3C72),
                            Color(0xFF2A5298),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blueAccent.withOpacity(0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          /// DATE
                          Text(
                            DateFormat('dd MMM yyyy • hh:mm a').format(trip.startTime),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),

                          const SizedBox(height: 12),

                          /// DISTANCE BIG
                          Text(
                            "${((trip.distance ?? 0) / 1000).toStringAsFixed(2)} km",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 10),

                          Row(
                            children: [

                              Row(
                                children: [
                                  const Icon(Icons.timer, color: Colors.white70, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    trip.duration ?? "Running...",
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),

                              const Spacer(),

                              Row(
                                children: [
                                  const Icon(Icons.location_on,
                                      color: Colors.white70, size: 18),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    width: 120,
                                    child: Text(
                                      location,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}



////////////////////////////////////////////////////////////
/// SETTINGS SCREEN
////////////////////////////////////////////////////////////

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF141E30),
      body: Center(
        child: Text(
          "Settings Coming Soon ⚙",
          style: TextStyle(color: Colors.white70, fontSize: 20),
        ),
      ),
    );
  }
}


