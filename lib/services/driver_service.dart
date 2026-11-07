import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class DriverService {
  DriverService._();
  static final DriverService instance = DriverService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  /// Vérifie si l'utilisateur connecté est déjà inscrit en tant que chauffeur
  Future<bool> isDriverRegistered(String uid) async {
    try {
      final doc = await _firestore.collection('drivers').doc(uid).get();
      if (!doc.exists) return false;
      final data = doc.data();
      return data != null && (data.containsKey('car') || data.containsKey('moto'));
    } catch (e) {
      debugPrint('Erreur vérification chauffeur : $e');
      return false;
    }
  }

  /// Récupère les données du chauffeur (véhicule, statut, profil)
  Future<Map<String, dynamic>?> getDriverData(String uid) async {
    try {
      final doc = await _firestore.collection('drivers').doc(uid).get();
      return doc.data();
    } catch (e) {
      debugPrint('Erreur récupération profil chauffeur : $e');
      return null;
    }
  }

  /// Met à jour la disponibilité et la position du chauffeur
  Future<void> updateDriverAvailability({
    required String uid,
    required bool isOnline,
    GeoPoint? location,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'isAvailable': isOnline,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (location != null) {
        updateData['location'] = location;
      }
      await _firestore.collection('drivers').doc(uid).set(
        updateData,
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Erreur mise à jour disponibilité chauffeur : $e');
    }
  }

  /// Écoute en direct les courses disponibles à proximité (en recherche de chauffeur)
  Stream<QuerySnapshot<Map<String, dynamic>>> getAvailableRidesStream() {
    return _firestore
        .collection('rides')
        .where('status', isEqualTo: 'searching')
        .snapshots();
  }

  /// Écoute une course spécifique
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamRide(String rideId) {
    return _firestore.collection('rides').doc(rideId).snapshots();
  }

  /// Écoute les propositions des chauffeurs pour une course donnée
  Stream<QuerySnapshot<Map<String, dynamic>>> streamRideOffers(String rideId) {
    return _firestore
        .collection('rides')
        .doc(rideId)
        .collection('offers')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// Envoie ou met à jour une offre de course faite par le chauffeur
  Future<void> sendDriverOffer({
    required String rideId,
    required String driverId,
    required String driverName,
    required double rating,
    required String carModel,
    required String plate,
    required int price,
    required int arrivalMinutes,
    String? photoUrl,
    String level = 'Or',
  }) async {
    final offerRef = _firestore
        .collection('rides')
        .doc(rideId)
        .collection('offers')
        .doc(driverId);

    await offerRef.set({
      'driverId': driverId,
      'driverName': driverName,
      'rating': rating,
      'level': level,
      'car': carModel,
      'plate': plate,
      'price': price,
      'arrivalMinutes': arrivalMinutes,
      'photoUrl': photoUrl,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Le client accepte l'offre d'un chauffeur
  Future<void> acceptDriverOffer({
    required String rideId,
    required String driverId,
    required int agreedPrice,
    required String driverName,
    required String car,
    required String plate,
    String? photoUrl,
  }) async {
    final batch = _firestore.batch();
    final rideRef = _firestore.collection('rides').doc(rideId);

    batch.update(rideRef, {
      'status': 'accepted',
      'driverId': driverId,
      'agreedPrice': agreedPrice,
      'driverName': driverName,
      'driverCar': car,
      'driverPlate': plate,
      'driverPhotoUrl': photoUrl,
      'acceptedAt': FieldValue.serverTimestamp(),
    });

    // Marquer l'offre acceptée
    final offerRef = rideRef.collection('offers').doc(driverId);
    batch.update(offerRef, {'status': 'accepted'});

    await batch.commit();
  }

  /// Mise à jour du statut d'avancement de la course (chauffeur)
  /// Statuts possibles : 'driver_arrived', 'in_progress', 'completed', 'cancelled'
  Future<void> updateRideStatus({
    required String rideId,
    required String newStatus,
  }) async {
    await _firestore.collection('rides').doc(rideId).update({
      'status': newStatus,
      '${newStatus}At': FieldValue.serverTimestamp(),
    });
  }

  /// Enregistrement du paiement final de la course
  Future<void> markRideAsPaid({
    required String rideId,
    required String paymentMethod,
    required int amount,
    String? transactionId,
    String? provider,
  }) async {
    await _firestore.collection('rides').doc(rideId).update({
      'isPaid': true,
      'paymentMethod': paymentMethod, // 'paycentral' ou 'cash'
      'paymentTransactionId': transactionId,
      'paymentProvider': provider,
      'paidAmount': amount,
      'paidAt': FieldValue.serverTimestamp(),
    });
  }
}

