import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/api_client.dart';
import '../../services/driver_service.dart';
import '../../services/session.dart';
import 'driver_theme.dart';
import 'ride_offer.dart';
import 'negotiate_price_page.dart';
import 'active_ride_page.dart';

class RideDetailsPage extends StatefulWidget {
  final RideOffer offer;
  const RideDetailsPage({super.key, required this.offer});

  /// Course dont le détail est affiché : c'est cette page (et non la liste)
  /// qui ouvre la course active quand l'offre est acceptée.
  static String? watchingRideId;

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
    RideDetailsPage.watchingRideId = widget.offer.id;
    _listenToRideStatus();
  }

  @override
  void dispose() {
    if (RideDetailsPage.watchingRideId == widget.offer.id) {
      RideDetailsPage.watchingRideId = null;
    }
    _rideSubscription?.cancel();
    super.dispose();
  }

  /// Identifiant du profil chauffeur (`drivers.id`) : c'est lui que l'API
  /// renseigne dans `ride.driverId`, pas l'identifiant utilisateur.
  String? get _myDriverId =>
      DriverService.instance.cachedDriver?['id']?.toString() ??
      AppSession.instance.currentUser?.driverId;

  void _listenToRideStatus() {
    _rideSubscription =
        DriverService.instance.streamRide(widget.offer.id).listen((data) {
      if (!mounted) return;
      final status = data['status']?.toString();
      final driverId = data['driverId']?.toString();

      // Si le client a accepté notre offre, on ouvre l'écran de course active !
      if (status == 'accepted' && driverId != null && driverId == _myDriverId) {
        _rideSubscription?.cancel();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ActiveRidePage(
              offer: widget.offer,
              agreedPrice: asNum(data['agreedPrice'])?.toInt() ?? widget.offer.price,
              initialStatus: status,
            ),
          ),
        );
        return;
      }

      // Course attribuée à un autre chauffeur, annulée ou expirée.
      if (status != null && status != 'searching') {
        _rideSubscription?.cancel();
        final message = switch (status) {
          'cancelled' => 'Le passager a annulé cette course.',
          'expired' => 'Cette demande de course a expiré.',
          _ => 'Cette course a été attribuée à un autre chauffeur.',
        };
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        Navigator.maybePop(context);
      }
    }, onError: (_) {});
  }

  Future<void> _submitOffer(int price) async {
    setState(() => _isSending = true);
    try {
      // Nom, véhicule, plaque, note et photo sont renseignés par l'API.
      await DriverService.instance.sendDriverOffer(
        rideId: widget.offer.id,
        price: price,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage(e)), backgroundColor: Colors.red),
      );
      return;
    }

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
