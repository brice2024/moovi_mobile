import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../services/driver_service.dart';
import '../test/driver_theme.dart';
import 'recharge_wallet_sheet.dart';

class DriverWalletPage extends StatefulWidget {
  const DriverWalletPage({super.key});

  @override
  State<DriverWalletPage> createState() => _DriverWalletPageState();
}

class _DriverWalletPageState extends State<DriverWalletPage> {
  // Solde + transactions depuis l'API (actualisés automatiquement).
  late final Stream<Map<String, dynamic>> _wallet =
      DriverService.instance.streamDriverWallet();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MooviColors.dark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Mon Portefeuille Moovi',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: MooviColors.dark,
          ),
        ),
        centerTitle: false,
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _wallet,
        builder: (context, snapshot) {
          if (snapshot.hasError && !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(errorMessage(snapshot.error!), textAlign: TextAlign.center),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: MooviColors.orange));
          }
          final data = snapshot.data!;
          final int balance = asNum(data['walletBalance'])?.toInt() ?? 0;
          final bool isBlocked = data['isWalletBlocked'] == true || balance < 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // CARTE PRINCIPALE DU SOLDE
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isBlocked
                          ? [const Color(0xFFC62828), const Color(0xFFE53935)]
                          : [const Color(0xFF1B1B1F), const Color(0xFF2C2C34)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: (isBlocked ? Colors.red : Colors.black).withOpacity(0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'SOLDE DISPONIBLE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white70,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isBlocked
                                  ? Colors.white.withOpacity(0.2)
                                  : MooviColors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isBlocked ? Icons.warning_amber_rounded : Icons.check_circle,
                                  size: 13,
                                  color: isBlocked ? Colors.white : MooviColors.green,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  isBlocked ? 'SOLDE INSUFFISANT' : 'COMPTE ACTIF',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: isBlocked ? Colors.white : MooviColors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '$balance FCFA',
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isBlocked
                          ? 'Votre solde ne couvre plus les commissions. Rechargez pour continuer à recevoir des courses.'
                          : 'Ce solde couvre automatiquement les commissions Moovi (15%) sur vos courses en cash.',
                        style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.3),
                      ),
                      const SizedBox(height: 18),

                      // Bouton Recharger
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => showRechargeWalletSheet(
                            context: context,
                            driverId: data['driverId']?.toString() ?? '',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: MooviColors.orange,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_card_rounded, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Recharger mon compte',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // RÈGLES DES COMMISSIONS MOOVI
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: MooviColors.orangeSoft,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: MooviColors.orange.withOpacity(0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: MooviColors.orange, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Fonctionnement des commissions Moovi',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: MooviColors.dark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '• Les passagers vous règlent 100% en Espèces (Cash).\n'
                              '• La commission plateforme (15%) est prélevée de ce portefeuille.\n'
                              '• Si votre solde passe sous 0 FCFA, votre compte est temporairement mis hors-ligne jusqu\'à la recharge.',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.45,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // HISTORIQUE DES TRANSACTIONS
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Historique des opérations',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: MooviColors.dark,
                      ),
                    ),
                    Text(
                      'Automatisé PawaPay',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Builder(
                  builder: (context) {
                    final txDocs = (data['transactions'] as List? ?? const [])
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();

                    if (txDocs.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.receipt_long_rounded, size: 40, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            const Text(
                              'Aucune opération pour le moment',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Vos recharges Mobile Money et commissions apparaîtront ici.',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: txDocs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final tx = txDocs[index];
                        final isDeposit = tx['type'] == 'deposit' || tx['type'] == 'promo_subsidy';
                        final isPending = tx['status'] == 'pending';
                        final isFailed = tx['status'] == 'failed';
                        final amount = asNum(tx['amount'])?.toInt() ?? 0;
                        final desc = tx['description']?.toString() ??
                            (isDeposit ? 'Recharge Mobile Money' : 'Commission de course');
                        final date = asDate(tx['createdAt']);
                        final dateFormatted = date != null
                            ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} à ${date.hour}h${date.minute.toString().padLeft(2, '0')}'
                            : 'Récemment';

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: isDeposit
                                      ? MooviColors.green.withOpacity(0.12)
                                      : MooviColors.orange.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isDeposit ? Icons.arrow_downward_rounded : Icons.percent_rounded,
                                  color: isDeposit ? MooviColors.green : MooviColors.orange,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      desc,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: MooviColors.dark,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isPending
                                          ? '$dateFormatted • En attente de validation'
                                          : isFailed
                                              ? '$dateFormatted • Échoué'
                                              : dateFormatted,
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${isDeposit ? '+' : ''}$amount FCFA',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: isDeposit ? MooviColors.green : Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

