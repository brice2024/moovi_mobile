import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:moovi/widgets/moovi_scaffold.dart';

import '../../services/driver_service.dart';
import 'wallet_widgets.dart';

/// Liste complète des opérations du portefeuille (courses et recharges).
class DriverWalletHistoryPage extends StatelessWidget {
  const DriverWalletHistoryPage({super.key, required this.driverId});

  final String driverId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MooviGradient.start,
      body: MooviGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              const MooviHeader(title: 'Historique'),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: DriverService.instance.streamWalletTransactions(driverId),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return const Center(
                        child: Text("Impossible de charger l'historique.",
                            style: TextStyle(color: Colors.white)),
                      );
                    }
                    if (!snap.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }
                    final txs = snap.data!.docs
                        .map((d) => WalletTx(d.id, d.data()))
                        .toList();
                    if (txs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: WalletEmptyCard(
                            title: 'Aucune opération pour le moment',
                            text:
                                'Vos courses et recharges Mobile Money apparaîtront ici.',
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      itemCount: txs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => txs[i].isCommission
                          ? WalletRideCard(tx: txs[i])
                          : WalletOperationCard(tx: txs[i]),
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
