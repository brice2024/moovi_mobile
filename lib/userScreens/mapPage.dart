import 'dart:async';
import 'package:dotted_line/dotted_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:moovi/theme/app_colors.dart';
import 'package:moovi/userScreens/widgets/driverOffersSheet.dart';
import 'package:moovi/userScreens/widgets/rideSheetColors.dart';
import '../services/api_client.dart';
import '../services/itinéraire/DirectionsService.dart';
import '../services/driver_service.dart';
import '../services/contact_service.dart';
import '../widgets/mobile_money_payment_sheet.dart';
import '../widgets/ride_chat_page.dart';
import 'dataService.dart';
import 'place_search_controller.dart';
import 'places_service.dart';

/// Page d'affichage de la carte : Google Map + champs départ / destination
/// avec suggestions gérées par [PlaceSearchController].
///
/// Toutes les données transitent par l'API Moovi : recherche de lieux et
/// itinéraires (proxy Google), chauffeurs à proximité, création de course,
/// offres, acceptation, suivi et paiement.
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const _originLabel = 'Ma position';
  static const _fieldHeight = 40.00;
  static const _fieldGap = 10.0;

  //Style de la map
  String? mapStyle;

  Future<void> chargerStyle() async {
    final style = await rootBundle.loadString(
      'assets/map_style.json',
    );

    if (!mounted) return;

    setState(() {
      mapStyle = style;
    });
  }

  final Completer<GoogleMapController> _mapController = Completer();

  // Gère les deux champs (texte + focus), les suggestions et les lieux choisis.
  // Les requêtes Google Places passent par l'API (aucune clé dans l'app).
  late final PlaceSearchController _search = PlaceSearchController(
    PlacesService(),
    country: 'ga',
  );

  LatLng? _currentPosition;

  /// Libreville : centre utilisé tant que le GPS n'a pas de position.
  static const _defaultCenter = LatLng(0.4162, 9.4673);

  /// Position approximative ou absente (message affiché sur la carte).
  String? _locationWarning;
  StreamSubscription<Position>? _positionSub;
  String? _error;

  // Derniers lieux affichés sur la carte (pour ne réagir qu'aux vrais changements).
  LatLng? _shownOrigin;
  LatLng? _shownDestination;

  //distance et temps du trajet
  int distance = 0;
  String temps = '';
  RouteInfo? _route;

  bool _showOffers = false;
  String? _currentRideId;
  DriverOffer? _acceptedOffer;
  String? _driverPhone;
  int? _driverEtaMinutes;
  String? _rideStatus;
  LatLng? _assignedDriverPosition;
  bool _paymentSheetOpen = false;
  BuildContext? _completedSheetCtx;

  /// Le passager a choisi les espèces (ou fermé le paiement) : on attend la
  /// confirmation du chauffeur sans rouvrir la feuille en boucle.
  String? _awaitingDriverConfirmation;
  Map<String, dynamic>? _lastRideData;
  bool _rideSheetOpen = false;
  bool _streamErrorShown = false;
  StreamSubscription<Map<String, dynamic>>? _currentRideSub;
  Stream<List<Map<String, dynamic>>>? _offersStream;

  //tracer les itinéraires
  final DirectionsService directionsService = DirectionsService();
  Set<Polyline> polylines = {};
  int animationVersion = 0;

  Future<void> tracerItineraire() async {
    if (_shownOrigin == null || _shownDestination == null) {
      return;
    }

    try {
      final info = await directionsService.getRoute(
        _shownOrigin!,
        _shownDestination!,
      );

      if (!mounted) return;

      setState(() {
        _route = info;
        polylines = {
          Polyline(
              polylineId: const PolylineId("bordure"),
              points: info.points,
              color: AppColors.primaryDark,
              width: 11,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
              zIndex: 0),
          Polyline(
              polylineId: const PolylineId("trajet"),
              points: info.points,
              color: AppColors.primary,
              width: 7,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
              zIndex: 1),
        };
        distance = info.distanceMeters;
        temps = info.durationText;
      });
    } catch (e) {
      if (!mounted) return;
      _route = null;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Impossible de tracer le trajet : ${errorMessage(e)}"),
        ),
      );
    }
  }

  Future<void> _loadCarIcon() async {
    final icon = await BitmapDescriptor.asset(
      const ImageConfiguration(
        size: Size(25, 25),
      ),
      'assets/icon/car4.png',
      width: 25,
      height: 25,
    );

    if (!mounted) return;

    setState(() {
      _carIcon = icon;

      // Actualiser les marqueurs existants
      _driverMarkers = _driverMarkers.map((marker) {
        return marker.copyWith(
          iconParam: icon,
        );
      }).toSet();
    });
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _search.originFocus.addListener(_onOriginFocusChanged);
    _loadCarIcon();
    _initLocation();
    chargerStyle();
    _listenToDrivers();
    _resumeActiveRide();
  }

  @override
  void dispose() {
    _search.originFocus.removeListener(_onOriginFocusChanged);
    _search.removeListener(_onSearchChanged);
    _search.dispose(); // libère aussi les champs et les focus
    _driversSubscription?.cancel();
    _currentRideSub?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Localisation
  // ---------------------------------------------------------------------------
  /// Position de départ sans jamais bloquer l'écran : dernière position
  /// connue, puis position GPS avec délai maximum, sinon Libreville. Le GPS
  /// continue ensuite de mettre la carte à jour dès qu'il capte.
  Future<void> _initLocation() async {
    String? problem;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        problem = 'Localisation désactivée : activez-la pour partir de votre position.';
      } else {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          problem = 'Permission de localisation refusée : choisissez votre départ à la main.';
        }
      }
    } catch (e) {
      problem = 'Localisation indisponible ($e).';
    }

    if (problem != null) {
      _applyPosition(null, warning: problem);
      return;
    }

    // 1. Dernière position connue : affichage immédiat.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        _applyPosition(LatLng(last.latitude, last.longitude),
            warning: 'Position approximative, recherche du GPS…');
      }
    } catch (_) {}

    // 2. Position précise, 12 s au plus (sans signal, l'écran ne doit pas tourner indéfiniment).
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      _applyPosition(LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      if (_currentPosition == null) {
        _applyPosition(null,
            warning: 'GPS sans signal : carte centrée sur Libreville. Votre position s\'affichera dès qu\'il capte.');
      }
    }

    // 3. Suivi : la position se met à jour dès que le GPS capte.
    _positionSub ??= Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
      ),
    ).listen(
      (pos) => _applyPosition(LatLng(pos.latitude, pos.longitude)),
      onError: (_) {},
    );
  }

  void _applyPosition(LatLng? here, {String? warning}) {
    if (!mounted) return;
    final hadPrecise = _currentPosition != null && _locationWarning == null;
    if (hadPrecise && here == null) return;
    final first = _currentPosition == null || _locationWarning != null;
    setState(() {
      _currentPosition = here ?? _currentPosition ?? _defaultCenter;
      _locationWarning = warning;
      _error = null;
    });
    if (here == null) return;
    // Les suggestions proches de l'utilisateur remontent en premier, et le
    // départ est la position actuelle tant qu'il ne le change pas.
    _search.biasLocation = here;
    final originIsMe = _search.originText.text == _originLabel ||
        _search.originText.text.trim().isEmpty;
    if (first || originIsMe) _useCurrentLocationAsOrigin();
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
      ctrl.selection =
          TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    } else if (ctrl.text.trim().isEmpty) {
      // Champ laissé vide : on revient à la position actuelle.
      _useCurrentLocationAsOrigin();
    }
  }

  // ---------------------------------------------------------------------------
  // Réaction aux changements du contrôleur de recherche
  // ---------------------------------------------------------------------------
  Future<void> _onSearchChanged() async {
    final origin = _search.origin;
    final destination = _search.destination;
    if (origin == _shownOrigin && destination == _shownDestination) return;

    _shownOrigin = origin;
    _shownDestination = destination;

    if (!mounted) return;
    setState(() {}); // les marqueurs sont recalculés dans build()
    _updateCamera();

    if (_shownOrigin != null && _shownDestination != null) {
      await tracerItineraire();
    }

    if (_shownDestination == null) {
      polylines.clear();
      _route = null;
    }

    // Pas de nouvelle réservation pendant une course en cours.
    if (_currentRideId != null) return;

    if (_shownOrigin != null && _shownDestination != null) {
      await Future.delayed(
        const Duration(milliseconds: 1500),
      );
      if (!mounted || _currentRideId != null) return;
      if (_search.destination != destination) return; // destination changée entre-temps
      _openRideSelection();
    }
  }

  /// Ouvre (une seule fois) la feuille de choix du véhicule et du prix.
  Future<void> _openRideSelection() async {
    if (_rideSheetOpen || _currentRideId != null) return;
    if (_shownOrigin == null || _shownDestination == null) return;
    _rideSheetOpen = true;
    if (mounted) setState(() {});
    try {
      final route = _route;
      await showRideSelectionSheet(
        context,
        departureLat: _shownOrigin!.latitude,
        departureLng: _shownOrigin!.longitude,
        destinationLat: _shownDestination!.latitude,
        destinationLng: _shownDestination!.longitude,
        departureAddress: _search.originText.text.trim().isNotEmpty
            ? _search.originText.text.trim()
            : 'Point de départ',
        destinationAddress: _search.destinationText.text.trim().isNotEmpty
            ? _search.destinationText.text.trim()
            : 'Destination',
        distanceText: route?.distanceText ?? '',
        durationText: temps,
        distanceMeters: route?.distanceMeters,
        durationSeconds: route?.duration.inSeconds,
        polyline: route?.encodedPolyline,
        recommendedPrices: {
          for (final e in route?.priceEstimates ?? const <PriceEstimate>[])
            e.rideType: e.recommendedPrice,
        },
        onConfirm: (option, price, rideId) {
          if (rideId == null) return;
          _startTrackingRide(rideId);
        },
      );
    } finally {
      _rideSheetOpen = false;
      if (mounted) setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // Course : recherche, offres, acceptation, suivi
  // ---------------------------------------------------------------------------

  /// Reprend la course en cours du passager (application relancée).
  Future<void> _resumeActiveRide() async {
    try {
      final ride = await DriverService.instance.getActiveRide(role: 'passenger');
      if (ride == null || !mounted) return;
      _startTrackingRide(ride['id'].toString(), initial: ride);
    } catch (_) {}
  }

  void _startTrackingRide(String rideId, {Map<String, dynamic>? initial}) {
    setState(() {
      _currentRideId = rideId;
      _showOffers = true;
      _acceptedOffer = null;
      _rideStatus = initial?['status']?.toString() ?? 'searching';
      _offersStream = DriverService.instance.streamRideOffers(rideId);
    });
    if (initial != null) _applyRideUpdate(initial);
    _listenToCurrentRide();
  }

  void _resetRide({String? message}) {
    _currentRideSub?.cancel();
    _currentRideSub = null;
    if (!mounted) return;
    setState(() {
      _showOffers = false;
      _acceptedOffer = null;
      _currentRideId = null;
      _rideStatus = null;
      _assignedDriverPosition = null;
      _offersStream = null;
      polylines.clear();
    });
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _acceptDriver(DriverOffer offer) async {
    if (_currentRideId == null) return;
    setState(() {
      _acceptedOffer = offer;
    });

    try {
      // Attribution atomique : l'API rejette les autres offres.
      final ride = await DriverService.instance.acceptDriverOffer(
        rideId: _currentRideId!,
        offerId: offer.id,
      );
      if (!mounted) return;
      _applyRideUpdate(ride);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _acceptedOffer = null;
        _offersStream = _currentRideId == null
            ? null
            : DriverService.instance.streamRideOffers(_currentRideId!);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage(e))),
      );
    }
  }

  Future<void> _cancelRide() async {
    final rideId = _currentRideId;
    if (rideId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Annuler la course ?'),
        content: Text(_acceptedOffer == null
            ? 'La recherche de chauffeur sera arrêtée.'
            : 'Votre chauffeur sera prévenu de l\'annulation.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Non'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await DriverService.instance.cancelRide(rideId, reason: 'Annulée par le passager');
      _resetRide(message: 'Course annulée.');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  void _listenToCurrentRide() {
    final rideId = _currentRideId;
    if (rideId == null) return;
    _currentRideSub?.cancel();
    _currentRideSub = DriverService.instance.streamRide(rideId).listen(
      _applyRideUpdate,
      onError: (e) {
        // Erreur persistante (accès refusé, course supprimée…) : on le dit
        // une fois au lieu de laisser l'écran figé.
        if (!mounted || _streamErrorShown) return;
        _streamErrorShown = true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Suivi de la course interrompu : ${errorMessage(e)}')));
      },
    );
  }

  /// Met à jour l'écran selon l'état de la course renvoyé par l'API.
  void _applyRideUpdate(Map<String, dynamic> data) {
    if (!mounted || data['id']?.toString() != _currentRideId) return;
    _lastRideData = data;
    _streamErrorShown = false;
    final status = data['status']?.toString();
    final isPaid = data['isPaid'] == true;

    final loc = data['driverLocation'];
    LatLng? driverPos;
    if (loc is Map && loc['latitude'] != null && loc['longitude'] != null) {
      driverPos = LatLng(asNum(loc['latitude'])!.toDouble(),
          asNum(loc['longitude'])!.toDouble());
    }

    final dep = data['departure'];
    int? eta;
    if (driverPos != null && dep is Map && dep['latitude'] != null) {
      eta = ContactService.etaMinutes(driverPos.latitude, driverPos.longitude,
          asNum(dep['latitude'])!.toDouble(), asNum(dep['longitude'])!.toDouble());
    }
    final lvlStr = data['driverLevel']?.toString().toLowerCase();
    final level = lvlStr == 'diamant'
        ? DriverLevel.diamant
        : lvlStr == 'platine'
            ? DriverLevel.platine
            : DriverLevel.or;

    setState(() {
      _rideStatus = status;
      _assignedDriverPosition = driverPos;
      _driverPhone = data['driverPhone']?.toString();
      _driverEtaMinutes = status == 'accepted' ? eta : null;
      if (status != 'searching' && data['driverId'] != null) {
        _acceptedOffer ??= DriverOffer(
          id: data['driverId'].toString(),
          name: data['driverName']?.toString() ?? 'Chauffeur',
          rating: asNum(data['driverRating'])?.toDouble() ?? 0,
          level: level,
          price: (asNum(data['finalPrice']) ?? 0).toInt(),
          arrivalMinutes: eta ?? 0,
          car: data['driverCar']?.toString() ?? 'Véhicule',
          plate: data['driverPlate']?.toString() ?? '',
          photoUrl: data['driverPhotoUrl']?.toString(),
        );
      }
    });

    switch (status) {
      case 'expired':
        _resetRide(
            message:
                'Aucun chauffeur n\'a répondu à temps. Vous pouvez relancer une course.');
        break;
      case 'cancelled':
        _resetRide(
            message: data['cancelledBy'] == 'driver'
                ? 'Votre chauffeur a annulé la course. Vous pouvez relancer une recherche.'
                : 'Course annulée.');
        break;
      case 'completed':
        if (isPaid) {
          _currentRideSub?.cancel();
          // Règlement confirmé (ex. espèces validées par le chauffeur).
          final sheetCtx = _completedSheetCtx;
          if (sheetCtx != null) {
            _completedSheetCtx = null;
            _paymentSheetOpen = false;
            Navigator.pop(sheetCtx);
          }
          if (_paymentSheetOpen) return;
          _onRideFinished(data);
        } else if (_awaitingDriverConfirmation != data['id']?.toString()) {
          _showCompletedSheet(data);
        }
        break;
    }
  }

  /// Fin de course : choix du règlement (espèces ou Mobile Money PawaPay).
  void _showCompletedSheet(Map<String, dynamic> data) {
    if (_paymentSheetOpen) return;
    _paymentSheetOpen = true;
    final rideId = data['id'].toString();
    final amount = (asNum(data['amountDue']) ?? asNum(data['finalPrice']) ?? 0).toInt();

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        _completedSheetCtx = sheetContext;
        return PopScope(
        canPop: false,
        child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF2E7D32), size: 42),
            ),
            const SizedBox(height: 16),
            const Text(
              'Vous êtes arrivé à destination !',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.background),
            ),
            const SizedBox(height: 6),
            const Text(
              'Réglez votre chauffeur en espèces ou par Mobile Money.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  const Text(
                    'TOTAL À PAYER',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$amount FCFA',
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  _completedSheetCtx = null;
                  Navigator.pop(sheetContext);
                  final paid = await showMobileMoneyPaymentSheet(
                    context: context,
                    rideId: rideId,
                    amount: amount,
                    departureAddress: data['departureAddress']?.toString() ?? '',
                    destinationAddress:
                        data['destinationAddress']?.toString() ?? '',
                  );
                  _paymentSheetOpen = false;
                  if (paid == true) {
                    _onRideFinished(data);
                  } else {
                    // Espèces choisies ou paiement fermé : on attend la
                    // confirmation du chauffeur (bouton « Régler » pour revenir).
                    if (mounted) {
                      setState(() => _awaitingDriverConfirmation = rideId);
                    }
                    _listenToCurrentRide();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('Régler la course',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
      );
      },
    ).whenComplete(() => _completedSheetCtx = null);
  }

  void _onRideFinished(Map<String, dynamic> data) {
    final rideId = data['id'].toString();
    _awaitingDriverConfirmation = null;
    _resetRide(message: 'Merci d\'avoir voyagé avec Moovi Gabon !');
    _askRating(rideId);
  }

  Future<void> _askRating(String rideId) async {
    var score = 5;
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Notez votre chauffeur'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setDialogState(() => score = i),
                  icon: Icon(
                    i <= score ? Icons.star_rounded : Icons.star_border_rounded,
                    color: AppColors.primary,
                    size: 32,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Plus tard'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Envoyer'),
            ),
          ],
        ),
      ),
    );
    if (submit != true) return;
    try {
      await DriverService.instance.rateRide(rideId, score: score);
    } catch (_) {}
  }

  Set<Marker> _driverMarkers = {};
  StreamSubscription<List<Map<String, dynamic>>>? _driversSubscription;

  BitmapDescriptor _carIcon = BitmapDescriptor.defaultMarker;

  /// Chauffeurs disponibles à proximité (API `GET /api/drivers/nearby`).
  void _listenToDrivers() {
    _driversSubscription = NearbyDriversService().getDrivers(() {
      final pos = _currentPosition;
      return pos == null
          ? null
          : (latitude: pos.latitude, longitude: pos.longitude);
    }).listen((drivers) {
      final markers = <Marker>{};

      for (final data in drivers) {
        final lat = asNum(data['latitude']);
        final lng = asNum(data['longitude']);
        if (lat == null || lng == null) continue;

        markers.add(
          Marker(
            markerId: MarkerId('driver_${data['id']}'),
            position: LatLng(lat.toDouble(), lng.toDouble()),
            icon: _carIcon,
            rotation: asNum(data['heading'])?.toDouble() ?? 0,
            infoWindow: InfoWindow(
              title: data['vehicleLabel']?.toString() ?? 'Chauffeur Moovi',
              snippet: data['arrivalMinutes'] != null
                  ? 'à ${data['arrivalMinutes']} min'
                  : data['city']?.toString() ?? '',
            ),
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        _driverMarkers = markers;
      });
    }, onError: (error) {
      debugPrint('Erreur chargement chauffeurs : $error');
    });
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    final origin = _shownOrigin;
    final destination = _shownDestination;

    // Chauffeur assigné (suivi en direct) ou chauffeurs disponibles.
    final assigned = _assignedDriverPosition;
    if (assigned != null && _acceptedOffer != null) {
      markers.add(Marker(
        markerId: const MarkerId('assigned_driver'),
        position: assigned,
        icon: _carIcon,
        infoWindow: InfoWindow(title: _acceptedOffer!.name),
      ));
    } else {
      markers.addAll(_driverMarkers);
    }

    // Marqueur du point de départ
    if (origin != null && origin != _currentPosition) {
      markers.add(
        Marker(
          markerId: const MarkerId('origin'),
          position: origin,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }

    // Marqueur de destination
    if (destination != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: destination,
          infoWindow: InfoWindow(
            title: _search.destinationText.text,
          ),
        ),
      );
    }

    return markers;
  }

  // ---------------------------------------------------------------------------
  // Sélection d'une suggestion
  // ---------------------------------------------------------------------------
  Future<void> _onSuggestionTap(PlaceSuggestion s) async {
    // Remplit le champ actif, ferme le clavier, récupère les coordonnées.
    await _search.pickSuggestion(s);
  }

  void _onClear(SearchField field) {
    _search.clear(field);
    _search.focusFor(field).requestFocus();
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
        await controller.animateCamera(CameraUpdate.newLatLngZoom(from, 16));
      }
      return;
    }
    if (from == null) {
      await controller.animateCamera(CameraUpdate.newLatLngZoom(to, 17));
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
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  /// Champ de saisie personnalisé, relié au contrôleur de recherche.
  Widget _buildPlaceField({
    required SearchField field,
    required String hint,
  }) {
    final text = _search.textFor(field);

    return SizedBox(
      height: _fieldHeight,
      child: TextField(
        controller: text,
        focusNode: _search.focusFor(field),
        onChanged: (t) => _search.onQueryChanged(field, t),
        textInputAction: TextInputAction.search,
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: text,
            builder: (_, value, __) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => _onClear(field),
                  ),
          ),
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }

  /// Sous les champs : erreur, suggestions, chargement.
  Widget _buildSuggestionsOrRecents() {
    if (_search.error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(_search.error!, style: const TextStyle(color: Colors.red)),
      );
    }

    final suggestions = _search.suggestions;

    if (suggestions.isNotEmpty) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.only(top: 8),
          itemCount: suggestions.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final s = suggestions[i];
            return ListTile(
              dense: true,
              leading: const Icon(Icons.location_on_outlined),
              title: Text(s.mainText,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: s.secondaryText.isEmpty
                  ? null
                  : Text(s.secondaryText,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _onSuggestionTap(s),
            );
          },
        ),
      );
    }

    if (_search.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  String get _rideBanner {
    switch (_rideStatus) {
      case 'driver_arrived':
        return 'Votre chauffeur est arrivé au point de départ';
      case 'in_progress':
        return 'Course en cours - Bon trajet !';
      case 'completed':
        return _awaitingDriverConfirmation != null
            ? 'Course terminée - en attente de la confirmation du chauffeur'
            : 'Course terminée - en attente du règlement';
      default:
        final eta = _driverEtaMinutes;
        return eta == null
            ? 'Chauffeur en route vers vous...'
            : 'Chauffeur en route · arrivée dans ~$eta min';
    }
  }

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
      // Quelques instants au plus : _initLocation finit toujours par une position.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final canCancel = _rideStatus == 'accepted' || _rideStatus == 'driver_arrived';

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: position, zoom: 15.5),
          onMapCreated: (c) {
            if (!_mapController.isCompleted) _mapController.complete(c);
          },
          style: mapStyle,
          polylines: polylines,
          markers: _buildMarkers(),
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
            FocusScope.of(context).unfocus();
            _search.dismissSuggestions();
          },
        ),

        // Carte de recherche : départ + destination + suggestions
        Positioned(
          top: 0,
          left: 16,
          right: 16,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(14),
                color: Colors.white,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(
                            width: 30,
                            height: _fieldHeight * 2 + _fieldGap,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Stack(
                                  children: [
                                    SizedBox(
                                      height: _fieldHeight,
                                      child: Center(
                                          child: Icon(
                                        Icons.circle,
                                        size: 18,
                                        color: AppColors.primary,
                                      )),
                                    ),
                                    SizedBox(
                                      height: _fieldHeight,
                                      child: Center(
                                          child: Icon(Icons.circle, size: 14)),
                                    ),
                                  ],
                                ),
                                DottedLine(
                                  direction: Axis.vertical,
                                  lineLength: 10,
                                  lineThickness: 2,
                                  dashLength: 1,
                                  dashGapLength: 2,
                                  dashColor: Colors.grey,
                                ),
                                SizedBox(
                                  height: _fieldHeight,
                                  child: Center(
                                      child: Icon(
                                    Icons.location_on,
                                    color: AppColors.primary,
                                  )),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Column(
                              children: [
                                _buildPlaceField(
                                  field: SearchField.origin,
                                  hint: 'Point de départ',
                                ),
                                const SizedBox(height: _fieldGap),
                                _buildPlaceField(
                                  field: SearchField.destination,
                                  hint: 'Où allez-vous ?',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      ListenableBuilder(
                        listenable: _search,
                        builder: (_, __) => _buildSuggestionsOrRecents(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        if (_locationWarning != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 156,
            child: Material(
              color: const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(12),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                child: Row(children: [
                  const Icon(Icons.gps_not_fixed, color: Color(0xFFB26A00), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_locationWarning!,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A4A00))),
                  ),
                  TextButton(onPressed: _initLocation, child: const Text('Réessayer')),
                ]),
              ),
            ),
          ),
        if (_currentRideId == null &&
            !_rideSheetOpen &&
            _shownOrigin != null &&
            _shownDestination != null)
          Positioned(
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).padding.bottom + 96,
            child: ElevatedButton.icon(
              onPressed: _openRideSelection,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.local_taxi_rounded),
              label: const Text('Commander une course',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),

        // -------------------------------------------------------------
        // OFFRES DES CHAUFFEURS EN DIRECT (API)
        // -------------------------------------------------------------
        if (_showOffers &&
            _currentRideId != null &&
            _acceptedOffer == null &&
            _offersStream != null)
          Positioned.fill(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _offersStream,
              builder: (context, snapshot) {
                final offers = (snapshot.data ?? const <Map<String, dynamic>>[])
                    .where((o) => o['status'] == 'pending')
                    .map((o) => DriverOffer.fromMap(o['id'].toString(), o))
                    .toList();

                return Stack(
                  children: [
                    DriverOffersSheet(
                      offers: offers,
                      onSelect: _acceptDriver,
                      onBack: _cancelRide,
                    ),
                    if (offers.isEmpty)
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 80,
                        left: 20,
                        right: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: const Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Recherche de chauffeurs à proximité au Gabon...',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),

        // -------------------------------------------------------------
        // COURSE ACCEPTÉE - CHAUFFEUR EN ROUTE
        // -------------------------------------------------------------
        if (_acceptedOffer != null)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 90,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.cream,
                        backgroundImage: _acceptedOffer!.photoUrl != null
                            ? NetworkImage(_acceptedOffer!.photoUrl!)
                            : null,
                        child: _acceptedOffer!.photoUrl == null
                            ? const Icon(Icons.person, color: AppColors.primary)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _acceptedOffer!.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${_acceptedOffer!.car} • ${_acceptedOffer!.plate}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            if (_acceptedOffer!.rating > 0)
                              Row(children: [
                                const Icon(Icons.star_rounded,
                                    size: 14, color: Color(0xFFFFB300)),
                                const SizedBox(width: 2),
                                Text(
                                  '${_acceptedOffer!.rating.toStringAsFixed(1)} · ${_acceptedOffer!.level.label}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ]),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${_acceptedOffer!.price} FCFA',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                          const Text(
                            'PRIX CONVENU',
                            style: TextStyle(fontSize: 9, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.directions_car,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _rideBanner,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_currentRideId != null) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => ContactService.call(context, _driverPhone),
                        icon: const Icon(Icons.call, size: 18),
                        label: const Text('Appeler'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RideChatPage(
                              rideId: _currentRideId!,
                              title: _acceptedOffer!.name,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('Message'),
                      ),
                    ),
                    ]),
                  ],
                  if (_rideStatus == 'completed' &&
                      _awaitingDriverConfirmation != null &&
                      _lastRideData != null) ...[
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _awaitingDriverConfirmation = null);
                        _showCompletedSheet(_lastRideData!);
                      },
                      icon: const Icon(Icons.phone_android, size: 18),
                      label: const Text('Payer par Mobile Money'),
                    ),
                  ],
                  if (canCancel) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _cancelRide,
                      child: const Text('Annuler la course',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
