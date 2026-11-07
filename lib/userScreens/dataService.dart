import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ImportDriversService {
  static Future<void> importDrivers() async {
    final firestore = FirebaseFirestore.instance;

    // Charger le JSON
    final jsonString = await rootBundle.loadString(
      'assets/data/moovi_chauffeurs_gabon_50.json',
    );

    final List<dynamic> drivers = jsonDecode(jsonString);

    // Préparer les écritures
    final batch = firestore.batch();

    for (final item in drivers) {
      final driver = Map<String, dynamic>.from(item);

      final docRef = firestore
          .collection('test_drivers')
          .doc(driver['driverId'] as String);

      batch.set(docRef, {
        ...driver,
        'location': GeoPoint(
          (driver['latitude'] as num).toDouble(),
          (driver['longitude'] as num).toDouble(),
        ),
        'isTest': true,
      });
    }

    // Envoyer toutes les écritures
    await batch.commit();

    print('${drivers.length} chauffeurs importés !');
  }
}



class DriverService {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> getDrivers() {
    return _firestore
        .collection('test_drivers')
        .where('isAvailable', isEqualTo: true)
        .snapshots();
  }
}

