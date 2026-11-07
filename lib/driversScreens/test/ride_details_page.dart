import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/driver_service.dart';
import 'driver_theme.dart';
import 'ride_offer.dart';
import 'negotiate_price_page.dart';
import 'active_ride_page.dart';

class RideDetailsPage extends StatefulWidget {
  final RideOffer offer;
  const RideDetailsPage({super.key, required this.offer});

  @override
  State<RideDetailsPage> createState() => _RideDetailsPageState();
}

class _RideDetailsPageState extends State<RideDetailsPage> {
  StreamSubscription? _rideSubscription;
  bool _isSending = false;
  bool _offerSent = false;
  int? _sentPrice;

  @override
  void initState() {
    super.initState();
    _listenToRideStatus();
  }

  @override
  void dispose() {
    _rideSubscription?.cancel();
    super.dispose();
  }

  void _listenToRideStatus() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _rideSubscription = DriverService.instance.streamRide(widget.offer.id).listen((snap) {
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null) return;

      final status = data['status'];
      final driverId = data['driverId'];

      // Si le client a accepté notre offre, on ouvre l'écran de course active !
      if (status == 'accepted' && driverId == uid && mounted) {
        _rideSubscription?.cancel();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ActiveRidePage(
              offer: widget.offer,
              agreedPrice: (data['agreedPrice'] as num?)?.toInt() ?? widget.offer.price,
            ),
          ),
        );
      }
    });
  }

  Future<void> _submitOffer(int price) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez vous connecter')),
      );
      return;
    }

    setState(() => _isSending = true);

    final driverData = await DriverService.instance.getDriverData(user.uid);
    final car = driverData?['car'] as Map<String, dynamic>?;
    final carDesc = car != null ? '${car['brand']} ${car['model']}' : 'Véhicule';
    final plate = car != null ? '${car['plate']}' : '';

    await DriverService.instance.sendDriverOffer(
      rideId: widget.offer.id,
      driverId: user.uid,
      driverName: user.displayName ?? 'Chauffeur Moovi',
      rating: 4.8,
      carModel: carDesc,
      plate: plate,
      price: price,
      arrivalMinutes: 5,
      photoUrl: user.photoURL,
    );

    if (!mounted) return;
    setState(() {
      _isSending = false;
      _offerSent = true;
      _sentPrice = price;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Proposition envoyée au client ($price FCFA) ! En attente de validation...'),
        backgroundColor: MooviColors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final targetPos = widget.offer.departureLocation ?? const LatLng(0.4162, 9.4673);

    return Scaffold(
      backgroundColor: MooviColors.bg,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: Column(children: [
                  Row(children: [
                    GestureDetector(
                        onTap: () => Navigator.pop(context), child: const Icon(Icons.arrow_back, size: 20)),
                    const SizedBox(width: 8),
                    const Text('Détails de la course',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IdTag(widget.offer.id.substring(0, widget.offer.id.length.clamp(0, 6))),
                  ]),
                  const SizedBox(height: 14),
                  _priceCard(),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 120,
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(target: targetPos, zoom: 13),
                        liteModeEnabled: true,
                        zoomControlsEnabled: false,
                        myLocationButtonEnabled: false,
                        markers: {
                          Marker(
                            markerId: const MarkerId('pickup'),
                            position: targetPos,
                          ),
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  RouteLine(from: widget.offer.from, to: widget.offer.to),
                  const SizedBox(height: 14),
                  _statsBox(),
                  if (_offerSent) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: MooviColors.orangeSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: MooviColors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: MooviColors.orange),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Offre de $_sentPrice FCFA soumise. Vous serez redirigé automatiquement dès l\'acceptation du client.',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MooviColors.dark),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _offerSent
                ? OrangeButton(
                    label: 'Attente confirmation client...',
                    onPressed: null,
                  )
                : Row(children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Refuser', style: TextStyle(color: MooviColors.grey)),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton(
                        onPressed: _isSending
                            ? null
                            : () async {
                                final int? proposedPrice = await showModalBottomSheet<int>(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  barrierColor: Colors.black.withOpacity(0.25),
                                  useSafeArea: true,
                                  builder: (context) => NegotiatePriceSheet(offer: widget.offer),
                                );

                                if (proposedPrice != null) {
                                  _submitOffer(proposedPrice);
                                }
                              },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: MooviColors.orange,
                          side: const BorderSide(color: MooviColors.orange),
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Négocier', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _isSending ? null : () => _submitOffer(widget.offer.price),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MooviColors.orange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isSending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Accepter', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
          ),
        ]),
      ),
    );
  }

  Widget _priceCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MooviColors.border),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${widget.offer.price}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            const Padding(
              padding: EdgeInsets.only(bottom: 5),
              child: Text('FCFA', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MooviColors.orange)),
            ),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: MooviColors.orange, borderRadius: BorderRadius.circular(20)),
            child: Text('Prix proposé par le passager (Gabon)',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _mini(Icons.straighten, '${widget.offer.km} km', 'DISTANCE'),
            _mini(Icons.schedule, '${widget.offer.minutes} min', 'DURÉE ESTIMÉE'),
          ]),
        ]),
      );

  Widget _mini(IconData i, String v, String l) => Column(children: [
        Row(children: [
          Icon(i, size: 14, color: MooviColors.orange),
          const SizedBox(width: 4),
          Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
        Text(l, style: const TextStyle(fontSize: 8, color: MooviColors.grey)),
      ]);

  Widget _statsBox() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: MooviColors.bg, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _cell('PRISE EN CHARGE', '${widget.offer.clientDistanceKm} km'),
          _cell('TOTAL PARCOURS', '${widget.offer.totalKm.toStringAsFixed(0)} km'),
          _cell('DURÉE TOTALE', '${widget.offer.rideMinutes} min'),
        ]),
      );

  Widget _cell(String l, String v) => Column(children: [
        Text(l, style: const TextStyle(fontSize: 7, color: MooviColors.grey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      ]);
}
