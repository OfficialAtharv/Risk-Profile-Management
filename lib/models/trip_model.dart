import 'package:cloud_firestore/cloud_firestore.dart';

class Trip {
  final DateTime startTime;
  final double startLat;
  final double startLng;
  final String? startLocation;

  DateTime? endTime;
  double? endLat;
  double? endLng;
  String? duration;
  double? distance;
  String? endLocation;
  double? maxSpeed;


  Trip({
    required this.startTime,
    required this.startLat,
    required this.startLng,
    this.startLocation,
    this.maxSpeed = 0.0,
  });

  void endTrip({
    required DateTime endTime,
    required double endLat,
    required double endLng,
    required String duration,
    required double distance,
    required String endLocation,

  }) {
    this.endTime = endTime;
    this.endLat = endLat;
    this.endLng = endLng;
    this.duration = duration;
    this.distance = distance;
    this.endLocation = endLocation;
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
      'startLocation': startLocation,
      'endLocation': endLocation,
      'maxSpeed': maxSpeed,
    };
  }


  factory Trip.fromMap(Map<String, dynamic> map) {
    return Trip(
      startTime: (map['startTime'] as Timestamp).toDate(),
      startLat: map['startLat'],
      startLng: map['startLng'],
      startLocation: map['startLocation'],
      maxSpeed: (map['maxSpeed'] ?? 0).toDouble(),
    )
      ..endTime = map['endTime'] != null
          ? (map['endTime'] as Timestamp).toDate()
          : null
      ..endLat = map['endLat']
      ..endLng = map['endLng']
      ..endLocation = map['endLocation']
      ..duration = map['duration'] ?? "00:00:00"
      ..maxSpeed = (map['maxSpeed'] ?? 0).toDouble();


  }
}
