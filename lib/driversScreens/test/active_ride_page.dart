import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/driver_service.dart';
import '../../widgets/paycentral_payment_sheet.dart';
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

  const ActiveRidePage({
    super.key,
    required this.offer,
    this.agreedPrice,
  });

  @override
  State<ActiveRidePage> createState() => _ActiveRidePageState();
}

class _ActiveRidePageState extends State<ActiveRidePage> {
  ActiveRideStep _currentStep = ActiveRideStep.goingToClient;
  bool _isPaid = false;
  StreamSubscription? _rideSub;

  int get finalPrice => widget.agreedPrice ?? widget.offer.price;

  // Coordonnées par défaut au Gabon (Libreville) si non fournies
  LatLng get _pickup =>
      widget.offer.departureLocation ?? const LatLng(0.4162, 9.4673);
  LatLng get _dropoff =>
      widget.offer.destinationLocation ?? const LatLng(0.4250, 9.4500);

  @override
  void initState() {
    super.initState();
    _listenToPayment();
  }

  @override
  void dispose() {
    _rideSub?.cancel();
    super.dispose();
  }

  void _listenToPayment() {
    _rideSub = DriverService.instance.streamRide(widget.offer.id).listen((snap) {
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null) return;

      if (data['isPaid'] == true && mounted) {
        setState(() {
          _isPaid = true;
        });
      }
    });
  }

  Future<void> _advanceStep() async {
    switch (_currentStep) {
      case ActiveRideStep.goingToClient:
        await DriverService.instance.updateRideStatus(
          rideId: widget.offer.id,
          newStatus: 'driver_arrived',
        );
        setState(() => _currentStep = ActiveRideStep.arrivedAtClient);
        break;

      case ActiveRideStep.arrivedAtClient:
        await DriverService.instance.updateRideStatus(
          rideId: widget.offer.id,
          newStatus: 'in_progress',
        );
        setState(() => _currentStep = ActiveRideStep.inProgress);
        break;

      case ActiveRideStep.inProgress:
        await DriverService.instance.updateRideStatus(
          rideId: widget.offer.id,
          newStatus: 'completed',
        );
        setState(() => _currentStep = ActiveRideStep.completed);
        _promptPayment();
        break;

      case ActiveRideStep.completed:
        Navigator.pop(context);
        break;
    }
  }

  void _promptPayment() {
    showPayCentralPaymentSheet(
      context: context,
      rideId: widget.offer.id,
      amount: finalPrice,
      departureAddress: widget.offer.from,
      destinationAddress: widget.offer.to,
    ).then((paid) {
      if (paid == true && mounted) {
        setState(() => _isPaid = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paiement PayCentral / Cash validé avec succès !'),
            backgroundColor: MooviColors.green,
          ),
        );
      }
    });
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
        return _isPaid ? 'Retour à l\'accueil' : 'Encaisser via PayCentral / Cash';
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
              points: [_pickup, _dropoff],
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
                      const Text('Passager Moovi', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
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
                    child: _action(Icons.call, 'Appeler', () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Appel du client en cours...')),
                      );
                    }),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _action(Icons.chat_bubble_outline, 'Message', () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Messagerie client ouverte')),
                      );
                    }),
                  ),
                ]),
                const SizedBox(height: 12),
                OrangeButton(
                  label: _buttonLabel,
                  icon: _currentStep == ActiveRideStep.completed ? Icons.check_circle : Icons.arrow_forward,
                  onPressed: _currentStep == ActiveRideStep.completed && !_isPaid
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
