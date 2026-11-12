import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/driver_service.dart';
import 'driver_theme.dart';
import 'ride_offer.dart';
import 'ride_details_page.dart';
import '../wallet/driver_wallet_page.dart';
import '../wallet/recharge_wallet_sheet.dart';

class OffersPage extends StatefulWidget {
  const OffersPage({super.key});

  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  // Coordonnées par défaut : Libreville, Gabon
  static const _libreville = LatLng(0.4162, 9.4673);

  bool _isOnline = true;
  LatLng? _driverLocation;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _initDriverLocation();
  }

  Future<void> _initDriverLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 5));
      final loc = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() => _driverLocation = loc);
        _mapController?.animateCamera(CameraUpdate.newLatLng(loc));
      }
      _syncAvailability(true, loc);
    } catch (_) {
      // Position par défaut Libreville
      _syncAvailability(true, _libreville);
    }
  }

  void _syncAvailability(bool online, LatLng? loc) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    DriverService.instance.updateDriverAvailability(
      uid: uid,
      isOnline: online,
      location: loc != null ? GeoPoint(loc.latitude, loc.longitude) : null,
    );
  }

  Future<void> _toggleOnline() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && !_isOnline) {
      // Vérifier le solde avant de passer en ligne
      final driverData = await DriverService.instance.getDriverData(uid);
      final balance = (driverData?['walletBalance'] as num?)?.toInt() ?? 5000;
      final isBlocked = driverData?['isWalletBlocked'] == true || balance < 0;

      if (isBlocked) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solde insuffisant pour couvrir les commissions. Veuillez recharger votre portefeuille.'),
            backgroundColor: Colors.red,
          ),
        );
        showRechargeWalletSheet(context: context, driverId: uid);
        return;
      }
    }

    setState(() {
      _isOnline = !_isOnline;
    });
    _syncAvailability(_isOnline, _driverLocation ?? _libreville);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isOnline ? 'Vous êtes maintenant EN LIGNE' : 'Vous êtes HORS LIGNE'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initialPos = _driverLocation ?? _libreville;

    return Scaffold(
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: initialPos, zoom: 13),
          zoomControlsEnabled: false,
          myLocationButtonEnabled: true,
          onMapCreated: (ctrl) => _mapController = ctrl,
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  GestureDetector(
                    onTap: _toggleOnline,
                    child: OnlineChip(online: _isOnline),
                  ),
                  Row(
                    children: [
                      // Solde du portefeuille PawaPay
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseAuth.instance.currentUser?.uid != null
                            ? DriverService.instance.streamDriverWallet(FirebaseAuth.instance.currentUser!.uid)
                            : null,
                        builder: (context, snap) {
                          final data = snap.data?.data() ?? {};
                          final balance = (data['walletBalance'] as num?)?.toInt() ?? 5000;
                          final isBlocked = data['isWalletBlocked'] == true || balance < 0;

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const DriverWalletPage()),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isBlocked ? Colors.red : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(.08), blurRadius: 8)],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.account_balance_wallet_rounded,
                                    size: 14,
                                    color: isBlocked ? Colors.white : MooviColors.orange,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$balance FCFA',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: isBlocked ? Colors.white : MooviColors.dark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      RoundOrangeButton(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.maybePop(context),
                      ),
                    ],
                  ),
                ]),

                // Alerte solde insuffisant
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseAuth.instance.currentUser?.uid != null
                      ? DriverService.instance.streamDriverWallet(FirebaseAuth.instance.currentUser!.uid)
                      : null,
                  builder: (context, snap) {
                    final data = snap.data?.data() ?? {};
                    final balance = (data['walletBalance'] as num?)?.toInt() ?? 5000;
                    final isBlocked = data['isWalletBlocked'] == true || balance < 0;

                    if (!isBlocked) return const SizedBox.shrink();

                    return Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.3), blurRadius: 8)],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Solde insuffisant pour commissions. Rechargez pour accepter des courses.',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              final uid = FirebaseAuth.instance.currentUser?.uid;
                              if (uid != null) {
                                showRechargeWalletSheet(context: context, driverId: uid);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Recharger',
                                style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        // BottomSheet des offres de courses
        DraggableScrollableSheet(
          initialChildSize: .72,
          minChildSize: .25,
          maxChildSize: .92,
          builder: (_, controller) {
            if (!_isOnline) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.offline_bolt_rounded, size: 48, color: MooviColors.grey),
                    const SizedBox(height: 12),
                    const Text(
                      'Vous êtes actuellement hors ligne',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Passez en ligne pour recevoir les demandes de courses au Gabon.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: MooviColors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _toggleOnline,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MooviColors.orange,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Passer en ligne'),
                    ),
                  ],
                ),
              );
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: DriverService.instance.getAvailableRidesStream(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                List<RideOffer> offers;

                if (docs.isNotEmpty) {
                  offers = docs.map((d) => RideOffer.fromFirestore(d)).toList();
                } else {
                  // Si aucune course réelle dans la base, on propose les suggestions démo Libreville
                  offers = demoOffersGabon;
                }

                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 10),
                    ],
                  ),
                  child: ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: offers.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${offers.length} Course${offers.length > 1 ? 's' : ''} disponible${offers.length > 1 ? 's' : ''}',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: MooviColors.orangeSoft,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Gabon (FCFA)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: MooviColors.orange,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final offer = offers[i - 1];
                      return OfferCard(
                        offer: offer,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => RideDetailsPage(offer: offer)),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
      ]),
    );
  }
}

class OfferCard extends StatelessWidget {
  final RideOffer offer;
  final VoidCallback? onTap;
  const OfferCard({super.key, required this.offer, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isCar = offer.type == RideType.voiture;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MooviColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 8)],
        ),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: MooviColors.bg, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(isCar ? Icons.directions_car : Icons.two_wheeler,
                    size: 12, color: MooviColors.orange),
                const SizedBox(width: 4),
                Text(isCar ? 'VOITURE' : 'MOTO',
                    style: const TextStyle(fontSize: 9, color: MooviColors.orange, fontWeight: FontWeight.w700)),
              ]),
            ),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(offer.clientPrice ? 'PRIX PASSAGER' : 'ESTIMATION',
                  style: const TextStyle(fontSize: 8, color: MooviColors.grey, fontWeight: FontWeight.w700)),
              Text('${offer.price} FCFA',
                  style: const TextStyle(fontSize: 20, color: MooviColors.orange, fontWeight: FontWeight.w800)),
            ]),
          ]),
          const SizedBox(height: 8),
          RouteLine(from: offer.from, to: offer.to),
          const SizedBox(height: 12),
          Row(children: [
            _stat('TEMPS', '${offer.minutes} min'),
            const SizedBox(width: 20),
            _stat('DISTANCE', '${offer.km} km'),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: MooviColors.orangeSoft, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.bolt_rounded, size: 14, color: MooviColors.orange),
                const SizedBox(width: 4),
                Text('Voir & Négocier',
                    style: const TextStyle(fontSize: 10, color: MooviColors.orange, fontWeight: FontWeight.w800)),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _stat(String l, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l, style: const TextStyle(fontSize: 8, color: MooviColors.grey, fontWeight: FontWeight.w600)),
        Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ]);
}
