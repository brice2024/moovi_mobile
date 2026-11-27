import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/contact_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/api_client.dart';
import '../../services/driver_service.dart';
import '../../services/itinéraire/DirectionsService.dart';
import '../../widgets/ride_chat_page.dart';
import 'driver_theme.dart';
import 'ride_offer.dart';

enum ActiveRideStep {
  goingToClient, // En route vers le client
  arrivedAtClient, // Arrivé au point de prise en charge
  inProgress, // Course en cours vers destination
  completed, // Course terminée
}

class ActiveRidePage extends StatefulWidget {
  final RideOffer offer;
  final int? agreedPrice;

  /// Statut API au moment de l'ouverture (reprise d'une course en cours).
  final String? initialStatus;

  const ActiveRidePage({
    super.key,
    required this.offer,
    this.agreedPrice,
    this.initialStatus,
  });

  @override
  State<ActiveRidePage> createState() => _ActiveRidePageState();
}

class _ActiveRidePageState extends State<ActiveRidePage> {
  ActiveRideStep _currentStep = ActiveRideStep.goingToClient;
  bool _isPaid = false;
  bool _busy = false;
  int? _amountDue;
  StreamSubscription? _rideSub;

  int get finalPrice => widget.agreedPrice ?? widget.offer.price;

  /// Montant réellement à encaisser (après réduction promo/parrainage financée par Moovi).
  int get amountToCollect => _amountDue ?? finalPrice;

  static ActiveRideStep _stepFor(String? status) {
    switch (status) {
      case 'driver_arrived':
        return ActiveRideStep.arrivedAtClient;
      case 'in_progress':
        return ActiveRideStep.inProgress;
      case 'completed':
        return ActiveRideStep.completed;
      default:
        return ActiveRideStep.goingToClient;
    }
  }

  // Coordonnées par défaut au Gabon (Libreville) si non fournies
  LatLng get _pickup =>
      widget.offer.departureLocation ?? const LatLng(0.4162, 9.4673);
  LatLng get _dropoff =>
      widget.offer.destinationLocation ?? const LatLng(0.4250, 9.4500);

  @override
  void initState() {
    super.initState();
    _currentStep = _stepFor(widget.initialStatus);
    // Position transmise au passager pendant toute la course.
    DriverService.instance.startLocationHeartbeat();
    _listenToRide();
    _loadRoute();
  }

  List<LatLng>? _route;

  /// Itinéraire réel (Google Routes via l'API) ; ligne droite en secours.
  Future<void> _loadRoute() async {
    try {
      final info = await DirectionsService().getRoute(_pickup, _dropoff);
      if (mounted && info.points.isNotEmpty) setState(() => _route = info.points);
    } catch (_) {}
  }

  @override
  void dispose() {
    _rideSub?.cancel();
    super.dispose();
  }

  String? _clientPhone;

  void _listenToRide() {
    _rideSub = DriverService.instance.streamRide(widget.offer.id).listen((data) {
      if (!mounted) return;
      final status = data['status']?.toString();
      setState(() {
        _amountDue = asNum(data['amountDue'])?.toInt();
        if (data['isPaid'] == true) _isPaid = true;
        // Le téléphone du passager n'est transmis qu'au chauffeur attribué.
        _clientPhone = data['clientPhone']?.toString() ?? _clientPhone;
        // Le serveur fait foi (ex. réponse perdue après un changement d'étape).
        if (status != null && status != 'cancelled') {
          final serverStep = _stepFor(status);
          if (serverStep.index > _currentStep.index) _currentStep = serverStep;
        }
      });

      if (status == 'cancelled' && _currentStep != ActiveRideStep.completed) {
        _rideSub?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La course a été annulée par le passager.')),
        );
        Navigator.maybePop(context);
      }
    }, onError: (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Suivi de la course interrompu : ${errorMessage(e)}')));
    });
  }

  Future<void> _setStatus(String status, ActiveRideStep next) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await DriverService.instance.updateRideStatus(
        rideId: widget.offer.id,
        newStatus: status,
      );
      if (!mounted) return;
      setState(() => _currentStep = next);
      if (next == ActiveRideStep.completed) _promptPayment();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'INVALID_STATE_TRANSITION') {
        // Étape déjà appliquée côté serveur : on se resynchronise.
        try {
          final ride = await DriverService.instance.getRide(widget.offer.id);
          if (mounted) {
            setState(() => _currentStep = _stepFor(ride['status']?.toString()));
          }
        } catch (_) {}
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _advanceStep() async {
    switch (_currentStep) {
      case ActiveRideStep.goingToClient:
        await _setStatus('driver_arrived', ActiveRideStep.arrivedAtClient);
        break;

      case ActiveRideStep.arrivedAtClient:
        await _setStatus('in_progress', ActiveRideStep.inProgress);
        break;

      case ActiveRideStep.inProgress:
        await _setStatus('completed', ActiveRideStep.completed);
        break;

      case ActiveRideStep.completed:
        Navigator.pop(context);
        break;
    }
  }

  Future<void> _confirmCash() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // L'API marque la course payée et prélève atomiquement la commission (15 %).
      final result = await DriverService.instance.confirmCashPayment(widget.offer.id);
      if (!mounted) return;
      setState(() => _isPaid = true);
      final wallet = result['wallet'];
      final blocked = wallet is Map && wallet['isWalletBlocked'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(blocked
              ? 'Paiement confirmé. Solde insuffisant : rechargez votre portefeuille pour reprendre les courses.'
              : 'Paiement espèces confirmé. La commission de 15 % a été prélevée à la fin de la course.'),
          backgroundColor: blocked ? Colors.red : MooviColors.green,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'ALREADY_PAID') {
        setState(() => _isPaid = true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _promptPayment() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
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
            const SizedBox(height: 18),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: MooviColors.green.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.payments_rounded, color: MooviColors.green, size: 32),
            ),
            const SizedBox(height: 16),
            const Text(
              'Règlement en Espèces (Cash)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: MooviColors.dark),
            ),
            const SizedBox(height: 6),
            Text(
              'Le passager doit vous remettre le montant de la course en espèces.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MONTANT À PERCEVOIR',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MooviColors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$amountToCollect FCFA',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: MooviColors.orange),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: MooviColors.orangeSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Commission: ${(finalPrice * 0.15).round()} FCFA (15%)',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: MooviColors.orange),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _confirmCash();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: MooviColors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('Confirmer l\'encaissement en Espèces', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _buttonLabel {
    switch (_currentStep) {
      case ActiveRideStep.goingToClient:
        return 'Je suis arrivé au point de départ';
      case ActiveRideStep.arrivedAtClient:
        return 'Client à bord - Démarrer la course';
      case ActiveRideStep.inProgress:
        return 'Terminer la course';
      case ActiveRideStep.completed:
        return _isPaid ? 'Retour à l\'accueil' : 'Confirmer encaissement Espèces';
    }
  }

  String get _statusBadgeLabel {
    switch (_currentStep) {
      case ActiveRideStep.goingToClient:
        return 'EN ROUTE VERS LE CLIENT';
      case ActiveRideStep.arrivedAtClient:
        return 'ARRIVÉ AU POINT DE DÉPART';
      case ActiveRideStep.inProgress:
        return 'COURSE EN COURS';
      case ActiveRideStep.completed:
        return _isPaid ? 'COURSE TERMINÉE & RÉGLÉE' : 'COURSE TERMINÉE - ATTENTE PAIEMENT';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: _pickup, zoom: 14),
          zoomControlsEnabled: false,
          myLocationButtonEnabled: true,
          markers: {
            Marker(
              markerId: const MarkerId('pickup'),
              position: _pickup,
              infoWindow: InfoWindow(title: 'Départ', snippet: widget.offer.from),
            ),
            Marker(
              markerId: const MarkerId('destination'),
              position: _dropoff,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
              infoWindow: InfoWindow(title: 'Destination', snippet: widget.offer.to),
            ),
          },
          polylines: {
            Polyline(
              polylineId: const PolylineId('route'),
              points: _route ?? [_pickup, _dropoff],
              color: MooviColors.orange,
              width: 5,
            ),
          },
        ),

        // En-tête
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const OnlineChip(online: true),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: MooviColors.orange,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _statusBadgeLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(.1), blurRadius: 10)],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _top('${widget.offer.minutes} min', 'ESTIMATION'),
                  Container(
                    width: 1,
                    height: 28,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    color: MooviColors.border,
                  ),
                  _top('${widget.offer.km} km', 'DISTANCE'),
                ]),
              ),
            ]),
          ),
        ),

        // Carte d'actions en bas
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(.14), blurRadius: 16)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const CircleAvatar(
                    radius: 22,
                    backgroundColor: MooviColors.bg,
                    child: Icon(Icons.person, color: MooviColors.orange),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.offer.clientName ?? 'Passager Moovi', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      Text(
                        'Trajet : ${widget.offer.from.split(',').first} → ${widget.offer.to.split(',').first}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: MooviColors.grey),
                      ),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(
                      '$finalPrice FCFA',
                      style: const TextStyle(fontSize: 18, color: MooviColors.orange, fontWeight: FontWeight.w900),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _isPaid ? const Color(0xFFE8F5E9) : MooviColors.orangeSoft,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _isPaid ? 'RÉGLÉ' : 'À PAYER',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: _isPaid ? const Color(0xFF2E7D32) : MooviColors.orange,
                        ),
                      ),
                    ),
                  ]),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: _action(Icons.call, 'Appeler',
                        () => ContactService.call(context, _clientPhone ?? widget.offer.clientPhone)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _action(Icons.chat_bubble_outline, 'Message', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RideChatPage(
                            rideId: widget.offer.id,
                            title: (widget.offer.clientName ?? '').isNotEmpty
                                ? widget.offer.clientName!
                                : 'Passager',
                          ),
                        ),
                      );
                    }),
                  ),
                ]),
                const SizedBox(height: 12),
                OrangeButton(
                  label: _buttonLabel,
                  icon: _currentStep == ActiveRideStep.completed ? Icons.check_circle : Icons.arrow_forward,
                  onPressed: _busy
                      ? null
                      : _currentStep == ActiveRideStep.completed && !_isPaid
                          ? _promptPayment
                          : _advanceStep,
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _top(String v, String l) => Column(children: [
        Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        Text(l, style: const TextStyle(fontSize: 8, color: MooviColors.grey, fontWeight: FontWeight.w600)),
      ]);

  Widget _action(IconData i, String l, VoidCallback onTap) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(i, size: 16),
        label: Text(l, style: const TextStyle(fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: MooviColors.dark,
          side: const BorderSide(color: MooviColors.border),
          minimumSize: const Size.fromHeight(42),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
}
