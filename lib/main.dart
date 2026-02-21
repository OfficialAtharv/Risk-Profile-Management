import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:speed_monitor_flutter/screens/trip_details_screen.dart';
import 'auth/auth_wrapper.dart';
import 'models/trip_model.dart';
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/firestore_service.dart';
import 'package:speed_monitor_flutter/services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
<<<<<<< HEAD





=======
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
>>>>>>> c0a3057 (new updates on the application - this version is comming with the User specific ID, DB storage, and theme building features)
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final prefs = await SharedPreferences.getInstance();
  final isDarkMode = prefs.getBool('isDarkMode') ?? false;

  themeNotifier.value =
  isDarkMode ? ThemeMode.dark : ThemeMode.light;

  runApp(const SpeedMonitorApp());
}

final ValueNotifier<ThemeMode> themeNotifier =
ValueNotifier(ThemeMode.light);

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

    List<Placemark> placemarks =
    await placemarkFromCoordinates(
        position.latitude,
        position.longitude);

    Placemark place = placemarks.first;

    String area = place.subLocality ?? '';
    String city = place.locality ?? '';

    String startLocationName =
    area.isNotEmpty ? "$area, $city" : city;

    _currentTrip = Trip(
      startTime: DateTime.now(),
      startLat: position.latitude,
      startLng: position.longitude,
      startLocation: startLocationName,
    );

    print("START LOCATION: $startLocationName");

    print("Current user: ${FirebaseAuth.instance.currentUser?.uid}");
    _currentTripId =
    await FirestoreService().saveTrip(_currentTrip!);

    widget.onTripCreated(_currentTrip!);

    print("Trip Started with ID: $_currentTripId");
  }

  Future<void> _endCurrentTrip() async {
    if (_currentTrip == null || _currentTripId == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("User not logged in");
      return;
    }

    Position position = await Geolocator.getCurrentPosition();

    DateTime endTime = DateTime.now();
    DateTime startTime = _currentTrip!.startTime;

    Duration difference = endTime.difference(startTime);

    String formattedDuration =
        "${difference.inHours.toString().padLeft(2, '0')}:"
        "${(difference.inMinutes % 60).toString().padLeft(2, '0')}:"
        "${(difference.inSeconds % 60).toString().padLeft(2, '0')}";

    List<Placemark> placemarks =
    await placemarkFromCoordinates(
        position.latitude,
        position.longitude);

    Placemark place = placemarks.first;

    String area = place.subLocality ?? '';
    String city = place.locality ?? '';

    String endLocationName =
    area.isNotEmpty ? "$area, $city" : city;

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



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: Theme.of(context).brightness == Brightness.dark
                ? [const Color(0xFF141E30), const Color(0xFF243B55)]
                : [Colors.white, Colors.grey.shade200],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [

              const SizedBox(height: 10),

              // 🔹 APP TITLE
              Text(
                "Speed Monitor",
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
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
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: Theme.of(context).brightness == Brightness.dark
                              ? [const Color(0xFF141E30), const Color(0xFF243B55)]
                              : [Colors.white, Colors.grey.shade200],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Text(
                        "60",
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // GPS Status
                    Row(
                      children: [
                        const Icon(Icons.gps_fixed, color: Colors.green),
                        const SizedBox(width: 6),
                        Text(
                          "GPS Strong",
                          style: TextStyle(
                            color: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.color
                                ?.withOpacity(0.7),
                          ),
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
                                style: TextStyle(
                                  color: Theme.of(context).textTheme.bodyLarge?.color,
                                  fontSize: 60,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "km/h",
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.color
                                      ?.withOpacity(0.7),
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
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            color: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.color
                ?.withOpacity(0.6),
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

        selectedItemColor: Colors.blueAccent,
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: StreamBuilder<List<Trip>>(
        stream: firestoreService.getTrips(),
        builder: (context, snapshot) {

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Text(
                "No Trips Yet 🚗",
                style: TextStyle(color: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.color
                    ?.withOpacity(0.7), fontSize: 18),
              ),
            );
          }

          final trips = snapshot.data!;

          return ListView.builder(
            itemCount: trips.length,
              itemBuilder: (context, index) {
                final trip = trips[index];

                String location =
                    trip.startLocation ?? "Unknown Location";

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            TripDetailsScreen(trip: trip),
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
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        Text(
                          DateFormat('dd MMM yyyy • hh:mm a')
                              .format(trip.startTime),
                          style: TextStyle(
                            color: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.color
                                ?.withOpacity(0.7),
                            fontSize: 13,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          "${((trip.distance ?? 0) / 1000).toStringAsFixed(2)} km",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                              const Spacer(),

                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Icon(Icons.location_on,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.color
                                    ?.withOpacity(0.7), size: 18),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 150,
                              child: Text(
                                location,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.color
                                      ?.withOpacity(0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }

          );
        },
      ),
    );
  }
}







