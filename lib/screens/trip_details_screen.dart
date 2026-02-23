import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/trip_model.dart';

class TripDetailsScreen extends StatelessWidget {
  final Trip trip;
  const TripDetailsScreen({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141E30),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141E30),
        elevation: 0,
        title: const Text("Trip Details"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            /// 🔥 HERO DISTANCE SECTION
            Center(
              child: Column(
                children: [
                  Text(
                    "${((trip.distance ?? 0) / 1000).toStringAsFixed(2)} km",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Total Distance",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            /// 📊 QUICK SUMMARY CARDS
            Row(
              children: [
                _summaryCard(
                  icon: Icons.timer,
                  title: "Duration",
                  value: trip.duration ?? "N/A",
                ),
                const SizedBox(width: 12),
                _summaryCard(
                  icon: Icons.route,
                  title: "Distance",
                  value:
                  "${((trip.distance ?? 0) / 1000).toStringAsFixed(2)} km",
                ),
              ],
            ),

            const SizedBox(height: 30),

            /// 📍 START SECTION
            _sectionTitle("Start Details"),
            const SizedBox(height: 12),

            _detailTile(
              icon: Icons.access_time,
              label: "Start Time",
              value: DateFormat('dd MMM yyyy, hh:mm a')
                  .format(trip.startTime),
            ),

            _detailTile(
              icon: Icons.location_on,
              label: "Start Location",
              value: trip.startLocation ?? "Unknown Location",
            ),

            const SizedBox(height: 25),

            /// 🏁 END SECTION
            _sectionTitle("End Details"),
            const SizedBox(height: 12),

            _detailTile(
              icon: Icons.access_time,
              label: "End Time",
              value: trip.endTime != null
                  ? DateFormat('dd MMM yyyy, hh:mm a')
                  .format(trip.endTime!)
                  : "Not Ended Yet",
            ),

            _detailTile(
              icon: Icons.flag,
              label: "End Location",
              value: trip.endLocation ?? "Unknown Location",
            ),
          ],
        ),
      ),
    );
  }

  /// 🔹 Summary Card Widget
  Widget _summaryCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF243B55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.blueAccent),
            const SizedBox(height: 10),
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
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🔹 Section Title Widget
  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  /// 🔹 Detail Tile Widget
  Widget _detailTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF243B55),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueAccent),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}