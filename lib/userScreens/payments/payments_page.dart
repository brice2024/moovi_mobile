import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:moovi/driversScreens/wallet/moovi_format.dart';
import 'package:moovi/widgets/moovi_scaffold.dart';

import '../../widgets/UserbottomNavBar.dart';
import '../settings/settings_widgets.dart';

/// Onglet « WALLET » côté client : liste des courses payées
/// (`users/{uid}/rides` où `isPaid == true`).
class PaymentsPage extends StatelessWidget {
  const PaymentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: MooviGradient.start,
      body: MooviGradientBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const MooviHeader(title: 'Mes paiements', showBack: false),
              Expanded(
                child: uid == null
                    ? const Center(
                        child: Text('Vous devez être connecté.',
                            style: TextStyle(color: Colors.white)),
                      )
                    : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        // Filtre simple (pas d'index composite) ; tri côté client.
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .collection('rides')
                            .where('isPaid', isEqualTo: true)
                            .snapshots(),
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return const _Empty(
                              icon: Icons.error_outline_rounded,
                              title: 'Impossible de charger vos paiements',
                              text: 'Vérifiez votre connexion et réessayez.',
                            );
                          }
                          if (!snap.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            );
                          }
                          final docs = [...snap.data!.docs];
                          DateTime dateOf(Map<String, dynamic> d) =>
                              asDate(d['paidAt']) ??
                              asDate(d['createdAt']) ??
                              DateTime.fromMillisecondsSinceEpoch(0);
                          docs.sort((a, b) =>
                              dateOf(b.data()).compareTo(dateOf(a.data())));

                          if (docs.isEmpty) {
                            return const _Empty(
                              icon: Icons.receipt_long_rounded,
                              title: 'Aucun paiement pour le moment',
                              text:
                                  'Les courses que vous avez réglées apparaîtront ici.',
                            );
                          }

                          final total = docs.fold<num>(
                              0, (acc, d) => acc + _amountOf(d.data()));

                          return ListView(
                            padding: EdgeInsets.fromLTRB(
                                20, 4, 20, mooviNavBarInset(context)),
                            children: [
                              _TotalCard(total: total, count: docs.length),
                              const SizedBox(height: 22),
                              const Text(
                                'Historique',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 12),
                              for (final d in docs) ...[
                                _PaymentCard(data: d.data(), date: dateOf(d.data())),
                                const SizedBox(height: 12),
                              ],
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

num _amountOf(Map<String, dynamic> d) =>
    (d['paidAmount'] as num?) ?? (d['agreedPrice'] as num?) ?? (d['price'] as num?) ?? 0;

(String, IconData) _methodOf(Map<String, dynamic> d) {
  final method = d['paymentMethod']?.toString();
  final provider = d['paymentProvider']?.toString();
  if (method == 'cash') return ('Espèces', Icons.payments_rounded);
  final label = switch (provider) {
    'airtel' => 'Airtel Money',
    'moov' => 'Moov Money',
    _ => 'Mobile Money',
  };
  return (label, Icons.phone_android_rounded);
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.total, required this.count});
  final num total;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MooviGradient.brownCard,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total dépensé',
                    style: TextStyle(fontSize: 13, color: Color(0xD9FFFFFF))),
                const SizedBox(height: 4),
                Text(
                  formatFcfa(total),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count course${count > 1 ? 's' : ''} payée${count > 1 ? 's' : ''}',
                  style: const TextStyle(fontSize: 12, color: Color(0xD9FFFFFF)),
                ),
              ],
            ),
          ),
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded,
                color: Colors.white, size: 26),
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.data, required this.date});
  final Map<String, dynamic> data;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final from = data['departureAddress']?.toString() ?? 'Point de départ';
    final to = data['destinationAddress']?.toString() ?? 'Destination';
    final (method, methodIcon) = _methodOf(data);
    final hasDate = date.millisecondsSinceEpoch > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MooviGradient.cardStrong,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SettingsIconBox(icon: Icons.directions_car_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  formatRelativeDate(hasDate ? date : null),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                    color: kMooviInk.withValues(alpha: 0.7),
                  ),
                ),
              ),
              Text(
                formatFcfa(_amountOf(data)),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: MooviGradient.brownCard,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Place(icon: Icons.radio_button_checked_rounded, text: from),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Container(width: 1.5, height: 10, color: kMooviInk.withValues(alpha: 0.25)),
          ),
          _Place(icon: Icons.location_on_rounded, text: to),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF0E0D0)),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(methodIcon, size: 16, color: MooviGradient.end),
              const SizedBox(width: 6),
              Text(
                method,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: kMooviInk,
                ),
              ),
              const Spacer(),
              const Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF1FA45B)),
              const SizedBox(width: 4),
              const Text(
                'PAYÉ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1FA45B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Place extends StatelessWidget {
  const _Place({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: MooviGradient.end),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: kMooviInk,
            ),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(32, 0, 32, mooviNavBarInset(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
