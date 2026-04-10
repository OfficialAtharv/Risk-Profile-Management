import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/trip_model.dart';
import '../services/firestore_service.dart';
import 'trip_details_screen.dart';

class TripHistoryScreen extends StatelessWidget {
  const TripHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: SafeArea(
        child: StreamBuilder<List<Trip>>(
          stream: firestoreService.getTrips(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 30,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1730),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFF1A2743),
                      ),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history_rounded,
                          color: Color(0xFF4DA3FF),
                          size: 42,
                        ),
                        SizedBox(height: 14),
                        Text(
                          "No Trips Yet",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Your recent driving trips will appear here.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF8F98AD),
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final trips = snapshot.data!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Trip History",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Your recent driving trips",
                        style: TextStyle(
                          color: Color(0xFF8F98AD),
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                      ),

                      const SizedBox(height: 16),

                      /// subtle divider glow (figma feel)
                      Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Color(0xFF1A2743),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    itemCount: trips.length,
                    itemBuilder: (context, index) {
                      final trip = trips[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _TripCard(trip: trip),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final Trip trip;

  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final String distance =
        "${((trip.distance ?? 0) / 1000).toStringAsFixed(1)} km";

    final String duration = _formatDurationForCard(trip.duration);
    final String maxSpeed = "-- km/h";

    final String dateLabel = _getDateLabel(trip.startTime);
    final String timeLabel = DateFormat('h:mm a').format(trip.startTime);

    final String title = _buildTripTitle(
      trip.startLocation,
      trip.endLocation,
    );

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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [
              Color(0xFF0B1730),
              Color(0xFF0D1F3F),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: const Color(0xFF1A2743),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// Title row
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: Color(0xFF4DA3FF),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF7B879C),
                  size: 22,
                ),
              ],
            ),

            const SizedBox(height: 4),

            /// Date row
            Text(
              "$dateLabel   •   $timeLabel",
              style: const TextStyle(
                color: Color(0xFF8F98AD),
                fontSize: 13.5,
              ),
            ),

            const SizedBox(height: 16),

            /// Stats
            Row(
              children: [
                _TripStatBox(
                  title: "Distance",
                  value: distance,
                ),
                const SizedBox(width: 10),
                _TripStatBox(
                  title: "Duration",
                  value: duration,
                ),
                const SizedBox(width: 10),
                _TripStatBox(
                  title: "Max Speed",
                  value: maxSpeed,
                ),
              ],
            ),

            const SizedBox(height: 14),

            /// Placeholder badge only
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.orange.withOpacity(0.10),
                border: Border.all(
                  color: Colors.orange.withOpacity(0.35),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    "Trip status coming soon",
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _buildTripTitle(String? start, String? end) {
    final String from = _shortPlace(start, fallback: "Start");
    final String to = _shortPlace(end, fallback: "Destination");
    return "$from to $to";
  }

  static String _shortPlace(String? value, {required String fallback}) {
    if (value == null || value.trim().isEmpty) return fallback;

    final parts = value.split(',');
    return parts.first.trim().isEmpty ? fallback : parts.first.trim();
  }

  static String _getDateLabel(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tripDay = DateTime(dateTime.year, dateTime.month, dateTime.day);

    final diff = today.difference(tripDay).inDays;

    if (diff == 0) return "Today";
    if (diff == 1) return "Yesterday";

    return DateFormat('MMM d').format(dateTime);
  }

  static String _formatDurationForCard(String? rawDuration) {
    if (rawDuration == null || rawDuration.isEmpty) return "N/A";

    final parts = rawDuration.split(':');
    if (parts.length != 3) return rawDuration;

    final int hours = int.tryParse(parts[0]) ?? 0;
    final int minutes = int.tryParse(parts[1]) ?? 0;

    if (hours > 0 && minutes > 0) {
      return "${hours}h ${minutes}m";
    } else if (hours > 0) {
      return "${hours}h";
    } else {
      return "${minutes} min";
    }
  }
}

class _TripStatBox extends StatelessWidget {
  final String title;
  final String value;

  const _TripStatBox({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 10,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF17243D),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF8F98AD),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}