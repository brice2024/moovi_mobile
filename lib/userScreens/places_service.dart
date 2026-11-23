import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

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
  String toString() => 'PlacesException: $message';
}

class PlacesService {
  PlacesService(this.apiKey, {http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  static const _timeout = Duration(seconds: 8);

  Future<List<PlaceSuggestion>> autocomplete(
    String input, {
    String? sessionToken,
    String language = 'fr',
    String? country, // code ISO, ex. 'ma'
    LatLng? bias, // favorise les résultats proches de ce point
    int biasRadiusMeters = 50000,
  }) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {
        'input': input,
        'key': apiKey,
        'language': language,
        if (sessionToken != null) 'sessiontoken': sessionToken,
        if (country != null) 'components': 'country:$country',
        if (bias != null) ...{
          'location': '${bias.latitude},${bias.longitude}',
          'radius': '$biasRadiusMeters',
        },
      },
    );

    final json = await _getJson(uri);
    final status = json['status'] as String?;
    if (status == 'ZERO_RESULTS') return const [];
    _throwIfNotOk(json, status);

    final predictions = (json['predictions'] as List?) ?? const [];
    return predictions.map((p) {
      final structured = p['structured_formatting'] as Map<String, dynamic>?;
      final description = p['description'] as String? ?? '';
      return PlaceSuggestion(
        placeId: p['place_id'] as String,
        description: description,
        mainText: structured?['main_text'] as String? ?? description,
        secondaryText: structured?['secondary_text'] as String? ?? '',
      );
    }).toList();
  }

  Future<LatLng> details(
    String placeId, {
    String? sessionToken,
    String language = 'fr',
  }) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      {
        'place_id': placeId,
        'fields': 'geometry',
        'key': apiKey,
        'language': language,
        if (sessionToken != null) 'sessiontoken': sessionToken,
      },
    );

    final json = await _getJson(uri);
    _throwIfNotOk(json, json['status'] as String?);

    final loc = json['result']?['geometry']?['location'];
    if (loc == null) throw const PlacesException('Lieu introuvable.');
    return LatLng(
      (loc['lat'] as num).toDouble(),
      (loc['lng'] as num).toDouble(),
    );
  }

  /// Adresse lisible d'un point (Geocoding API). Renvoie null si aucune
  /// adresse n'est trouvée ; lève [PlacesException] en cas d'erreur
  /// (API non activée sur la clé, réseau...).
  Future<String?> reverseGeocode(
    LatLng position, {
    String language = 'fr',
  }) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/geocode/json',
      {
        'latlng': '${position.latitude},${position.longitude}',
        'key': apiKey,
        'language': language,
      },
    );

    final json = await _getJson(uri);
    final status = json['status'] as String?;
    if (status == 'ZERO_RESULTS') return null;
    _throwIfNotOk(json, status);

    final results = (json['results'] as List?) ?? const [];
    if (results.isEmpty) return null;
    // Le premier résultat « plus code » est peu lisible : on préfère une adresse.
    for (final r in results) {
      final types = (r['types'] as List?)?.cast<String>() ?? const [];
      if (types.contains('plus_code')) continue;
      final address = r['formatted_address'] as String?;
      if (address != null && address.isNotEmpty) return address;
    }
    return results.first['formatted_address'] as String?;
  }

  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    try {
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode != 200) {
        throw PlacesException('Erreur réseau (${res.statusCode}).');
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    } on PlacesException {
      rethrow;
    } catch (_) {
      throw const PlacesException('Connexion impossible. Vérifiez votre réseau.');
    }
  }

  /// L'API legacy répond HTTP 200 même en cas d'erreur : il faut lire `status`.
  void _throwIfNotOk(Map<String, dynamic> json, String? status) {
    if (status == 'OK') return;
    final message = json['error_message'] as String?;
    throw PlacesException(message ?? 'Erreur Places : ${status ?? 'inconnue'}.');
  }

  void dispose() => _client.close();
}
