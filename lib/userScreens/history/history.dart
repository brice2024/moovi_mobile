import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:moovi/driversScreens/wallet/moovi_format.dart';
import 'package:moovi/widgets/moovi_scaffold.dart';

import '../../widgets/UserbottomNavBar.dart';
import '../settings/settings_widgets.dart';

/// Onglet « HISTORIQUE » : courses du client (`users/{uid}/rides`).
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: MooviGradient.start,
      body: MooviGradientBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const MooviHeader(title: 'Historique des courses', showBack: false),
              Expanded(
                child: user == null
                    ? const _Info(
                        icon: Icons.lock_outline_rounded,
                        title: 'Veuillez vous connecter pour voir vos courses.',
                      )
                    : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .collection('rides')
                            .orderBy('createdAt', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return const _Info(
                              icon: Icons.error_outline_rounded,
                              title: "Impossible de charger l'historique",
                              text: 'Vérifiez votre connexion et réessayez.',
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            );
                          }

                          final docs = snapshot.data!.docs;
                          if (docs.isEmpty) {
                            return const _Info(
                              icon: Icons.history_toggle_off_rounded,
                              title: 'Aucune course effectuée',
                              text: 'Vos prochains trajets au Gabon apparaîtront ici.',
                            );
                          }

                          return ListView.separated(
                            padding: EdgeInsets.fromLTRB(
                                20, 4, 20, mooviNavBarInset(context)),
                            itemCount: docs.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, i) => _RideCard(data: docs[i].data()),
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

(String, Color) _statusOf(Map<String, dynamic> d) {
  if (d['isPaid'] == true) {
    final cash = d['paymentMethod'] == 'cash';
    return ('PAYÉ · ${cash ? 'ESPÈCES' : 'MOBILE MONEY'}', const Color(0xFF1FA45B));
  }
  return switch (d['status']?.toString()) {
    'searching' => ('EN RECHERCHE', MooviGradient.end),
    'accepted' => ('ACCEPTÉE', MooviGradient.end),
    'driver_arrived' => ('CHAUFFEUR ARRIVÉ', MooviGradient.end),
    'in_progress' => ('EN COURS', MooviGradient.end),
    'completed' => ('TERMINÉE', const Color(0xFF1FA45B)),
    'cancelled' => ('ANNULÉE', const Color(0xFFC62828)),
    _ => ('EN ATTENTE', MooviGradient.end),
  };
}

class _RideCard extends StatelessWidget {
  const _RideCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final from = data['departureAddress']?.toString() ?? 'Point de départ';
    final to = data['destinationAddress']?.toString() ?? 'Destination';
    final price = (data['paidAmount'] as num?) ??
        (data['agreedPrice'] as num?) ??
        (data['price'] as num?) ??
        0;
    final (status, statusColor) = _statusOf(data);

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
              SettingsIconBox(
                icon: data['rideType'] == 'moto'
                    ? Icons.two_wheeler_rounded
                    : Icons.directions_car_rounded,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatFcfa(price),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: MooviGradient.brownCard,
                      ),
                    ),
                    Text(
                      formatRelativeDate(asDate(data['createdAt'])),
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w600,
                        color: kMooviInk.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Place(icon: Icons.radio_button_checked_rounded, text: from),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Container(
                width: 1.5, height: 10, color: kMooviInk.withValues(alpha: 0.25)),
          ),
          _Place(icon: Icons.location_on_rounded, text: to),
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

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.title, this.text});
  final IconData icon;
  final String title;
  final String? text;

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
            if (text != null) ...[
              const SizedBox(height: 6),
              Text(
                text!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
