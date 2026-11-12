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
    try {
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      final data = rideDoc.data();
      final clientId = data?['clientId'] as String?;
      final driverId = data?['driverId'] as String?;

      final updateData = <String, dynamic>{
        'isPaid': true,
        'paymentMethod': paymentMethod, // 'paycentral' ou 'cash'
        'paymentTransactionId': transactionId,
        'paymentProvider': provider,
        'paidAmount': amount,
        'paidAt': FieldValue.serverTimestamp(),
        'status': 'completed',
      };

      final batch = _firestore.batch();
      batch.update(_firestore.collection('rides').doc(rideId), updateData);

      // Synchroniser avec l'historique du client
      if (clientId != null && clientId.isNotEmpty) {
        final userRideRef = _firestore
            .collection('users')
            .doc(clientId)
            .collection('rides')
            .doc(rideId);
        batch.set(userRideRef, updateData, SetOptions(merge: true));
      }

      // Mettre à jour les statistiques et revenus du chauffeur
      if (driverId != null && driverId.isNotEmpty) {
        final driverRef = _firestore.collection('drivers').doc(driverId);
        batch.set(driverRef, {
          'ridesCount': FieldValue.increment(1),
          'totalRevenue': FieldValue.increment(amount),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Erreur synchronisation markRideAsPaid : $e');
      // Fallback simple
      await _firestore.collection('rides').doc(rideId).update({
        'isPaid': true,
        'paymentMethod': paymentMethod,
        'paymentTransactionId': transactionId,
        'paymentProvider': provider,
        'paidAmount': amount,
        'paidAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GESTION DU PORTEFEUILLE CHAUFFEUR & COMMISSIONS MOOVI
  // ─────────────────────────────────────────────────────────────────────────

  /// Écoute en direct les données du portefeuille du chauffeur
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamDriverWallet(String driverId) {
    return _firestore.collection('drivers').doc(driverId).snapshots();
  }

  /// Écoute les transactions du portefeuille (recharges et commissions)
  Stream<QuerySnapshot<Map<String, dynamic>>> streamWalletTransactions(String driverId) {
    return _firestore
        .collection('drivers')
        .doc(driverId)
        .collection('wallet_transactions')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Recharger le portefeuille chauffeur via Mobile Money (PawaPay)
  Future<void> rechargeDriverWallet({
    required String driverId,
    required int amount,
    required String depositId,
    required String operatorCode,
    required String operatorName,
    required String phoneNumber,
  }) async {
    final driverRef = _firestore.collection('drivers').doc(driverId);
    final txRef = driverRef.collection('wallet_transactions').doc(depositId);

    final batch = _firestore.batch();

    // 1. Enregistrer la transaction
    batch.set(txRef, {
      'id': depositId,
      'type': 'deposit', // Rechargement
      'amount': amount,
      'operatorCode': operatorCode,
      'operatorName': operatorName,
      'phoneNumber': phoneNumber,
      'gateway': 'pawapay',
      'status': 'completed',
      'description': 'Rechargement Mobile Money ($operatorName)',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 2. Créditer le solde et réactiver le chauffeur s'il était bloqué
    batch.set(
      driverRef,
      {
        'walletBalance': FieldValue.increment(amount),
        'isWalletBlocked': false, // Déblocage automatique après recharge
        'isAvailable': true, // Redevient disponible pour les courses
        'lastRechargeAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
    debugPrint('✅ Portefeuille chauffeur $driverId rechargé de $amount FCFA via PawaPay.');
  }

  /// Déduire la commission plateforme sur une course réglée en Cash
  /// Exemple : Course à 3 000 FCFA à 15% de commission -> 450 FCFA déduits du portefeuille
  Future<int> deductRideCommission({
    required String driverId,
    required String rideId,
    required int ridePrice,
    double commissionRate = 0.15, // 15% par défaut
  }) async {
    final commissionAmount = (ridePrice * commissionRate).round();
    final driverRef = _firestore.collection('drivers').doc(driverId);
    final txRef = driverRef.collection('wallet_transactions').doc('COMM-$rideId');

    // Récupérer le solde actuel
    final driverSnap = await driverRef.get();
    final currentBalance = (driverSnap.data()?['walletBalance'] as num?)?.toInt() ?? 5000;
    final newBalance = currentBalance - commissionAmount;
    final isBlocked = newBalance < 0; // Bloqué si solde insuffisant/négatif

    final batch = _firestore.batch();

    // 1. Transaction de prélèvement de commission
    batch.set(txRef, {
      'id': 'COMM-$rideId',
      'type': 'commission',
      'amount': -commissionAmount,
      'rideId': rideId,
      'ridePrice': ridePrice,
      'commissionRate': commissionRate,
      'status': 'completed',
      'description': 'Commission Moovi (${(commissionRate * 100).toInt()}%) - Course Cash',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 2. Mise à jour solde et état de blocage
    batch.set(
      driverRef,
      {
        'walletBalance': newBalance,
        'isWalletBlocked': isBlocked,
        'isAvailable': !isBlocked, // Si le solde est épuisé, passe hors-ligne
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    // 3. Noter la commission sur la course
    batch.update(_firestore.collection('rides').doc(rideId), {
      'platformCommission': commissionAmount,
      'commissionRate': commissionRate,
      'commissionDeducted': true,
    });

    await batch.commit();
    debugPrint('💼 Commission de $commissionAmount FCFA déduite. Nouveau solde : $newBalance FCFA (Bloqué: $isBlocked)');
    return commissionAmount;
  }
}

