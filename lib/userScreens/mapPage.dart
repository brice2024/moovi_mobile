import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:moovi/theme/app_colors.dart';
import 'package:moovi/userScreens/widgets/driverOffersSheet.dart';
import 'package:moovi/userScreens/widgets/rideSheetColors.dart';
import 'package:moovi/widgets/UserbottomNavBar.dart';
import '../services/itinéraire/DirectionsService.dart';
import '../services/driver_service.dart';
import '../widgets/paycentral_payment_sheet.dart';
import 'dataService.dart' hide DriverService;
import 'place_search_controller.dart';
import 'places_service.dart';

/// Page d'affichage de la carte : Google Map + champs départ / destination
/// avec suggestions gérées par [PlaceSearchController].
///
///
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  // Clé passée au lancement :
  //   flutter run --dart-define=PLACES_API_KEY=xxx
  static const _placesApiKey = "AIzaSyBs6DVjYiLlKjtJHqRwO6qTKouJ7o0f5F4";

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
  late final PlaceSearchController _search = PlaceSearchController(
    PlacesService(_placesApiKey),
    country: 'ga',
  );

  LatLng? _currentPosition;
  String? _error;

  // Derniers lieux affichés sur la carte (pour ne réagir qu'aux vrais changements).
  LatLng? _shownOrigin;
  LatLng? _shownDestination;
  Set<Marker> _markers = {};

  // Dernier trajet pour lequel searchDriver a été lancé (évite les doublons).
  String? _lastSearchKey;

  //distance et temps du trajet
  int distance = 0;
  String temps = '';

  bool _showOffers = false;
  String? _currentRideId;
  DriverOffer? _acceptedOffer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _currentRideSub;

  //tracer les itinéraires
  final DirectionsService directionsService =
  DirectionsService();
  Set<Polyline> polylines = {};
  int animationVersion = 0;


  Future<void> tracerItineraire() async {
    if (_shownOrigin == null ||
        _shownDestination == null) {
      return;
    }

    try {
      final info = await directionsService.getRoute(
        _shownOrigin!,
        _shownDestination!,
      );

      if (!mounted) return;

      setState(() {
        polylines = {
          Polyline(
            polylineId: const PolylineId("bordure"),
            points: info.points,
            color: AppColors.primaryDark,
            width: 11,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
            zIndex: 0
          ),

          Polyline(
            polylineId: const PolylineId("trajet"),
            points: info.points,
            color: AppColors.primary,
            width: 7,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
            zIndex: 1
          ),
        };
        distance = info.distanceMeters;
        temps = info.durationText;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Impossible de tracer le trajet : $e"),
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
  }

  @override
  void dispose() {
    _search.originFocus.removeListener(_onOriginFocusChanged);
    _search.removeListener(_onSearchChanged);
    _search.dispose(); // libère aussi les champs et les focus
    _driversSubscription?.cancel();
    _currentRideSub?.cancel();
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
    _search.originText.value = TextEditingValue(
      text: _originLabel,
      selection: TextSelection.collapsed(offset: _originLabel.length),
    );
    _search.setPlace(SearchField.origin, here);
    _maybeSearchDriver();
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
  // Réaction aux changements du contrôleur de recherche
  // ---------------------------------------------------------------------------
  Future<void> _onSearchChanged() async {
    final origin = _search.origin;
    final destination = _search.destination;
    if (origin == _shownOrigin && destination == _shownDestination) return;

    _shownOrigin = origin;
    _shownDestination = destination;

    if (!mounted) return;
    setState(() => _markers = _buildMarkers());
    _updateCamera();


    if (_shownOrigin != null && _shownDestination!= null) {
      await tracerItineraire();
    }

    if (_shownDestination == null ) {
      polylines.clear();
    }

    if (_shownOrigin != null && _shownDestination != null) {
      await Future.delayed(
        const Duration(milliseconds: 1500),
      );
      showRideSelectionSheet(
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
        distanceText: distance > 0 ? '${(distance / 1000).toStringAsFixed(1)} km' : '',
        durationText: temps,
        onConfirm: (option, price, rideId) {
          setState(() {
            _currentRideId = rideId;
            _showOffers = true;
            _acceptedOffer = null;
          });
        },
      );
    }
  }

  void _acceptDriver(DriverOffer offer) async {
    if (_currentRideId == null) return;
    setState(() {
      _acceptedOffer = offer;
    });

    await DriverService.instance.acceptDriverOffer(
      rideId: _currentRideId!,
      driverId: offer.id,
      agreedPrice: offer.price,
      driverName: offer.name,
      car: offer.car,
      plate: offer.plate,
      photoUrl: offer.photoUrl,
    );

    _listenToCurrentRide();
  }

  void _listenToCurrentRide() {
    if (_currentRideId == null) return;
    _currentRideSub?.cancel();
    _currentRideSub =
        DriverService.instance.streamRide(_currentRideId!).listen((snap) {
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null) return;

      final status = data['status']?.toString();
      final isPaid = data['isPaid'] == true;

      // Lorsque la course est terminée par le chauffeur
      if (status == 'completed' && !isPaid && mounted) {
        _currentRideSub?.cancel();
        showPayCentralPaymentSheet(
          context: context,
          rideId: _currentRideId!,
          amount: (data['agreedPrice'] as num?)?.toInt() ??
              (data['price'] as num?)?.toInt() ??
              2000,
          departureAddress:
              data['departureAddress']?.toString() ?? 'Point de départ',
          destinationAddress:
              data['destinationAddress']?.toString() ?? 'Destination',
        ).then((paid) {
          if (paid == true && mounted) {
            setState(() {
              _showOffers = false;
              _acceptedOffer = null;
              _currentRideId = null;
              polylines.clear();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Course réglée avec succès via PayCentral ! Merci d\'avoir choisi Moovi.',
                ),
              ),
            );
          }
        });
      }
    });
  }

  Set<Marker> _driverMarkers = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _driversSubscription;

  BitmapDescriptor _carIcon = BitmapDescriptor.defaultMarker;

  void _listenToDrivers() {
    _driversSubscription = FirebaseFirestore.instance
        .collection('test_drivers')
        .where('isAvailable', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      final markers = <Marker>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final location = data['location'];

        if (location is! GeoPoint) continue;

        markers.add(
          Marker(
            markerId: MarkerId(doc.id),
            position: LatLng(
              location.latitude,
              location.longitude,
            ),
            icon: _carIcon,
            infoWindow: InfoWindow(
              title: 'Chauffeur ${doc.id}',
              snippet: data['city']?.toString() ?? '',
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

    // Ajouter tous les chauffeurs disponibles
    markers.addAll(_driverMarkers);

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
  // Sélection d'une suggestion + déclenchement de searchDriver
  // ---------------------------------------------------------------------------
  Future<void> _onSuggestionTap(PlaceSuggestion s) async {
    // Remplit le champ actif, ferme le clavier, récupère les coordonnées.
    final latLng = await _search.pickSuggestion(s);
    if (latLng == null || !mounted) return;
    _maybeSearchDriver();
  }

  void _onClear(SearchField field) {
    _search.clear(field);
    if (field == SearchField.destination) {
      _lastSearchKey = null;

      // TODO : annuler la recherche de chauffeur en cours si nécessaire.

    }
    _search.focusFor(field).requestFocus();
  }

  /// Lance searchDriver dès que le départ ET la destination sont choisis.
  void _maybeSearchDriver() {
    final origin = _search.origin;
    final destination = _search.destination;
    if (origin == null || destination == null) return;

    final key = '${origin.latitude},${origin.longitude}'
        '>${destination.latitude},${destination.longitude}';
    if (key == _lastSearchKey) return; // même trajet : déjà lancé
    _lastSearchKey = key;

    searchDriver(origin: origin, destination: destination).catchError((_) {
      _lastSearchKey = null; // permet de relancer en cas d'échec
    });

  }

  /// À implémenter : recherche d'un chauffeur pour ce trajet.
  Future<void> searchDriver({
    required LatLng origin,
    required LatLng destination,
  }) async {
    // TODO : appel API / provider / Bloc pour trouver un chauffeur.
    debugPrint('searchDriver: $origin -> $destination');
    print("ojifjebfjneeefd81d54d84d15v4dvv8v");
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

  Future<void> _recenter() async {
    final pos = _currentPosition;
    if (pos == null) return;
    final controller = await _mapController.future;
    await controller.animateCamera(CameraUpdate.newLatLngZoom(pos, 20));
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
        style: TextStyle(
          fontSize: 13
        ),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }

  /// Sous les champs : erreur, suggestions, chargement, sinon dernières destinations.
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
              title: Text(s.mainText, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: s.secondaryText.isEmpty
                  ? null
                  : Text(s.secondaryText, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    
    return Text("");

    //3 dernières destinations

    /*
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
      height: 60,
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.access_time_outlined, size: 18,),
          SizedBox(width: 12,),
          Column(mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,children: [
              Text("Arribat Center", style: TextStyle(
                  fontSize: 14
              ),),

              Text("Avenue Omar Ibn al Khattab")
            ],
          ),

        ],
      ),
    );*/
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: position, zoom: 15.5),
          onMapCreated: (c) {
            if (!_mapController.isCompleted) _mapController.complete(c);
          },
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

        if (_showOffers)
          DriverOffersSheet(
            offers: demoOffers, // remplace par tes vraies offres
            onSelect: (offer) {
              /// todo accepter le chaufeur
              print(offer.price);
              print(offer.car);
              print(offer.id);
              print(offer.arrivalMinutes);
              // l'utilisateur a choisi un chauffeur
            },
            onBack: () => setState(() => _showOffers = false),
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
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
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
                                      child: Center(child: Icon(Icons.circle, size: 18, color:  AppColors.primary,)),
                                    ),
                                    SizedBox(
                                      height: _fieldHeight,
                                      child: Center(child: Icon(Icons.circle, size: 14)),
                                    ),
                                  ],
                                ),
                                DottedLine(
                                  direction: Axis.vertical,
                                  lineLength: 10,
                                  lineThickness: 2,
                                  dashLength:1,
                                  dashGapLength: 2,
                                  dashColor: Colors.grey,
                                ),
                                SizedBox(
                                  height: _fieldHeight,
                                  child: Center(child: Icon(Icons.location_on, color:  AppColors.primary,)),
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


        /*
        ElevatedButton(
          onPressed: () async {
            try {
              await ImportDriversService.importDrivers();

              debugPrint("Importation terminée !");
            } catch (e) {
              debugPrint("Erreur importation : $e");
            }
          },
          child: const Text("Importer les 50 chauffeurs"),
        )


         */

        // Bouton recentrer
        /*
        Positioned(
          right: 16,
          bottom: 24,
          child: FloatingActionButton.small(
            heroTag: 'recenter',
            onPressed: _recenter,
            child: const Icon(Icons.my_location),
          ),
        ),
        */

        // -------------------------------------------------------------
        // OFFRES DES CHAUFFEURS EN DIRECT (Firestore)
        // -------------------------------------------------------------
        if (_showOffers && _currentRideId != null && _acceptedOffer == null)
          Positioned.fill(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: DriverService.instance.streamRideOffers(_currentRideId!),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                final offers = docs
                    .map((d) => DriverOffer.fromMap(d.id, d.data()))
                    .toList();

                return Stack(
                  children: [
                    DriverOffersSheet(
                      offers: offers,
                      onSelect: _acceptDriver,
                      onBack: () => setState(() => _showOffers = false),
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
                          child: Row(
                            children: const [
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
                      children: const [
                        Icon(Icons.directions_car,
                            size: 16, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text(
                          'Chauffeur en route vers vous...',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

      ],
    );
  }
}


