import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/driver_service.dart';
import '../../widgets/moovi_scaffold.dart';
import 'ride_style.dart';

/// Commission prélevée par la plateforme (voir kMooviCommissionRate).
const double kPlatformCommissionRate = kMooviCommissionRate;

/// Fin de course (maquette 16) : récapitulatif, montant à payer au chauffeur,
/// mode de paiement, confirmation quand le chauffeur valide l'encaissement.
///
/// Se ferme avec « Accueil » (pop) : la carte d'accueil se réinitialise.
class RideCompletedPage extends StatefulWidget {
  const RideCompletedPage({
    super.key,
    required this.rideId,
    required this.amount,
    required this.from,
    required this.to,
    this.distanceText = '',
    this.durationText = '',
  });

  final String rideId;
  final int amount;
  final String from;
  final String to;
  final String distanceText;
  final String durationText;

  @override
  State<RideCompletedPage> createState() => _RideCompletedPageState();
}

class _RideCompletedPageState extends State<RideCompletedPage> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  bool _isPaid = false;
  int? _paidAmount;
  String? _paymentMethod;

  @override
  void initState() {
    super.initState();
    _sub = DriverService.instance.streamRide(widget.rideId).listen((snap) {
      final data = snap.data();
      if (data == null || !mounted) return;
      setState(() {
        _isPaid = data['isPaid'] == true;
        _paidAmount = (data['paidAmount'] as num?)?.toInt() ??
            (data['agreedPrice'] as num?)?.toInt();
        _paymentMethod = data['paymentMethod']?.toString();
      });
    }, onError: (e) => debugPrint('Paiement course : $e'));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _goHome() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final amount = _paidAmount ?? widget.amount;

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 4),
              const Text(
                'MOOVI',
                style: TextStyle(
                  color: RideColors.orange,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Row(
                  children: [
                    Material(
                      color: RideColors.orange,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _goHome,
                        child: const SizedBox(
                          width: 34,
                          height: 34,
                          child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'Fin de la course',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: RideColors.brown,
                        ),
                      ),
                    ),
                    const SizedBox(width: 34),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 10, 28, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(
                        from: widget.from,
                        to: widget.to,
                        distanceText: widget.distanceText,
                        durationText: widget.durationText,
                      ),
                      const SizedBox(height: 18),
                      _AmountCard(amount: amount),
                      const SizedBox(height: 24),
                      _PaymentMethodCard(
                        method: _paymentMethod,
                        selected: true,
                      ),
                      const SizedBox(height: 24),
                      _isPaid ? const _PaidBanner() : const _WaitingBanner(),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Commission plateforme : ${(kPlatformCommissionRate * 100).round()} %',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
                child: SizedBox(
                  width: 150,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _goHome,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RideColors.dark,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Accueil',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.from,
    required this.to,
    required this.distanceText,
    required this.durationText,
  });

  final String from;
  final String to;
  final String distanceText;
  final String durationText;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFC57A), MooviGradient.end, MooviGradient.start],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Illustration : silhouette de ville sur le dégradé.
          Positioned(
            left: -10,
            right: -10,
            top: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final s in const [64.0, 92.0, 76.0, 110.0, 70.0, 88.0])
                  Icon(
                    Icons.location_city_rounded,
                    size: s,
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 18,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: RideColors.orange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.route_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ITINÉRAIRE',
                          style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w600,
                            color: RideColors.brownLabel,
                          ),
                        ),
                        Text(
                          '${shortAddress(from)} → ${shortAddress(to)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: RideColors.brown,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (distanceText.isNotEmpty)
                        Text(
                          distanceText,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: RideColors.brownMid,
                          ),
                        ),
                      if (durationText.isNotEmpty)
                        Text(
                          durationText,
                          style: const TextStyle(fontSize: 11, color: RideColors.brownLabel),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({required this.amount});
  final int amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      decoration: BoxDecoration(
        color: RideColors.cream,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          const Text(
            'Montant à payer au chauffeur',
            style: TextStyle(fontSize: 15, color: RideColors.brownMid),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatFcfa(amount),
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  color: RideColors.brown,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'FCFA',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: RideColors.brownMid,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({required this.method, required this.selected});

  /// Valeur de `paymentMethod` sur la course (null tant que non réglée).
  final String? method;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final isMobileMoney = method != null && method != 'cash';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFF1E6DA), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD60A),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isMobileMoney ? Icons.phone_iphone_rounded : Icons.payments_outlined,
              color: RideColors.brown,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMobileMoney ? 'Paiement Mobile Money' : 'Paiement en espèces',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: RideColors.brown,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isMobileMoney
                      ? 'Réglé depuis votre téléphone'
                      : 'Réglez directement le chauffeur',
                  style: const TextStyle(fontSize: 13, color: RideColors.brownMid),
                ),
              ],
            ),
          ),
          if (selected)
            Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: RideColors.brownMid,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 15),
            ),
        ],
      ),
    );
  }
}

class _PaidBanner extends StatelessWidget {
  const _PaidBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: RideColors.cream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD9B8)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: RideColors.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_rounded, color: RideColors.success, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paiement confirmé',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: RideColors.brown,
                  ),
                ),
                Text(
                  'Merci pour votre course',
                  style: TextStyle(fontSize: 12, color: RideColors.brownMid),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingBanner extends StatelessWidget {
  const _WaitingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: RideColors.creamLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD9B8)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Padding(
              padding: EdgeInsets.all(7),
              child: CircularProgressIndicator(strokeWidth: 2.4, color: RideColors.orange),
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'En attente de confirmation',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: RideColors.brown,
                  ),
                ),
                Text(
                  'Le chauffeur confirme la réception du paiement.',
                  style: TextStyle(fontSize: 12, color: RideColors.brownMid),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
