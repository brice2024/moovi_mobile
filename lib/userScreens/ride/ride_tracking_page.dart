import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../functions.dart';
import '../../services/driver_service.dart';
import '../../services/itinéraire/DirectionsService.dart';
import '../widgets/driverOffersSheet.dart';
import 'ride_cards.dart';
import 'ride_completed_page.dart';
import 'ride_style.dart';
import 'vehicle_markers.dart';

/// Résultat renvoyé à la carte d'accueil quand le suivi se ferme.
enum RideTrackingResult { finished, cancelled }

/// Statuts écrits par l'app chauffeur (active_ride_page.dart).
class RideStatus {
  static const accepted = 'accepted';
  static const driverArrived = 'driver_arrived';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const cancelled = 'cancelled';
}

/// Suivi de la course côté client (maquettes 13, 14 et 15).
class RideTrackingPage extends StatefulWidget {
  const RideTrackingPage({
    super.key,
    required this.rideId,
    required this.pickup,
    required this.destination,
    required this.from,
    required this.to,
    this.offer,
    this.rideType = 'voiture',
    this.distanceText = '',
    this.durationText = '',
  });

  final String rideId;
  final LatLng pickup;
  final LatLng destination;
  final String from;
  final String to;
  final DriverOffer? offer;
  final String rideType;
  final String distanceText;
  final String durationText;

  @override
  State<RideTrackingPage> createState() => _RideTrackingPageState();
}

class _RideTrackingPageState extends State<RideTrackingPage> {
  final Completer<GoogleMapController> _map = Completer();
  final DirectionsService _directions = DirectionsService();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _rideSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _driverSub;
  Timer? _ticker;

  String _status = RideStatus.accepted;
  Map<String, dynamic> _ride = const {};
  DriverOffer? _offer;
  String? _driverId;
  LatLng? _driverPos;

  // Itinéraire affiché + infos associées.
  List<LatLng> _route = const [];
  int? _routeSeconds;
  int? _routeMeters;
  String? _routeKey;
  LatLng? _routeFrom;
  DateTime _routeAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Valeurs de référence pour la barre d'avancement.
  int? _initialEtaSeconds;
  int? _tripMeters;

  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _offer = widget.offer;
    VehicleMarkerIcons.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    _rideSub = DriverService.instance.streamRide(widget.rideId).listen(
          _onRide,
          onError: (e) => debugPrint('Suivi course : $e'),
        );
    // Rafraîchit l'estimation de secours (basée sur l'heure d'acceptation).
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _rideSub?.cancel();
    _driverSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Firestore
  // ---------------------------------------------------------------------------

  void _onRide(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null || !mounted) return;

    final status = data['status']?.toString() ?? RideStatus.accepted;
    final driverId = data['driverId']?.toString();

    setState(() {
      _ride = data;
      _status = status;
    });

    if (driverId != null && driverId.isNotEmpty && driverId != _driverId) {
      _driverId = driverId;
      _listenToDriver(driverId);
      if (_offer == null) _loadOffer(driverId);
    }

    switch (status) {
      case RideStatus.completed:
        _openCompleted();
        return;
      case RideStatus.cancelled:
        _close(RideTrackingResult.cancelled);
        return;
    }
    _refreshRoute();
  }

  void _listenToDriver(String driverId) {
    _driverSub?.cancel();
    _driverSub = FirebaseFirestore.instance
        .collection('drivers')
        .doc(driverId)
        .snapshots()
        .listen((snap) {
      final pos = _geoFrom(snap.data());
      if (pos == null || !mounted) return;
      setState(() => _driverPos = pos);
      _refreshRoute();
    }, onError: (e) => debugPrint('Position chauffeur : $e'));
  }

  /// Position du chauffeur : `location` (GeoPoint) ou `position.geopoint`.
  LatLng? _geoFrom(Map<String, dynamic>? data) {
    if (data == null) return null;
    final loc = data['location'];
    if (loc is GeoPoint) return LatLng(loc.latitude, loc.longitude);
    final pos = data['position'];
    if (pos is Map && pos['geopoint'] is GeoPoint) {
      final g = pos['geopoint'] as GeoPoint;
      return LatLng(g.latitude, g.longitude);
    }
    return null;
  }

  Future<void> _loadOffer(String driverId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('rides')
          .doc(widget.rideId)
          .collection('offers')
          .doc(driverId)
          .get();
      final data = doc.data();
      if (data != null && mounted) {
        setState(() => _offer = DriverOffer.fromMap(driverId, data));
      }
    } catch (e) {
      debugPrint('Offre du chauffeur : $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Itinéraire
  // ---------------------------------------------------------------------------

  /// Tronçon à afficher selon le statut :
  /// en route → chauffeur ➜ point de départ ; sinon départ ➜ destination
  /// (ou chauffeur ➜ destination pendant la course).
  (LatLng, LatLng)? get _leg {
    switch (_status) {
      case RideStatus.accepted:
        final d = _driverPos;
        return d == null ? null : (d, widget.pickup);
      case RideStatus.inProgress:
        return (_driverPos ?? widget.pickup, widget.destination);
      default:
        return (widget.pickup, widget.destination);
    }
  }

  Future<void> _refreshRoute() async {
    final leg = _leg;
    if (leg == null) {
      _fitCamera();
      return;
    }
    final (from, to) = leg;
    final key = _status;
    final moved = _routeFrom == null ||
        Geolocator.distanceBetween(
              from.latitude,
              from.longitude,
              _routeFrom!.latitude,
              _routeFrom!.longitude,
            ) >
            120;
    final stale = DateTime.now().difference(_routeAt) > const Duration(seconds: 20);
    if (key == _routeKey && !(moved && stale)) return;

    _routeKey = key;
    _routeFrom = from;
    _routeAt = DateTime.now();
    try {
      final info = await _directions.getRoute(from, to);
      if (!mounted || _routeKey != key) return;
      setState(() {
        _route = info.points;
        _routeSeconds = info.duration.inSeconds;
        _routeMeters = info.distanceMeters;
        if (_status == RideStatus.accepted) {
          _initialEtaSeconds ??= info.duration.inSeconds;
        }
        if (_status != RideStatus.accepted) {
          _tripMeters ??= info.distanceMeters;
        }
      });
    } catch (e) {
      debugPrint('Itinéraire de suivi : $e');
      if (!mounted) return;
      setState(() {
        _route = [from, to];
        _routeSeconds = null;
        _routeMeters = null;
      });
    }
    _fitCamera();
  }

  Future<void> _fitCamera() async {
    if (!_map.isCompleted) return;
    final c = await _map.future;
    final pts = <LatLng>[
      if (_driverPos != null) _driverPos!,
      if (_status != RideStatus.inProgress) widget.pickup,
      if (_status != RideStatus.accepted || _driverPos == null) widget.destination,
      ..._route,
    ];
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
      return;
    }
    var minLat = pts.first.latitude, maxLat = minLat;
    var minLng = pts.first.longitude, maxLng = minLng;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    if (maxLat - minLat < 0.002 && maxLng - minLng < 0.002) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 16));
      return;
    }
    try {
      await c.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        70,
      ));
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Valeurs affichées
  // ---------------------------------------------------------------------------

  int get _price =>
      (_ride['agreedPrice'] as num?)?.toInt() ??
      _offer?.price ??
      (_ride['price'] as num?)?.toInt() ??
      0;

  /// Minutes avant l'arrivée du chauffeur (en route) ou à destination.
  int get _etaMinutes {
    switch (_status) {
      case RideStatus.driverArrived:
        return 0;
      case RideStatus.accepted:
        if (_routeSeconds != null && _driverPos != null) {
          return (_routeSeconds! / 60).ceil();
        }
        // Secours : délai annoncé dans l'offre moins le temps écoulé.
        final announced = _offer?.arrivalMinutes ?? 5;
        final acceptedAt = (_ride['acceptedAt'] as Timestamp?)?.toDate();
        if (acceptedAt == null) return announced;
        final elapsed = DateTime.now().difference(acceptedAt).inMinutes;
        return (announced - elapsed).clamp(1, announced);
      default:
        if (_routeSeconds != null) return (_routeSeconds! / 60).ceil();
        return _parseMinutes(widget.durationText) ?? 0;
    }
  }

  int? _parseMinutes(String text) {
    final h = RegExp(r'(\d+)\s*h').firstMatch(text);
    final m = RegExp(r'(\d+)\s*min').firstMatch(text);
    if (h == null && m == null) return null;
    return (int.tryParse(h?.group(1) ?? '0') ?? 0) * 60 +
        (int.tryParse(m?.group(1) ?? '0') ?? 0);
  }

  double get _progress {
    switch (_status) {
      case RideStatus.accepted:
        final initial = _initialEtaSeconds;
        if (initial == null || initial == 0 || _routeSeconds == null) {
          final announced = (_offer?.arrivalMinutes ?? 5).clamp(1, 600);
          return 1 - _etaMinutes / announced;
        }
        return 1 - _routeSeconds! / initial;
      case RideStatus.driverArrived:
        return 1;
      case RideStatus.inProgress:
        final total = _tripMeters;
        if (total == null || total == 0 || _routeMeters == null) return 0.05;
        return 1 - _routeMeters! / total;
      default:
        return 1;
    }
  }

  String get _distanceText {
    if (widget.distanceText.isNotEmpty) return widget.distanceText;
    final d = _ride['distance']?.toString() ?? '';
    return d;
  }

  String get _bannerText {
    switch (_status) {
      case RideStatus.driverArrived:
        return 'Votre chauffeur est arrivé';
      case RideStatus.inProgress:
        return 'Course en cours · arrivée dans $_etaMinutes min';
      default:
        return 'Chauffeur en route · arrive dans $_etaMinutes min';
    }
  }

  String get _chipText {
    switch (_status) {
      case RideStatus.driverArrived:
        return 'Course démarrée';
      case RideStatus.inProgress:
        return 'Fin de course';
      default:
        return 'Chauffeur en route';
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  Future<void> _openCompleted() async {
    if (_leaving) return;
    _leaving = true;
    _rideSub?.cancel();
    _driverSub?.cancel();
    final navigator = Navigator.of(context);
    await navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => RideCompletedPage(
          rideId: widget.rideId,
          amount: _price,
          from: widget.from,
          to: widget.to,
          distanceText: _distanceText,
          durationText: widget.durationText.isNotEmpty
              ? widget.durationText
              : _ride['duration']?.toString() ?? '',
        ),
      ),
      result: RideTrackingResult.finished,
    );
  }

  void _close(RideTrackingResult result) {
    if (_leaving) return;
    _leaving = true;
    if (result == RideTrackingResult.cancelled) {
      final by = _ride['cancelledBy']?.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(by == 'client'
            ? 'Votre course a été annulée.'
            : 'La course a été annulée par le chauffeur.'),
      ));
    }
    Navigator.of(context).pop(result);
  }

  Future<void> _onBack() async {
    if (_status == RideStatus.inProgress) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('La course est en cours : elle ne peut plus être annulée.'),
      ));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la course ?'),
        content: const Text(
          'Le chauffeur sera prévenu de l\'annulation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await cancelRide(widget.rideId);
      // Le listener reçoit « cancelled » et ferme la page.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Annulation impossible : $e'),
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Set<Marker> _markers() {
    final kind = widget.rideType == 'moto' ? VehicleKind.moto : VehicleKind.voiture;
    return {
      if (_status != RideStatus.inProgress)
        Marker(
          markerId: const MarkerId('pickup'),
          position: widget.pickup,
          icon: VehicleMarkerIcons.pickup,
          anchor: const Offset(0.5, 0.5),
          infoWindow: const InfoWindow(title: 'Votre position'),
        ),
      if (_status != RideStatus.accepted)
        Marker(
          markerId: const MarkerId('destination'),
          position: widget.destination,
          icon: VehicleMarkerIcons.destination,
          anchor: const Offset(0.5, 0.5),
          infoWindow: const InfoWindow(title: 'Votre destination'),
        ),
      if (_driverPos != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverPos!,
          icon: VehicleMarkerIcons.forKind(kind),
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 2,
          infoWindow: InfoWindow(title: _offer?.name ?? 'Votre chauffeur'),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_leaving) _onBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF242120),
        body: Stack(
          children: [
            Positioned.fill(
              child: GoogleMap(
                padding: EdgeInsets.only(top: top + 50, bottom: 300),
                initialCameraPosition: CameraPosition(target: widget.pickup, zoom: 15),
                style: kMooviDarkMapStyle,
                onMapCreated: (c) {
                  if (!_map.isCompleted) _map.complete(c);
                  _fitCamera();
                },
                markers: _markers(),
                polylines: {
                  if (_route.length >= 2)
                    Polyline(
                      polylineId: const PolylineId('track'),
                      points: _route,
                      color: RideColors.orange,
                      width: 5,
                      startCap: Cap.roundCap,
                      endCap: Cap.roundCap,
                      jointType: JointType.round,
                    ),
                },
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
              ),
            ),
            Positioned(
              top: top + 10,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Material(
                    color: RideColors.orange,
                    shape: const CircleBorder(),
                    elevation: 4,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _onBack,
                      child: const SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: RideColors.bannerBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _bannerText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: RideColors.bannerText,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 46),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildPanel(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final offer = _offer;
    final name = offer?.name ?? _ride['driverName']?.toString() ?? 'Votre chauffeur';
    final car = offer?.car ?? _ride['driverCar']?.toString() ?? 'Véhicule';
    final plate = offer?.plate ?? _ride['driverPlate']?.toString() ?? '';
    final photo = offer?.photoUrl ?? _ride['driverPhotoUrl']?.toString();
    final level = offer?.level ?? DriverLevel.or;
    final eta = _etaMinutes;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 26, 20, 16 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ItineraryCard(
            from: widget.from,
            to: widget.to,
            minutesText: '${eta.toString().padLeft(2, '0')} min',
            distanceText: _distanceText,
            progress: _progress,
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DriverPhoto(
                photoUrl: photo,
                badgeColor: level.color,
                badgeIcon: level.icon,
                size: 64,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: RideColors.brown,
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, size: 17, color: RideColors.star),
                          const SizedBox(width: 3),
                          Text(
                            (offer?.rating ?? 4.8).toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: RideColors.brown,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            level.label,
                            style: const TextStyle(fontSize: 12.5, color: RideColors.brownLabel),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: formatFcfa(_price),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                        const TextSpan(
                          text: ' FCFA',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ]),
                      style: const TextStyle(color: RideColors.brown),
                    ),
                    Text(
                      _status == RideStatus.accepted
                          ? 'Arrivée : $eta min'
                          : _status == RideStatus.driverArrived
                              ? 'Sur place'
                              : 'Destination : $eta min',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: RideColors.brownMid,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.directions_car_outlined, size: 18, color: RideColors.brown),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  plate.isEmpty ? car : '$car •\n$plate',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, height: 1.25, color: RideColors.brown),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: RideColors.dark,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_taxi_outlined, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _chipText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
