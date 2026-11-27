import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

import '../api_client.dart';

/// Prix recommandé par l'API pour une catégorie (voiture, confort, moto).
class PriceEstimate {
  final String rideType;
  final int recommendedPrice;
  final int minPrice;
  final int maxPrice;
  final int step;

  const PriceEstimate({
    required this.rideType,
    required this.recommendedPrice,
    this.minPrice = 500,
    this.maxPrice = 50000,
    this.step = 250,
  });

  factory PriceEstimate.fromJson(Map<String, dynamic> json) => PriceEstimate(
        rideType: json['rideType']?.toString() ?? 'voiture',
        recommendedPrice: asNum(json['recommendedPrice'])?.toInt() ?? 0,
        minPrice: asNum(json['minPrice'])?.toInt() ?? 500,
        maxPrice: asNum(json['maxPrice'])?.toInt() ?? 50000,
        step: asNum(json['step'])?.toInt() ?? 250,
      );
}

/// Résultat d'un calcul d'itinéraire : tracé + distance + durée.
class RouteInfo {
  final List<LatLng> points;
  final int distanceMeters;
  final Duration duration;

  /// Polyline encodée (transmise à l'API lors de la création de la course).
  final String encodedPolyline;

  /// Prix recommandés par catégorie, calculés par l'API.
  final List<PriceEstimate> priceEstimates;

  const RouteInfo({
    required this.points,
    required this.distanceMeters,
    required this.duration,
    this.encodedPolyline = '',
    this.priceEstimates = const [],
  });

  double get distanceKm => distanceMeters / 1000;

  /// Ex: "850 m" ou "12,4 km"
  String get distanceText => distanceMeters < 1000
      ? '$distanceMeters m'
      : '${distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km';

  /// Ex: "8 min" ou "1 h 05 min"
  String get durationText {
    final totalMinutes = (duration.inSeconds / 60).round();
    if (totalMinutes < 1) return '1 min';
    if (totalMinutes < 60) return '$totalMinutes min';
    final h = totalMinutes ~/ 60;
    final m = (totalMinutes % 60).toString().padLeft(2, '0');
    return '$h h $m min';
  }
}

/// Itinéraire Google Routes **via le proxy de l'API Moovi**
/// (`POST /api/maps/routes/compute`). La clé Google reste côté serveur.
class DirectionsService {
  Future<RouteInfo> getRoute(
    LatLng depart,
    LatLng destination,
  ) async {
    final data = await ApiClient.instance.request(
      'POST',
      '/api/maps/routes/compute',
      body: {
        'originLat': depart.latitude,
        'originLng': depart.longitude,
        'destinationLat': destination.latitude,
        'destinationLng': destination.longitude,
        'travelMode': 'DRIVE',
      },
    );

    final encoded = data['encodedPolyline']?.toString() ?? '';
    if (encoded.isEmpty) {
      throw Exception('Aucun itinéraire trouvé');
    }
    final decoded = PolylinePoints.decodePolyline(encoded);

    return RouteInfo(
      points: decoded.map((p) => LatLng(p.latitude, p.longitude)).toList(),
      distanceMeters: asNum(data['distanceMeters'])?.toInt() ?? 0,
      duration: Duration(seconds: asNum(data['durationSeconds'])?.toInt() ?? 0),
      encodedPolyline: encoded,
      priceEstimates: (data['priceEstimates'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => PriceEstimate.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
