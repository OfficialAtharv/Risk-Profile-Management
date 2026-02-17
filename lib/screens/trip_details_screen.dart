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
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            /// BIG DISTANCE
            Text(
              "${((trip.distance ?? 0) / 1000).toStringAsFixed(2)} km",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            _detailTile(
              icon: Icons.calendar_today,
              label: "Start Time",
              value: DateFormat('dd MMM yyyy, hh:mm a')
                  .format(trip.startTime),
            ),

            _detailTile(
              icon: Icons.access_time,
              label: "Duration",
              value: trip.duration ?? "N/A",
            ),

            _detailTile(
              icon: Icons.my_location,
              label: "Start Coordinates",
              value:
              "${trip.startLat}, ${trip.startLng}",
            ),

            _detailTile(
              icon: Icons.flag,
              label: "End Coordinates",
              value:
              "${trip.endLat ?? '-'}, ${trip.endLng ?? '-'}",
            ),
          ],
        ),
      ),
    );
  }

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
                      color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
