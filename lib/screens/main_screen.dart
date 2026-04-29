import 'package:flutter/material.dart';

import '../models/trip_model.dart';
import '../screens/settings_screen.dart';
import '../screens/trip_history_screen.dart';
import '../screens/route_screen.dart';
import '../screens/vision_ai_screen.dart';
import '../main.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final List<Trip> _tripHistory = [];
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
              });
            },
          ),
          const TripHistoryScreen(),
          const RouteScreen(),
          const VisionAiScreen(),
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
          unselectedItemColor:
          Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
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
              label: "Route",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.visibility),
              label: "Vision AI",
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