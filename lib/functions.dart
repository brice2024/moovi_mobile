import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';

final FirebaseFirestore _firestore = FirebaseFirestore.instance;

String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

// Calcul du prix estimatif en FCFA
double calculDePrix(double distanceKm, double prixDuKm) {
  return distanceKm * prixDuKm;
}

// Prix minimum formaté
String prixMinimum(double distanceKm, double prixDuKm) {
  double prix = distanceKm * prixDuKm;
  return prix.toStringAsFixed(0);
}

/// Ajouter une course dans Firestore et renvoie son ID unique
Future<String?> addRide({
  required double departureLat,
  required double departureLng,
  required double destinationLat,
  required double destinationLng,
  required int price,
  String departureAddress = 'Point de départ',
  String destinationAddress = 'Destination',
  String rideType = 'voiture',
  String distanceText = '',
  String durationText = '',
}) async {
  final uid = currentUserId;
  if (uid.isEmpty) return null;

  final rideDoc = await _firestore.collection("rides").add({
    "clientId": uid,
    "departure": GeoPoint(departureLat, departureLng),
    "destination": GeoPoint(destinationLat, destinationLng),
    "departureAddress": departureAddress,
    "destinationAddress": destinationAddress,
    "rideType": rideType,
    "price": price,
    "currency": "XAF",
    "distance": distanceText,
    "duration": durationText,
    "status": "searching", // searching -> accepted -> driver_arrived -> in_progress -> completed
    "driverId": null,
    "isPaid": false,
    "paymentMethod": null,
    "createdAt": FieldValue.serverTimestamp(),
  });

  // Sauvegarde aussi dans l'historique de l'utilisateur
  await _firestore
      .collection("users")
      .doc(uid)
      .collection("rides")
      .doc(rideDoc.id)
      .set({
    "rideId": rideDoc.id,
    "departure": GeoPoint(departureLat, departureLng),
    "destination": GeoPoint(destinationLat, destinationLng),
    "departureAddress": departureAddress,
    "destinationAddress": destinationAddress,
    "rideType": rideType,
    "price": price,
    "currency": "XAF",
    "status": "searching",
    "createdAt": FieldValue.serverTimestamp(),
  });

  return rideDoc.id;
}

// Rechercher des chauffeurs dans un rayon (ex: 6 Km)
Stream<List<DocumentSnapshot<Map<String, dynamic>>>> findNearbyDrivers(
  double departureLat,
  double departureLng,
) {
  final center = GeoFirePoint(
    GeoPoint(departureLat, departureLng),
  );

  return GeoCollectionReference<Map<String, dynamic>>(
    FirebaseFirestore.instance.collection('drivers'),
  ).subscribeWithin(
    center: center,
    radiusInKm: 6,
    field: 'position',
    geopointFrom: (data) {
      final pos = data['position'];
      if (pos is Map && pos.containsKey('geopoint')) {
        return pos['geopoint'] as GeoPoint;
      }
      if (data['location'] is GeoPoint) {
        return data['location'] as GeoPoint;
      }
      return GeoPoint(departureLat, departureLng);
    },
  );
}
