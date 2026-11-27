import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/api_client.dart';

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.description,
    required this.mainText,
    this.secondaryText = '',
  });

  final String placeId;

  /// Texte complet, à mettre dans le champ une fois la suggestion choisie.
  final String description;

  /// Nom du lieu (ligne 1 dans l'UI), ex. "Gare de Rabat-Ville".
  final String mainText;

  /// Ville / pays (ligne 2 dans l'UI).
  final String secondaryText;
}

class PlacesException implements Exception {
  const PlacesException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Recherche de lieux Google Places **via le proxy de l'API Moovi**
/// (`/api/maps/places/*`). La clé Google est stockée dans le `.env` de l'API.
class PlacesService {
  PlacesService({ApiClient? client}) : _api = client ?? ApiClient.instance;

  final ApiClient _api;

  Future<List<PlaceSuggestion>> autocomplete(
    String input, {
    String? sessionToken,
    String language = 'fr',
    String? country, // code ISO, ex. 'ga'
    LatLng? bias, // favorise les résultats proches de ce point
    int biasRadiusMeters = 50000,
  }) async {
    final data = await _call(() => _api.request(
          'GET',
          '/api/maps/places/autocomplete',
          query: {
            'input': input,
            'language': language,
            'country': country,
            'sessionToken': sessionToken,
            if (bias != null) 'lat': bias.latitude,
            if (bias != null) 'lng': bias.longitude,
          },
        ));

    final predictions = (data['predictions'] as List?) ?? const [];
    return predictions.whereType<Map>().map((p) {
      final description = p['description']?.toString() ?? '';
      return PlaceSuggestion(
        placeId: p['placeId']?.toString() ?? '',
        description: description,
        mainText: p['mainText']?.toString() ?? description,
        secondaryText: p['secondaryText']?.toString() ?? '',
      );
    }).where((s) => s.placeId.isNotEmpty).toList();
  }

  Future<LatLng> details(
    String placeId, {
    String? sessionToken,
    String language = 'fr',
  }) async {
    final data = await _call(() => _api.request(
          'GET',
          '/api/maps/places/details',
          query: {'placeId': placeId, 'sessionToken': sessionToken},
        ));
    final lat = asNum(data['latitude']);
    final lng = asNum(data['longitude']);
    if (lat == null || lng == null) {
      throw const PlacesException('Lieu introuvable.');
    }
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  Future<Map<String, dynamic>> _call(
      Future<Map<String, dynamic>> Function() request) async {
    try {
      return await request();
    } on ApiException catch (e) {
      throw PlacesException(e.message);
    } catch (_) {
      throw const PlacesException('Connexion impossible. Vérifiez votre réseau.');
    }
  }

  void dispose() {}
}
