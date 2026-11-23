import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../functions.dart';
import '../services/driver_service.dart';
import '../services/itinéraire/DirectionsService.dart';
import 'place_search_controller.dart';
import 'places_service.dart';
import 'ride/home_widgets.dart';
import 'ride/ride_style.dart';
import 'ride/ride_tracking_page.dart';
import 'ride/saved_places_service.dart';
import 'ride/schedule_picker.dart';
import 'ride/search_panel.dart';
import 'ride/vehicle_markers.dart';
import 'widgets/driverOffersSheet.dart';
import 'widgets/rideSheetColors.dart';

/// Étapes de l'écran d'accueil client.
enum _Stage {
  /// Carte + pilule « Où allez-vous ? » (maquette 9).
  home,

  /// Recherche départ / destination (maquette 10).
  search,

  /// Choix d'un point sur la carte (viseur central).
  pickOnMap,

  /// « Votre offre » : type de véhicule et prix (maquette 11).
  quote,

  /// Propositions des chauffeurs (maquette 12).
  offers,
}

/// Position d'un chauffeur disponible affiché sur la carte.
class _DriverPin {
  const _DriverPin(this.id, this.position, this.kind, this.city);
  final String id;
  final LatLng position;
  final VehicleKind kind;
  final String city;
}

/// Écran principal du client : carte, recherche, offre, propositions.
/// Le suivi de course (maquettes 13-15) et la fin de course (maquette 16)
/// sont des pages poussées par-dessus ([RideTrackingPage]).
class MapPage extends StatefulWidget {
  /// Appelé par le bouton profil (en haut à droite) : bascule sur l'onglet Profil.
  final VoidCallback? onProfileTap;

  const MapPage({super.key, this.onProfileTap});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const _placesApiKey = "AIzaSyBs6DVjYiLlKjtJHqRwO6qTKouJ7o0f5F4";

  static const _originLabel = 'Ma position';

  final Completer<GoogleMapController> _mapController = Completer();

  // Gère les deux champs (texte + focus), les suggestions et les lieux choisis.
  late final PlaceSearchController _search = PlaceSearchController(
    PlacesService(_placesApiKey),
    country: 'ga',
  );

  _Stage _stage = _Stage.home;

  LatLng? _currentPosition;
  String? _error;

  // Derniers lieux affichés sur la carte (pour ne réagir qu'aux vrais changements).
  LatLng? _shownOrigin;
  LatLng? _shownDestination;

  // Distance et durée du trajet départ -> destination.
  int distance = 0;
  String temps = '';

  // Course planifiée (null = maintenant).
  DateTime? _scheduledAt;

  // Course en cours de création / recherche de chauffeur.
  String? _currentRideId;
  String _currentRideType = 'voiture';
  Stream<QuerySnapshot<Map<String, dynamic>>>? _offersStream;
  String? _selectingOfferId;

  // Choix d'un point sur la carte.
  SearchField _pickField = SearchField.destination;
  LatLng? _pickCenter;
  String _pickLabel = '';
  bool _pickLoading = false;
  int _pickRequest = 0;

  // Tracé de l'itinéraire.
  final DirectionsService directionsService = DirectionsService();
  Set<Polyline> polylines = {};

  // Chauffeurs disponibles (test + réels), par collection.
  final Map<String, List<_DriverPin>> _driverPins = {};
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _driverSubs = [];

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _search.originFocus.addListener(_onOriginFocusChanged);
    VehicleMarkerIcons.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    _initLocation();
    _listenToDrivers('test_drivers');
    _listenToDrivers('drivers');
  }

  @override
  void dispose() {
    _search.originFocus.removeListener(_onOriginFocusChanged);
    _search.removeListener(_onSearchChanged);
    _search.dispose(); // libère aussi les champs et les focus
    for (final s in _driverSubs) {
      s.cancel();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Localisation
  // ---------------------------------------------------------------------------
  Future<void> _initLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'Le service de localisation est désactivé, veuillez l\'activer.';
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw 'Permission de localisation refusée.';
      }

      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;

      final here = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _currentPosition = here;
        _error = null;
      });

      // Les suggestions proches de l'utilisateur remontent en premier,
      // et le départ est la position actuelle tant qu'il ne le change pas.
      _search.biasLocation = here;
      _useCurrentLocationAsOrigin();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  /// Remplit le champ de départ avec la position actuelle.
  void _useCurrentLocationAsOrigin() {
    final here = _currentPosition;
    if (here == null) return;

    // Écrire par code ne déclenche pas onChanged : le lieu reste valide.
    _search.originText.value = const TextEditingValue(
      text: _originLabel,
      selection: TextSelection.collapsed(offset: _originLabel.length),
    );
    _search.setPlace(SearchField.origin, here);
  }

  void _onOriginFocusChanged() {
    final ctrl = _search.originText;
    if (_search.originFocus.hasFocus) {
      // Tout sélectionner : l'utilisateur peut taper directement pour remplacer.
      ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    } else if (ctrl.text.trim().isEmpty) {
      // Champ laissé vide : on revient à la position actuelle.
      _useCurrentLocationAsOrigin();
    }
  }

  // ---------------------------------------------------------------------------
  // Chauffeurs disponibles sur la carte
  // ---------------------------------------------------------------------------
  void _listenToDrivers(String collection) {
    final sub = FirebaseFirestore.instance
        .collection(collection)
        .where('isAvailable', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      final pins = <_DriverPin>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final location = data['location'];
        if (location is! GeoPoint) continue;
        pins.add(_DriverPin(
          '$collection/${doc.id}',
          LatLng(location.latitude, location.longitude),
          vehicleKindFromData(doc.id, data),
          data['city']?.toString() ?? '',
        ));
      }
      if (!mounted) return;
      setState(() => _driverPins[collection] = pins);
    }, onError: (error) {
      debugPrint('Erreur chargement chauffeurs ($collection) : $error');
    });
    _driverSubs.add(sub);
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    for (final pin in _driverPins.values.expand((p) => p)) {
      markers.add(Marker(
        markerId: MarkerId(pin.id),
        position: pin.position,
        icon: VehicleMarkerIcons.forKind(pin.kind),
        anchor: const Offset(0.5, 0.5),
        flat: true,
        infoWindow: InfoWindow(
          title: pin.kind == VehicleKind.moto ? 'Moto disponible' : 'Voiture disponible',
          snippet: pin.city,
        ),
      ));
    }

    if (_stage == _Stage.pickOnMap) return markers;

    final origin = _shownOrigin;
    final destination = _shownDestination;

    if (origin != null && origin != _currentPosition) {
      markers.add(Marker(
        markerId: const MarkerId('origin'),
        position: origin,
        icon: VehicleMarkerIcons.pickup,
        anchor: const Offset(0.5, 0.5),
        infoWindow: InfoWindow(title: _search.originText.text),
      ));
    }

    if (destination != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: destination,
        icon: VehicleMarkerIcons.destination,
        anchor: const Offset(0.5, 0.5),
        infoWindow: InfoWindow(title: _search.destinationText.text),
      ));
    }

    return markers;
  }

  // ---------------------------------------------------------------------------
  // Recherche : réaction aux changements du contrôleur
  // ---------------------------------------------------------------------------
  Future<void> _onSearchChanged() async {
    final origin = _search.origin;
    final destination = _search.destination;
    if (origin == _shownOrigin && destination == _shownDestination) return;

    _shownOrigin = origin;
    _shownDestination = destination;

    if (!mounted) return;
    setState(() {
      if (destination == null || origin == null) {
        polylines = {};
        distance = 0;
        temps = '';
      }
    });
    if (_stage != _Stage.pickOnMap) _updateCamera();

    if (origin != null && destination != null) {
      await tracerItineraire();
    }
  }

  Future<void> tracerItineraire() async {
    final origin = _shownOrigin;
    final destination = _shownDestination;
    if (origin == null || destination == null) return;

    try {
      final info = await directionsService.getRoute(origin, destination);
      if (!mounted) return;
      // Le trajet a pu changer pendant le calcul.
      if (origin != _shownOrigin || destination != _shownDestination) return;

      setState(() {
        polylines = {
          Polyline(
            polylineId: const PolylineId("bordure"),
            points: info.points,
            color: AppRouteColors.border,
            width: 9,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
            zIndex: 0,
          ),
          Polyline(
            polylineId: const PolylineId("trajet"),
            points: info.points,
            color: RideColors.orange,
            width: 5,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
            zIndex: 1,
          ),
        };
        distance = info.distanceMeters;
        temps = info.durationText;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Impossible de tracer le trajet : $e")),
      );
    }
  }

  String get _distanceText =>
      distance > 0 ? '${(distance / 1000).toStringAsFixed(1).replaceAll('.', ',')} km' : '';

  String get _originAddress {
    final t = _search.originText.text.trim();
    return t.isNotEmpty ? t : 'Point de départ';
  }

  String get _destinationAddress {
    final t = _search.destinationText.text.trim();
    return t.isNotEmpty ? t : 'Destination';
  }

  // ---------------------------------------------------------------------------
  // Navigation entre les étapes
  // ---------------------------------------------------------------------------
  void _openSearch() {
    setState(() => _stage = _Stage.search);
    if (_search.destination == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _stage == _Stage.search) {
          _search.destinationFocus.requestFocus();
        }
      });
    }
  }

  void _closeSearch() {
    FocusScope.of(context).unfocus();
    _search.dismissSuggestions();
    setState(() => _stage = _Stage.home);
  }

  /// Passe à « Votre offre » dès que départ et destination sont connus.
  void _maybeGoToQuote() {
    if (_search.origin == null || _search.destination == null) return;
    FocusScope.of(context).unfocus();

    final at = _scheduledAt;
    if (at != null && at.isBefore(DateTime.now().add(kScheduleMinDelay))) {
      setState(() => _scheduledAt = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'L\'heure planifiée est trop proche : la course est repassée en « Maintenant ».',
        ),
      ));
    }
    setState(() => _stage = _Stage.quote);
    _updateCamera();
  }

  Future<void> _onSuggestionTap(PlaceSuggestion s) async {
    // Remplit le champ actif, ferme le clavier, récupère les coordonnées.
    final latLng = await _search.pickSuggestion(s);
    if (latLng == null || !mounted) return;
    _maybeGoToQuote();
  }

  void _onKnownPlaceTap(KnownPlace place) {
    // Un lieu enregistré / récent va dans le champ actif (destination par défaut).
    _search.fillPlace(_search.active, place.fieldText, place.position);
    _maybeGoToQuote();
  }

  void _onClear(SearchField field) {
    _search.clear(field);
    _search.focusFor(field).requestFocus();
  }

  Future<void> _onScheduleTap() async {
    final choice = await showSchedulePicker(context, initial: _scheduledAt);
    if (choice == null || !mounted) return;
    setState(() => _scheduledAt = choice.at);
  }

  // ---------------------------------------------------------------------------
  // Choix d'un point sur la carte
  // ---------------------------------------------------------------------------
  Future<void> _startPickOnMap(SearchField field) async {
    FocusScope.of(context).unfocus();
    _search.dismissSuggestions();
    final start = (field == SearchField.origin ? _search.origin : _search.destination) ??
        _currentPosition;
    setState(() {
      _pickField = field;
      _stage = _Stage.pickOnMap;
      _pickCenter = start;
      _pickLabel = '';
    });
    if (start != null) {
      final c = await _mapController.future;
      await c.animateCamera(CameraUpdate.newLatLngZoom(start, 17));
      _resolvePickAddress();
    }
  }

  void _onCameraMove(CameraPosition position) {
    if (_stage != _Stage.pickOnMap) return;
    _pickCenter = position.target;
  }

  void _onCameraIdle() {
    if (_stage != _Stage.pickOnMap) return;
    _resolvePickAddress();
  }

  Future<void> _resolvePickAddress() async {
    final center = _pickCenter;
    if (center == null) return;
    final id = ++_pickRequest;
    setState(() => _pickLoading = true);
    final address = await _search.addressFor(center);
    if (!mounted || id != _pickRequest) return;
    setState(() {
      _pickLoading = false;
      _pickLabel = address ?? _coordinatesLabel(center);
    });
  }

  String _coordinatesLabel(LatLng p) =>
      'Point choisi (${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)})';

  void _confirmPick() {
    final center = _pickCenter;
    if (center == null) return;
    final label = _pickLabel.isNotEmpty ? _pickLabel : _coordinatesLabel(center);
    _search.fillPlace(_pickField, label, center);
    setState(() => _stage = _Stage.search);
    _updateCamera();
    _maybeGoToQuote();
  }

  void _cancelPick() {
    _pickRequest++;
    setState(() {
      _stage = _Stage.search;
      _pickLoading = false;
    });
    _updateCamera();
  }

  // ---------------------------------------------------------------------------
  // Course : création, offres, acceptation
  // ---------------------------------------------------------------------------
  void _onRideCreated(RideOption option, double price, String? rideId) {
    if (rideId == null) return;
    setState(() {
      _currentRideId = rideId;
      _currentRideType = option.id;
      _offersStream = DriverService.instance.streamRideOffers(rideId);
      _stage = _Stage.offers;
    });
  }

  Future<void> _cancelSearch() async {
    final rideId = _currentRideId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la recherche ?'),
        content: const Text(
          'Votre demande sera retirée et les chauffeurs ne pourront plus vous faire d\'offre.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Annuler la course'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (rideId != null) {
      cancelRide(rideId).catchError((e) => debugPrint('Annulation course : $e'));
    }
    setState(() {
      _currentRideId = null;
      _offersStream = null;
      _stage = _Stage.quote;
    });
  }

  Future<void> _acceptDriver(DriverOffer offer) async {
    final rideId = _currentRideId;
    final origin = _shownOrigin;
    final destination = _shownDestination;
    if (rideId == null || origin == null || destination == null) return;
    if (_selectingOfferId != null) return;
    setState(() => _selectingOfferId = offer.id);

    try {
      await DriverService.instance.acceptDriverOffer(
        rideId: rideId,
        driverId: offer.id,
        agreedPrice: offer.price,
        driverName: offer.name,
        car: offer.car,
        plate: offer.plate,
        photoUrl: offer.photoUrl,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _selectingOfferId = null); // réactive « Choisir »
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Impossible de choisir ce chauffeur : $e'),
      ));
      return;
    }
    if (!mounted) return;

    // Suivi de la course (statuts accepted → driver_arrived → in_progress
    // → completed / cancelled), puis fin de course.
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RideTrackingPage(
        rideId: rideId,
        pickup: origin,
        destination: destination,
        from: _originAddress,
        to: _destinationAddress,
        offer: offer,
        rideType: _currentRideType,
        distanceText: _distanceText,
        durationText: temps,
      ),
    ));
    if (mounted) _resetAfterRide();
  }

  /// Retour à l'accueil après une course (terminée ou annulée).
  void _resetAfterRide() {
    _search.clear(SearchField.destination);
    _search.dismissSuggestions();
    setState(() {
      _stage = _Stage.home;
      _currentRideId = null;
      _offersStream = null;
      _selectingOfferId = null;
      _scheduledAt = null;
      polylines = {};
      distance = 0;
      temps = '';
    });
    _useCurrentLocationAsOrigin();
    _updateCamera();
  }

  /// Bouton retour système : remonte d'une étape.
  void _onSystemBack() {
    switch (_stage) {
      case _Stage.home:
        break;
      case _Stage.search:
        _closeSearch();
      case _Stage.pickOnMap:
        _cancelPick();
      case _Stage.quote:
        setState(() => _stage = _Stage.search);
      case _Stage.offers:
        _cancelSearch();
    }
  }

  // ---------------------------------------------------------------------------
  // Caméra
  // ---------------------------------------------------------------------------
  Future<void> _updateCamera() async {
    final controller = await _mapController.future;
    final from = _shownOrigin ?? _currentPosition;
    final to = _shownDestination;

    if (to == null) {
      if (from != null) {
        await controller.animateCamera(CameraUpdate.newLatLngZoom(from, 15.5));
      }
      return;
    }
    if (from == null) {
      await controller.animateCamera(CameraUpdate.newLatLngZoom(to, 16));
      return;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(
        from.latitude < to.latitude ? from.latitude : to.latitude,
        from.longitude < to.longitude ? from.longitude : to.longitude,
      ),
      northeast: LatLng(
        from.latitude > to.latitude ? from.latitude : to.latitude,
        from.longitude > to.longitude ? from.longitude : to.longitude,
      ),
    );
    try {
      await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  /// Marge basse : la barre d'onglets flotte au-dessus de la carte.
  double _navInset(BuildContext context) =>
      MediaQuery.of(context).padding.bottom + 100;

  @override
  Widget build(BuildContext context) {
    final position = _currentPosition;

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _initLocation,
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (position == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final media = MediaQuery.of(context);
    final top = media.padding.top;
    final navInset = _navInset(context);

    return PopScope(
      canPop: _stage == _Stage.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onSystemBack();
      },
      child: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: position, zoom: 15.5),
            style: kMooviDarkMapStyle,
            onMapCreated: (c) {
              if (!_mapController.isCompleted) _mapController.complete(c);
            },
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            polylines: _stage == _Stage.pickOnMap ? const {} : polylines,
            markers: _buildMarkers(),
            padding: EdgeInsets.only(top: top + 70, bottom: navInset),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            mapType: MapType.normal,
            buildingsEnabled: false,
            indoorViewEnabled: false,
            trafficEnabled: false,
            compassEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            zoomGesturesEnabled: true,
            scrollGesturesEnabled: true,
            onTap: (_) {
              if (_stage == _Stage.search) {
                _closeSearch();
              } else {
                FocusScope.of(context).unfocus();
                _search.dismissSuggestions();
              }
            },
          ),

          // Petit logo en haut (maquettes 9 à 12)
          if (_stage != _Stage.pickOnMap)
            Positioned(
              top: top + 2,
              left: 0,
              right: 0,
              child: const IgnorePointer(
                child: Text(
                  'MOOVI',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),

          if (_stage == _Stage.home)
            Positioned(
              top: top + 24,
              left: 16,
              right: 16,
              child: HomeSearchBar(
                onSearchTap: _openSearch,
                onScheduleTap: _onScheduleTap,
                scheduleLabel: _scheduledAt == null
                    ? 'Maintenant'
                    : formatScheduleChip(_scheduledAt!),
                onProfileTap: widget.onProfileTap,
              ),
            ),

          if (_stage == _Stage.search)
            Positioned(
              top: top + 30,
              left: 20,
              right: 20,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.max(
                    220.0,
                    media.size.height - top - 30 - math.max(navInset, media.viewInsets.bottom + 16),
                  ),
                ),
                child: RideSearchPanel(
                  search: _search,
                  onSuggestionTap: _onSuggestionTap,
                  onKnownPlaceTap: _onKnownPlaceTap,
                  onPickOnMap: _startPickOnMap,
                  onClear: _onClear,
                ),
              ),
            ),

          if (_stage == _Stage.pickOnMap)
            Positioned.fill(
              child: MapPickOverlay(
                title: _pickField == SearchField.origin
                    ? 'Point de départ'
                    : 'Destination',
                addressLabel: _pickLabel.isEmpty
                    ? 'Déplacez la carte pour placer le repère'
                    : _pickLabel,
                loading: _pickLoading,
                onConfirm: _confirmPick,
                onCancel: _cancelPick,
                bottomInset: navInset,
              ),
            ),

          if (_stage == _Stage.quote &&
              _shownOrigin != null &&
              _shownDestination != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: navInset - 10,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.max(300.0, media.size.height - top - 30 - navInset),
                ),
                child: RideSelectionSheet(
                  departureLat: _shownOrigin!.latitude,
                  departureLng: _shownOrigin!.longitude,
                  destinationLat: _shownDestination!.latitude,
                  destinationLng: _shownDestination!.longitude,
                  departureAddress: _originAddress,
                  destinationAddress: _destinationAddress,
                  distanceText: _distanceText,
                  durationText: temps,
                  scheduledAt: _scheduledAt,
                  onBack: () => setState(() => _stage = _Stage.search),
                  onConfirm: _onRideCreated,
                ),
              ),
            ),

          // Offres des chauffeurs en direct (Firestore)
          if (_stage == _Stage.offers && _offersStream != null)
            Positioned(
              top: top + 30,
              left: 20,
              right: 20,
              bottom: 0,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _offersStream,
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ?? const [];
                  final offers = [
                    for (final d in docs)
                      if (d.data()['status'] != 'rejected')
                        DriverOffer.fromMap(d.id, d.data()),
                  ];
                  return DriverOffersSheet(
                    key: ValueKey(_currentRideId),
                    offers: offers,
                    onSelect: _acceptDriver,
                    onBack: _cancelSearch,
                    from: _originAddress,
                    to: _destinationAddress,
                    durationText: temps,
                    distanceText: _distanceText,
                    selectingId: _selectingOfferId,
                    scheduledLabel: _scheduledAt == null
                        ? null
                        : 'Course prévue le ${formatDayMonthHour(_scheduledAt!)}',
                    bottomPadding: navInset + 10,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Couleur de la bordure du tracé (lisible sur la carte sombre).
class AppRouteColors {
  AppRouteColors._();
  static const Color border = Color(0xFF7A3E05);
}
