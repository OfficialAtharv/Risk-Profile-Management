import 'package:cloud_firestore/cloud_firestore.dart';

class Trip {
  final DateTime startTime;
  final double startLat;
  final double startLng;

  DateTime? endTime;
  double? endLat;
  double? endLng;
  String? duration;
  double? distance;

  Trip({
    required this.startTime,
    required this.startLat,
    required this.startLng,
  });

  void endTrip({
    required DateTime endTime,
    required double endLat,
    required double endLng,
    required String duration,
    required double distance,
  }) {
    this.endTime = endTime;
    this.endLat = endLat;
    this.endLng = endLng;
    this.duration = duration;
    this.distance = distance;
  }

 
  Map<String, dynamic> toMap() {
    return {
      'startTime': Timestamp.fromDate(startTime),
      'startLat': startLat,
      'startLng': startLng,
      'endTime': endTime != null ? Timestamp.fromDate(endTime!) : null,
      'endLat': endLat,
      'endLng': endLng,
      'duration': duration,
      'distance': distance,
    };
  }


  factory Trip.fromMap(Map<String, dynamic> map) {
    return Trip(
      startTime: (map['startTime'] as Timestamp).toDate(),
      startLat: map['startLat'],
      startLng: map['startLng'],
    )
      ..endTime = map['endTime'] != null
          ? (map['endTime'] as Timestamp).toDate()
          : null
      ..endLat = map['endLat']
      ..endLng = map['endLng']
      ..duration = map['duration']
      ..distance = map['distance'];
  }
}
