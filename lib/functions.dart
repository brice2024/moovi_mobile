import 'services/api_client.dart';
import 'services/session.dart';

String get currentUserId => AppSession.instance.currentUser?.id ?? '';

/// Crée une course (`POST /api/rides`) et renvoie son identifiant.
/// Lève [ApiException] (ex. `ACTIVE_RIDE_EXISTS`, `PRICE_OUT_OF_RANGE`).
Future<String?> addRide(
    {required double departureLat,
    required double departureLng,
    required double destinationLat,
    required double destinationLng,
    required int price,
    String departureAddress = 'Point de départ',
    String destinationAddress = 'Destination',
    String rideType = 'voiture',
    String distanceText = '',
    String durationText = '',
    int? distanceMeters,
    int? durationSeconds,
    String? polyline,
    String? promoCode}) async {
  final data = await ApiClient.instance.request('POST', '/api/rides', body: {
    'departureLat': departureLat,
    'departureLng': departureLng,
    'destinationLat': destinationLat,
    'destinationLng': destinationLng,
    'departureAddress': departureAddress,
    'destinationAddress': destinationAddress,
    'rideType': rideType,
    'price': price,
    if (distanceText.isNotEmpty) 'distanceText': distanceText,
    if (durationText.isNotEmpty) 'durationText': durationText,
    if (distanceMeters != null && distanceMeters > 0)
      'distanceMeters': distanceMeters,
    if (durationSeconds != null && durationSeconds > 0)
      'durationSeconds': durationSeconds,
    if (polyline != null && polyline.isNotEmpty) 'polyline': polyline,
    if (promoCode != null && promoCode.isNotEmpty) 'promoCode': promoCode,
  });
  return (data['id'] ?? data['rideId'])?.toString();
}

/// Chauffeurs disponibles autour d'un point (`GET /api/drivers/nearby`).
Future<List<Map<String, dynamic>>> findNearbyDrivers(
    double latitude, double longitude,
    {String? vehicleType}) async {
  final data = await ApiClient.instance.request('GET', '/api/drivers/nearby',
      query: {'lat': latitude, 'lng': longitude, 'vehicleType': vehicleType});
  return (data['drivers'] as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}
