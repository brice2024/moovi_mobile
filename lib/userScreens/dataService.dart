import '../functions.dart';
import '../services/api_client.dart';
import '../services/realtime_service.dart';

/// Chauffeurs disponibles affichés sur la carte passager
/// (remplace l'écoute de la collection Firestore `test_drivers`).
class NearbyDriversService {
  /// `GET /api/drivers/nearby` autour de la position fournie, mis à jour en
  /// temps réel : déplacements appliqués directement depuis
  /// `driver:location_updated`, liste rechargée quand un chauffeur passe en
  /// ligne ou hors ligne.
  Stream<List<Map<String, dynamic>>> getDrivers(
    ({double latitude, double longitude})? Function() position, {
    Duration interval = const Duration(seconds: 8),
  }) {
    return liveApi<List<Map<String, dynamic>>>(
      () async {
        final pos = position();
        if (pos == null) return const <Map<String, dynamic>>[];
        return findNearbyDrivers(pos.latitude, pos.longitude);
      },
      events: const {'driver:availability_changed', 'driver:location_updated'},
      onEvent: (e, last) {
        if (e.name != 'driver:location_updated') return null;
        final id = e.data['driverId']?.toString();
        final list = last ?? const <Map<String, dynamic>>[];
        // Chauffeur hors de la liste (trop loin) : rien à afficher, pas de
        // rechargement à chaque déplacement des autres chauffeurs.
        if (!list.any((d) => d['id']?.toString() == id)) return list;
        return [
          for (final d in list)
            if (d['id']?.toString() == id)
              {
                ...d,
                'latitude': e.data['latitude'],
                'longitude': e.data['longitude'],
                'heading': e.data['heading'] ?? d['heading'],
              }
            else
              d,
        ];
      },
      fallback: interval,
      safety: const Duration(seconds: 30),
    );
  }
}
