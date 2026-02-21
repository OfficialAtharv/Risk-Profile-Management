import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/trip_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// 🔹 Save Trip and return Trip ID
  Future<String> saveTrip(Trip trip) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception("User not logged in");
    }

    // Create new document under users/{uid}/trips
    DocumentReference docRef = await _db
        .collection('users')
        .doc(user.uid)
        .collection('trips')
        .add(trip.toMap());

    print("Trip saved with ID: ${docRef.id}");

    return docRef.id;
  }

  /// 🔹 Get Trips (USER-WISE)
  Stream<List<Trip>> getTrips() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception("User not logged in");
    }

    return _db
        .collection('users')
        .doc(user.uid)
        .collection('trips')
        .orderBy('startTime', descending: true)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => Trip.fromMap(doc.data())).toList());
  }

  /// 🔹 Save Speed Log inside specific trip
  Future<void> saveSpeedLog(
      String tripId,
      double speed,
      double lat,
      double lng,
      ) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception("User not logged in");
    }

    await _db
        .collection('users')
        .doc(user.uid)
        .collection('trips')
        .doc(tripId)
        .collection('speed_logs')
        .add({
      'speed': speed,
      'lat': lat,
      'lng': lng,
      'timestamp': FieldValue.serverTimestamp(),
    });

    print("Speed log saved");
  }
}