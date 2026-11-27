import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/api_client.dart';

enum RideType { voiture, moto }

/// Course disponible vue par le chauffeur (`GET /api/rides/available`).
class RideOffer {
  final String id;
  final RideType type;

  /// Catégorie exacte côté API : voiture | confort | moto.
  final String rideTypeName;
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
  final String? clientName;
  final String? clientPhone;
  final LatLng? departureLocation;
  final LatLng? destinationLocation;

  const RideOffer({
    required this.id,
    required this.type,
    this.rideTypeName = 'voiture',
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
    this.clientName,
    this.clientPhone,
    this.departureLocation,
    this.destinationLocation,
  });

  factory RideOffer.fromApi(Map<String, dynamic> data) {
    final typeStr = data['rideType']?.toString().toLowerCase() ?? 'voiture';
    final type = typeStr == 'moto' ? RideType.moto : RideType.voiture;

    LatLng? point(dynamic value) {
      if (value is! Map) return null;
      final lat = asNum(value['latitude']);
      final lng = asNum(value['longitude']);
      if (lat == null || lng == null) return null;
      return LatLng(lat.toDouble(), lng.toDouble());
    }

    final price = (asNum(data['finalPrice']) ?? asNum(data['price']) ?? 0).toInt();
    final rideKm = ((asNum(data['distanceMeters']) ?? 0) / 1000);
    final rideMin = ((asNum(data['durationSeconds']) ?? 0) / 60).round();
    final pickupKm = (asNum(data['pickupDistanceKm']) ?? 0).toDouble();
    final pickupMin = (asNum(data['pickupEtaMinutes']) ?? 0).toInt();

    double round1(num v) => double.parse(v.toStringAsFixed(1));

    return RideOffer(
      id: (data['id'] ?? data['rideId']).toString(),
      type: type,
      rideTypeName: typeStr,
      from: data['departureAddress']?.toString() ?? 'Point de départ',
      to: data['destinationAddress']?.toString() ?? 'Destination',
      minutes: rideMin,
      km: round1(rideKm),
      price: price,
      mooviPrice: price,
      clientPrice: true,
      clientDistanceKm: round1(pickupKm),
      rideMinutes: pickupMin + rideMin,
      totalKm: round1(pickupKm + rideKm),
      clientId: data['clientId']?.toString(),
      clientName: data['clientName']?.toString(),
      clientPhone: data['clientPhone']?.toString(),
      departureLocation: point(data['departure']),
      destinationLocation: point(data['destination']),
    );
  }
}
