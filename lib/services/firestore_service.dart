import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/trip_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 🔹 Save Trip and return Trip ID
  Future<String> saveTrip(Trip trip) async {
    DocumentReference docRef =
    await _db.collection('trips').add(trip.toMap());

    print("Trip saved with ID: ${docRef.id}");
    return docRef.id;
  }
  Stream<List<Trip>> getTrips() {
    return _db
        .collection('trips')
        .orderBy('startTime', descending: true)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => Trip.fromMap(doc.data())).toList());
  }


  // 🔹 Save Speed Log inside a trip
  Future<void> saveSpeedLog(
      String tripId,
      double speed,
      double lat,
      double lng,
      ) async {
    await _db
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
