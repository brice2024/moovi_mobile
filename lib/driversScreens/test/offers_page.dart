import '../../services/local_notifications.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/api_client.dart';
import '../../services/driver_service.dart';
import '../../services/realtime_service.dart';
import 'active_ride_page.dart';
import 'driver_theme.dart';
import 'ride_offer.dart';
import 'ride_details_page.dart';
import 'driver_profile_page.dart';
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

  bool _isOnline = false;
  bool _switching = false;
  LatLng? _driverLocation;
  GoogleMapController? _mapController;

  StreamSubscription<RealtimeEvent>? _offlineSub;
  StreamSubscription<RealtimeEvent>? _acceptedSub;
  StreamSubscription<Map<String, dynamic>>? _walletSub;

  /// Dernier état du portefeuille (un seul abonnement, fermé au dispose).
  final _wallet = ValueNotifier<Map<String, dynamic>?>(null);

  /// Flux des courses disponibles, recréé à chaque passage en ligne (un flux
  /// `liveApi` ne peut être écouté qu'une fois).
  Stream<List<Map<String, dynamic>>>? _rides;

  Stream<List<Map<String, dynamic>>> _newRidesStream() =>
      DriverService.instance.availableRidesStream(
        latitude: () => _driverLocation?.latitude,
        longitude: () => _driverLocation?.longitude,
      );

  bool _openingActiveRide = false;

  /// Offre acceptée alors que le chauffeur n'est pas sur le détail de la
  /// course : on ouvre directement la course active.
  Future<void> _onOfferAccepted(RealtimeEvent e) async {
    final ride = e.data;
    if (!mounted || _openingActiveRide) return;
    if (ride['driverId']?.toString() != _driverId || _driverId.isEmpty) return;
    if (RideDetailsPage.watchingRideId == ride['id']?.toString()) return;
    _openingActiveRide = true;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ActiveRidePage(
            offer: RideOffer.fromApi(ride),
            agreedPrice: asNum(ride['finalPrice'])?.toInt(),
            initialStatus: ride['status']?.toString(),
          ),
        ),
      );
    } finally {
      _openingActiveRide = false;
    }
  }

  @override
  void initState() {
    super.initState();
    // Le serveur peut passer le chauffeur hors ligne (signal GPS perdu,
    // dossier suspendu…) : l'interrupteur suit immédiatement.
    _offlineSub = RealtimeService.instance
        .on(const {'driver:offline', 'driver:availability_changed'})
        .where((e) =>
            e.data['isAvailable'] == false &&
            e.data['driverId']?.toString() == _driverId)
        .listen((e) {
      if (!mounted || !_isOnline || _switching) return;
      DriverService.instance.stopLocationHeartbeat();
      setState(() {
        _isOnline = false;
        _rides = null;
      });
      final blocked = e.data['reason'] == 'wallet_blocked';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: blocked ? Colors.red : null,
        content: Text(blocked
            ? 'Solde insuffisant : vous êtes HORS LIGNE. Rechargez votre portefeuille.'
            : 'Vous avez été mis HORS LIGNE (connexion perdue). Repassez en ligne pour recevoir des courses.'),
      ));
    });
    _acceptedSub = RealtimeService.instance
        .on(const {'ride:accepted'}).listen(_onOfferAccepted);
    _walletSub = DriverService.instance.streamDriverWallet().listen(
          (w) => _wallet.value = w,
          onError: (_) {},
        );
    _init();
  }

  @override
  void dispose() {
    _offlineSub?.cancel();
    _acceptedSub?.cancel();
    _walletSub?.cancel();
    _wallet.dispose();
    // Quitter l'espace chauffeur = passer hors ligne.
    DriverService.instance.stopLocationHeartbeat();
    if (_isOnline) {
      DriverService.instance
          .setAvailability(isOnline: false)
          .then((_) {}, onError: (_) {});
    }
    super.dispose();
  }

  Future<void> _init() async {
    await _initDriverLocation();
    if (!mounted) return;
    // Reprend une course déjà acceptée (application relancée en cours de course).
    try {
      final active = await DriverService.instance.getActiveRide(role: 'driver');
      if (active != null && mounted) {
        _openingActiveRide = true;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ActiveRidePage(
              offer: RideOffer.fromApi(active),
              agreedPrice: asNum(active['finalPrice'])?.toInt(),
              initialStatus: active['status']?.toString(),
            ),
          ),
        );
        _openingActiveRide = false;
      }
    } catch (_) {
      _openingActiveRide = false;
    }
    if (mounted) await _setOnline(true, silent: true);
  }

  Future<void> _initDriverLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition()
          .timeout(const Duration(seconds: 5));
      final loc = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() => _driverLocation = loc);
        _mapController?.animateCamera(CameraUpdate.newLatLng(loc));
      }
    } catch (_) {
      // Position par défaut Libreville
    }
  }

  String get _driverId =>
      DriverService.instance.cachedDriver?['id']?.toString() ?? '';

  /// Passe en ligne / hors ligne via l'API. Le serveur refuse le passage en
  /// ligne si le portefeuille est bloqué ou si le dossier n'est pas validé.
  Future<void> _setOnline(bool online, {bool silent = false}) async {
    if (_switching) return;
    setState(() => _switching = true);
    final loc = _driverLocation ?? _libreville;
    try {
      // Notifications système : nouvelles courses reçues en arrière-plan.
      if (online) await LocalNotifications.instance.requestPermission();
      await DriverService.instance.setAvailability(
        isOnline: online,
        latitude: loc.latitude,
        longitude: loc.longitude,
      );
      if (!mounted) {
        // L'espace chauffeur a été quitté pendant la requête.
        if (online) {
          DriverService.instance.stopLocationHeartbeat();
          DriverService.instance
              .setAvailability(isOnline: false)
              .then((_) {}, onError: (_) {});
        }
        return;
      }
      setState(() {
        _isOnline = online;
        _rides = online ? _newRidesStream() : null;
      });
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(online
                ? 'Vous êtes maintenant EN LIGNE'
                : 'Vous êtes HORS LIGNE'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on ApiException catch (e) {
      DriverService.instance.stopLocationHeartbeat();
      if (!mounted) return;
      setState(() {
        _isOnline = false;
        _rides = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
      if (e.code == 'WALLET_BLOCKED') {
        showRechargeWalletSheet(context: context, driverId: _driverId);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _toggleOnline() => _setOnline(!_isOnline);

  Widget _walletBuilder(Widget Function(int balance, bool isBlocked) child) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: _wallet,
      builder: (context, data, _) {
        if (data == null) return child(0, false);
        final balance = asNum(data['walletBalance'])?.toInt() ?? 0;
        final isBlocked = data['isWalletBlocked'] == true || balance < 0;
        return child(balance, isBlocked);
      },
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
          myLocationEnabled: true,
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
                    onTap: _switching ? null : _toggleOnline,
                    child: OnlineChip(online: _isOnline),
                  ),
                  Row(
                    children: [
                      // Solde du portefeuille PawaPay
                      _walletBuilder((balance, isBlocked) {
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const DriverWalletPage()),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isBlocked ? Colors.red : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(.08),
                                    blurRadius: 8)
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.account_balance_wallet_rounded,
                                  size: 14,
                                  color: isBlocked
                                      ? Colors.white
                                      : MooviColors.orange,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$balance FCFA',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: isBlocked
                                        ? Colors.white
                                        : MooviColors.dark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      RoundOrangeButton(
                        icon: Icons.person_outline,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const DriverProfilePage()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      RoundOrangeButton(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.maybePop(context),
                      ),
                    ],
                  ),
                ]),

                // Alerte solde insuffisant
                _walletBuilder((balance, isBlocked) {
                  if (!isBlocked) return const SizedBox.shrink();

                  return Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.red.withOpacity(0.3), blurRadius: 8)
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Solde insuffisant pour commissions. Rechargez pour accepter des courses.',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => showRechargeWalletSheet(
                              context: context, driverId: _driverId),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Recharger',
                              style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
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
                child: ListView(
                  controller: controller,
                  children: [
                    const SizedBox(height: 24),
                    const Icon(Icons.offline_bolt_rounded,
                        size: 48, color: MooviColors.grey),
                    const SizedBox(height: 12),
                    const Text(
                      'Vous êtes actuellement hors ligne',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Passez en ligne pour recevoir les demandes de courses au Gabon.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: MooviColors.grey),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: ElevatedButton(
                        onPressed: _switching ? null : _toggleOnline,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MooviColors.orange,
                          foregroundColor: Colors.white,
                        ),
                        child:
                            Text(_switching ? 'Connexion…' : 'Passer en ligne'),
                      ),
                    ),
                  ],
                ),
              );
            }

            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: _rides ??= _newRidesStream(),
              builder: (context, snapshot) {
                final offers = (snapshot.data ?? const <Map<String, dynamic>>[])
                    .map(RideOffer.fromApi)
                    .toList();

                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${offers.length} Course${offers.length > 1 ? 's' : ''} disponible${offers.length > 1 ? 's' : ''}',
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
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
                              if (snapshot.hasError && !snapshot.hasData) ...[
                                const SizedBox(height: 12),
                                Text(errorMessage(snapshot.error!),
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.red)),
                              ] else if (offers.isEmpty) ...[
                                const SizedBox(height: 24),
                                const Center(
                                  child: Text(
                                    'Aucune demande de course à proximité pour le moment.\nLa liste se met à jour automatiquement.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 12, color: MooviColors.grey),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }

                      final offer = offers[i - 1];
                      return OfferCard(
                        offer: offer,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => RideDetailsPage(offer: offer)),
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
                Text(offer.rideTypeName.toUpperCase(),
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
