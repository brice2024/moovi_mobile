import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

/// Résultat d'un calcul d'itinéraire : tracé + distance + durée.
class RouteInfo {
  final List<LatLng> points;
  final int distanceMeters;
  final Duration duration;

  const RouteInfo({
    required this.points,
    required this.distanceMeters,
    required this.duration,
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

class DirectionsService {
  // ⚠️ Ne laisse pas la clé en dur dans le code : voir notes plus bas.
  static const String apiKey = "AIzaSyBs6DVjYiLlKjtJHqRwO6qTKouJ7o0f5F4";

  Future<RouteInfo> getRoute(
      LatLng depart,
      LatLng destination,
      ) async {
    final url = Uri.parse(
      "https://routes.googleapis.com/directions/v2:computeRoutes",
    );

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        // On ajoute distanceMeters et duration au masque de champs
        "X-Goog-FieldMask":
        "routes.polyline.encodedPolyline,routes.distanceMeters,routes.duration",
      },
      body: jsonEncode({
        "origin": {
          "location": {
            "latLng": {
              "latitude": depart.latitude,
              "longitude": depart.longitude,
            }
          }
        },
        "destination": {
          "location": {
            "latLng": {
              "latitude": destination.latitude,
              "longitude": destination.longitude,
            }
          }
        },
        "travelMode": "DRIVE",
        // Durée tenant compte du trafic (facturé à un tarif supérieur) :
        // "routingPreference": "TRAFFIC_AWARE",
        "polylineQuality": "HIGH_QUALITY",
      }),
    );

    if (response.statusCode != 200) {
      throw Exception("Erreur Google Routes : ${response.body}");
    }

    final data = jsonDecode(response.body);
    final routes = data["routes"] as List?;

    if (routes == null || routes.isEmpty) {
      throw Exception("Aucun itinéraire trouvé");
    }

    final route = routes.first;

    final encodedPolyline = route["polyline"]["encodedPolyline"] as String;
    final decoded = PolylinePoints.decodePolyline(encodedPolyline);

    // distanceMeters est un entier ; absent si distance = 0
    final distanceMeters = (route["distanceMeters"] as num?)?.toInt() ?? 0;

    // duration est une chaîne au format "1234s"
    final durationStr = (route["duration"] as String?) ?? "0s";
    final seconds = int.tryParse(durationStr.replaceAll('s', '')) ?? 0;

    return RouteInfo(
      points: decoded.map((p) => LatLng(p.latitude, p.longitude)).toList(),
      distanceMeters: distanceMeters,
      duration: Duration(seconds: seconds),
    );
  }
}