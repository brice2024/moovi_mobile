import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Lieu affiché dans la recherche (enregistré ou récent).
class KnownPlace {
  const KnownPlace({
    required this.label,
    required this.address,
    required this.position,
    this.id,
    String? fieldText,
  }) : _fieldText = fieldText;

  final String? _fieldText;

  /// Texte à placer dans le champ de recherche quand on choisit ce lieu.
  String get fieldText => _fieldText ?? label;

  /// Identifiant du document `saved_places` (null pour un lieu récent).
  final String? id;
  final String label;
  final String address;
  final LatLng position;

  bool isNear(LatLng other) =>
      (position.latitude - other.latitude).abs() < 0.0002 &&
      (position.longitude - other.longitude).abs() < 0.0002;
}

/// Lieux enregistrés (`users/{uid}/saved_places`) et destinations récentes
/// (`users/{uid}/rides`).
class SavedPlacesService {
  SavedPlacesService._();
  static final SavedPlacesService instance = SavedPlacesService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? get _savedRef {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection('saved_places');
  }

  /// Lieux enregistrés, du plus récent au plus ancien.
  Stream<List<KnownPlace>> savedPlaces() {
    final ref = _savedRef;
    if (ref == null) return Stream.value(const []);
    return ref.orderBy('createdAt', descending: true).snapshots().map(
          (snap) => [
            for (final doc in snap.docs)
              if (_placeFrom(doc.id, doc.data()) case final p?) p,
          ],
        );
  }

  KnownPlace? _placeFrom(String id, Map<String, dynamic> data) {
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    final address = data['address']?.toString() ?? '';
    final label = data['label']?.toString() ?? '';
    return KnownPlace(
      id: id,
      label: label.isEmpty ? address : label,
      address: address,
      position: LatLng(lat, lng),
      fieldText: address.isEmpty ? null : address,
    );
  }

  Future<void> savePlace({
    required String label,
    required String address,
    required LatLng position,
  }) async {
    final ref = _savedRef;
    if (ref == null) return;
    await ref.add({
      'label': label,
      'address': address,
      'lat': position.latitude,
      'lng': position.longitude,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deletePlace(String id) async {
    await _savedRef?.doc(id).delete();
  }

  /// 5 dernières destinations distinctes (par adresse) des courses du client.
  Stream<List<KnownPlace>> recentDestinations({int limit = 5}) {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection('users')
        .doc(uid)
        .collection('rides')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .map((snap) {
      final seen = <String>{};
      final result = <KnownPlace>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final dest = data['destination'];
        final address = data['destinationAddress']?.toString().trim() ?? '';
        if (dest is! GeoPoint || address.isEmpty) continue;
        if (!seen.add(address.toLowerCase())) continue;
        final parts = address.split(',');
        result.add(KnownPlace(
          label: parts.first.trim(),
          address: parts.length > 1
              ? parts.skip(1).join(',').trim()
              : address,
          position: LatLng(dest.latitude, dest.longitude),
          fieldText: address,
        ));
        if (result.length >= limit) break;
      }
      return result;
    });
  }
}
