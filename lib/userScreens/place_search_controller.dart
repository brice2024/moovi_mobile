import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'places_service.dart';

enum SearchField { origin, destination }

/// Logique de recherche de lieux, indépendante de l'UI.
/// Un seul contrôleur pour plusieurs champs : il suit le champ actif et
/// expose une seule liste de suggestions.
class PlaceSearchController extends ChangeNotifier {
  PlaceSearchController(
    this._service, {
    this.minChars = 3,
    this.debounce = const Duration(milliseconds: 350),
    this.country,
    this.biasLocation,
  }) {
    originFocus.addListener(() {
      if (originFocus.hasFocus) setActive(SearchField.origin);
    });
    destinationFocus.addListener(() {
      if (destinationFocus.hasFocus) setActive(SearchField.destination);
    });
  }

  // --- Champs : à brancher sur VOS TextField personnalisés --------------------
  final TextEditingController originText = TextEditingController();
  final TextEditingController destinationText = TextEditingController();
  final FocusNode originFocus = FocusNode();
  final FocusNode destinationFocus = FocusNode();

  TextEditingController textFor(SearchField f) =>
      f == SearchField.origin ? originText : destinationText;

  FocusNode focusFor(SearchField f) =>
      f == SearchField.origin ? originFocus : destinationFocus;

  /// Texte (sans espaces) du champ actuellement actif.
  String get activeText => textFor(_active).text.trim();

  final PlacesService _service;
  final int minChars;
  final Duration debounce;
  final String? country;

  /// À mettre à jour avec la position de l'utilisateur pour favoriser
  /// les résultats proches.
  LatLng? biasLocation;

  // --- État exposé à l'UI ----------------------------------------------------
  SearchField _active = SearchField.destination;
  List<PlaceSuggestion> _suggestions = const [];
  bool _loading = false;
  String? _error;
  LatLng? _origin;
  LatLng? _destination;

  SearchField get active => _active;
  List<PlaceSuggestion> get suggestions => _suggestions;
  bool get isLoading => _loading;
  String? get error => _error;
  LatLng? get origin => _origin;
  LatLng? get destination => _destination;

  // --- Interne ---------------------------------------------------------------
  Timer? _timer;
  int _requestId = 0; // sert à ignorer les réponses obsolètes
  String _sessionToken = _newToken();
  bool _disposed = false;

  static String _newToken() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // --- API publique ----------------------------------------------------------

  /// À appeler quand un champ prend le focus.
  void setActive(SearchField field) {
    if (_active == field) return;
    _active = field;
    _resetSuggestions();
    _notify();
  }

  /// À appeler depuis le `onChanged` de vos TextField (saisie utilisateur).
  /// Un `controller.text = ...` fait par le code ne déclenche pas onChanged,
  /// donc remplir le champ après une sélection n'invalide pas le lieu choisi.
  void onQueryChanged(SearchField field, String text) {
    _active = field;

    // Modifier le texte invalide le lieu précédemment choisi pour ce champ.
    if (field == SearchField.origin) {
      _origin = null;
    } else {
      _destination = null;
    }

    _timer?.cancel();
    final query = text.trim();

    if (query.length < minChars) {
      _resetSuggestions();
      _notify();
      return;
    }

    _loading = true;
    _error = null;
    _notify();
    _timer = Timer(debounce, () => _fetch(query));
  }

  /// À appeler au tap sur une suggestion. Retourne les coordonnées
  /// (ou null en cas d'erreur, visible via [error]).
  Future<LatLng?> select(PlaceSuggestion suggestion) async {
    final field = _active;
    _timer?.cancel();
    _requestId++; // annule toute recherche en cours
    _suggestions = const [];
    _loading = true;
    _error = null;
    _notify();

    try {
      final latLng = await _service.details(
        suggestion.placeId,
        sessionToken: _sessionToken,
      );
      if (field == SearchField.origin) {
        _origin = latLng;
      } else {
        _destination = latLng;
      }
      return latLng;
    } catch (e) {
      _error = _messageFor(e);
      return null;
    } finally {
      // L'appel Details clôt la session de facturation : on en ouvre une autre.
      _sessionToken = _newToken();
      _loading = false;
      _notify();
    }
  }

  /// Tap sur une suggestion : remplit le champ actif, ferme le clavier,
  /// puis récupère les coordonnées. Retourne null en cas d'erreur.
  Future<LatLng?> pickSuggestion(PlaceSuggestion suggestion) {
    _fill(_active, suggestion.description);
    return select(suggestion);
  }

  /// Tap sur un lieu dont vous connaissez déjà les coordonnées (récent, favori).
  void pickKnownPlace(String label, LatLng latLng) {
    final field = _active;
    _fill(field, label);
    setPlace(field, latLng);
  }

  void _fill(SearchField field, String text) {
    // Modifier `.value` par code ne déclenche pas le onChanged du TextField,
    // donc le lieu choisi n'est pas invalidé.
    textFor(field).value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    focusFor(field).unfocus();
  }

  /// Vide un champ (bouton « effacer »).
  void clear(SearchField field) {
    textFor(field).clear();
    if (field == SearchField.origin) {
      _origin = null;
    } else {
      _destination = null;
    }
    if (_active == field) _resetSuggestions();
    _notify();
  }

  /// Définit directement un lieu dont on connaît déjà les coordonnées
  /// (lieu récent, point choisi sur la carte...).
  void setPlace(SearchField field, LatLng latLng) {
    if (field == SearchField.origin) {
      _origin = latLng;
    } else {
      _destination = latLng;
    }
    _resetSuggestions();
    _notify();
  }

  /// Ferme la liste sans toucher aux lieux choisis (tap sur la carte, etc.).
  void dismissSuggestions() {
    _resetSuggestions();
    _notify();
  }

  // --- Implémentation --------------------------------------------------------

  Future<void> _fetch(String query) async {
    final id = ++_requestId;
    try {
      final results = await _service.autocomplete(
        query,
        sessionToken: _sessionToken,
        country: country,
        bias: biasLocation,
      );
      if (id != _requestId) return; // une requête plus récente a pris le relais
      _suggestions = results;
      _error = null;
    } catch (e) {
      if (id != _requestId) return;
      _suggestions = const [];
      _error = _messageFor(e);
    }
    _loading = false;
    _notify();
  }

  void _resetSuggestions() {
    _timer?.cancel();
    _requestId++;
    _suggestions = const [];
    _loading = false;
    _error = null;
  }

  String _messageFor(Object e) =>
      e is PlacesException ? e.message : 'Une erreur est survenue.';

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _service.dispose();
    originText.dispose();
    destinationText.dispose();
    originFocus.dispose();
    destinationFocus.dispose();
    super.dispose();
  }
}
