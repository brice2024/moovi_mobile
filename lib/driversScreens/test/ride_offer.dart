import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum RideType { voiture, moto }

class RideOffer {
  final String id;
  final RideType type;
  final String from;
  final String to;
  final int minutes;
  final double km;
  final int price; // en FCFA
  final bool clientPrice;
  final int mooviPrice;
  final double clientDistanceKm;
  final int rideMinutes;
  final double totalKm;
  final String? clientId;
  final LatLng? departureLocation;
  final LatLng? destinationLocation;

  const RideOffer({
    required this.id,
    required this.type,
    required this.from,
    required this.to,
    required this.minutes,
    required this.km,
    required this.price,
    required this.mooviPrice,
    this.clientPrice = true,
    this.clientDistanceKm = 1.2,
    this.rideMinutes = 15,
    this.totalKm = 5.0,
    this.clientId,
    this.departureLocation,
    this.destinationLocation,
  });

  factory RideOffer.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final typeStr = data['rideType']?.toString().toLowerCase();
    final type = typeStr == 'moto' ? RideType.moto : RideType.voiture;

    final dep = data['departure'];
    final dest = data['destination'];

    LatLng? depLatLng;
    if (dep is GeoPoint) {
      depLatLng = LatLng(dep.latitude, dep.longitude);
    }

    LatLng? destLatLng;
    if (dest is GeoPoint) {
      destLatLng = LatLng(dest.latitude, dest.longitude);
    }

    final p = (data['price'] as num?)?.toInt() ?? 2000;

    return RideOffer(
      id: doc.id,
      type: type,
      from: data['departureAddress']?.toString() ?? 'Point de départ (Libreville)',
      to: data['destinationAddress']?.toString() ?? 'Destination (Libreville)',
      minutes: 5,
      km: 4.5,
      price: p,
      mooviPrice: p,
      clientPrice: true,
      clientDistanceKm: 1.5,
      rideMinutes: 18,
      totalKm: 6.0,
      clientId: data['clientId']?.toString(),
      departureLocation: depLatLng,
      destinationLocation: destLatLng,
    );
  }
}

// Données démo au Gabon (Libreville) si aucune course en attente
const demoOffersGabon = [
  RideOffer(
    id: 'GA-401',
    type: RideType.voiture,
    from: 'Aéroport International Léon Mba',
    to: 'Quartier Louis, Libreville',
    minutes: 6,
    km: 8.5,
    price: 3500,
    mooviPrice: 3500,
  ),
  RideOffer(
    id: 'GA-402',
    type: RideType.moto,
    from: 'Marché Mont-Bouët',
    to: 'Glass, Libreville',
    minutes: 3,
    km: 3.2,
    price: 1500,
    mooviPrice: 1500,
  ),
  RideOffer(
    id: 'GA-403',
    type: RideType.voiture,
    from: 'Batterie IV',
    to: 'Akanda, Cap Caravane',
    minutes: 10,
    km: 12.0,
    price: 5000,
    mooviPrice: 4500,
  ),
];
