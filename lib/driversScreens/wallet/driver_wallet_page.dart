import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:moovi/widgets/moovi_scaffold.dart';

import '../../services/driver_service.dart';
import '../../widgets/UserbottomNavBar.dart';
import 'driver_wallet_history_page.dart';
import 'moovi_format.dart';
import 'recharge_wallet_sheet.dart';
import 'wallet_widgets.dart';

/// Période du graphique des gains.
enum WalletPeriod {
  week('Semaine'),
  month('Mois'),
  year('Année');

  const WalletPeriod(this.label);
  final String label;
}

/// « Mon Wallet » du chauffeur (maquette 20).
/// Source : `drivers/{uid}.walletBalance` et `drivers/{uid}/wallet_transactions`.
class DriverWalletPage extends StatefulWidget {
  const DriverWalletPage({super.key, this.embedded = false});

  /// true quand la page est affichée dans l'onglet « WALLET » (barre du bas).
  final bool embedded;

  @override
  State<DriverWalletPage> createState() => _DriverWalletPageState();
}

class _DriverWalletPageState extends State<DriverWalletPage> {
  WalletPeriod _period = WalletPeriod.week;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: MooviGradient.start,
      body: MooviGradientBackground(
        child: SafeArea(
          bottom: !widget.embedded,
          child: Column(
            children: [
              if (widget.embedded)
                const _CenteredTitle('Mon Wallet')
              else
                const MooviHeader(title: 'Mon Wallet'),
              Expanded(
                child: uid == null
                    ? const Center(
                        child: Text(
                          'Veuillez vous connecter pour voir votre portefeuille.',
                          style: TextStyle(color: Colors.white),
                        ),
                      )
                    : _buildContent(uid),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(String uid) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: DriverService.instance.streamDriverWallet(uid),
      builder: (context, driverSnap) {
        final data = driverSnap.data?.data() ?? const {};
        // Même valeur par défaut que DriverService.deductRideCommission.
        final balance = (data['walletBalance'] as num?)?.toInt() ?? 5000;
        final blocked = data['isWalletBlocked'] == true || balance < 0;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: DriverService.instance.streamWalletTransactions(uid),
          builder: (context, txSnap) {
            final txs = (txSnap.data?.docs ?? const [])
                .map((d) => WalletTx(d.id, d.data()))
                .toList();
            final rides = txs.where((t) => t.isCommission).toList();

            return ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                widget.embedded ? mooviNavBarInset(context) : 24,
              ),
              children: [
                _BalanceHeader(
                  balance: balance,
                  period: _period,
                  onPeriodChanged: (p) => setState(() => _period = p),
                ),
                const SizedBox(height: 10),
                _RechargeRow(driverId: uid, blocked: blocked),
                const SizedBox(height: 18),
                SizedBox(
                  height: 230,
                  child: _EarningsChart(rides: rides, period: _period),
                ),
                const SizedBox(height: 22),
                const _CommissionCard(),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Historique',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DriverWalletHistoryPage(driverId: uid),
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white.withValues(alpha: 0.85),
                      ),
                      child: const Text('Voir tout',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (txSnap.hasError)
                  const WalletEmptyCard(
                    title: "Impossible de charger l'historique",
                    text: 'Vérifiez votre connexion et réessayez.',
                  )
                else if (!txSnap.hasData)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  )
                else if (rides.isEmpty)
                  const WalletEmptyCard(
                    title: 'Aucune course pour le moment',
                    text: 'Vos gains apparaîtront ici après chaque course.',
                  )
                else
                  for (final tx in rides.take(3)) ...[
                    WalletRideCard(tx: tx),
                    const SizedBox(height: 14),
                  ],
              ],
            );
          },
        );
      },
    );
  }
}

class _CenteredTitle extends StatelessWidget {
  const _CenteredTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          const Text(
            'MOOVI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Solde + sélecteur de période
// -----------------------------------------------------------------------------

class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({
    required this.balance,
    required this.period,
    required this.onPeriodChanged,
  });

  final int balance;
  final WalletPeriod period;
  final ValueChanged<WalletPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Solde total',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatFcfa(balance),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        PopupMenuButton<WalletPeriod>(
          initialValue: period,
          onSelected: onPeriodChanged,
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          itemBuilder: (_) => [
            for (final p in WalletPeriod.values)
              PopupMenuItem(value: p, child: Text(p.label)),
          ],
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  period.label,
                  style: const TextStyle(fontSize: 14, color: kWalletInk),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 20, color: kWalletInk),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RechargeRow extends StatelessWidget {
  const _RechargeRow({required this.driverId, required this.blocked});
  final String driverId;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (blocked) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE1DE),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFC62828)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Solde insuffisant : rechargez pour continuer à recevoir des courses.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF8E1B1B)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          height: 40,
          child: ElevatedButton.icon(
            onPressed: () =>
                showRechargeWalletSheet(context: context, driverId: driverId),
            icon: const Icon(Icons.add_card_rounded, size: 18),
            label: const Text(
              'Recharger mon compte',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: MooviGradient.end,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: const StadiumBorder(),
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Graphique des gains nets
// -----------------------------------------------------------------------------

class _Bucket {
  _Bucket(this.label);
  final String label;
  double value = 0;
}

const _weekDays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const _months = [
  'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin',
  'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc',
];

/// Découpe la période courante en sous-périodes et y cumule les gains nets.
/// Retourne les seaux et l'index de la sous-période en cours.
(List<_Bucket>, int) _buildBuckets(List<WalletTx> rides, WalletPeriod period) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  late final List<_Bucket> buckets;
  late final int current;
  late final int? Function(DateTime d) indexOf;

  switch (period) {
    case WalletPeriod.week:
      final monday = today.subtract(Duration(days: today.weekday - 1));
      buckets = [for (final d in _weekDays) _Bucket(d)];
      current = today.weekday - 1;
      indexOf = (d) {
        final i = DateTime(d.year, d.month, d.day).difference(monday).inDays;
        return i >= 0 && i < 7 ? i : null;
      };
    case WalletPeriod.month:
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final count = (daysInMonth - 1) ~/ 7 + 1;
      buckets = [for (var i = 1; i <= count; i++) _Bucket('S$i')];
      current = (now.day - 1) ~/ 7;
      indexOf = (d) => d.year == now.year && d.month == now.month
          ? (d.day - 1) ~/ 7
          : null;
    case WalletPeriod.year:
      buckets = [for (final m in _months) _Bucket(m)];
      current = now.month - 1;
      indexOf = (d) => d.year == now.year ? d.month - 1 : null;
  }

  for (final tx in rides) {
    final net = tx.net;
    // Date absente = écriture serveur en attente -> maintenant.
    final i = indexOf(tx.date ?? now);
    if (net != null && i != null) buckets[i].value += net.toDouble();
  }
  return (buckets, current);
}

class _EarningsChart extends StatelessWidget {
  const _EarningsChart({required this.rides, required this.period});

  final List<WalletTx> rides;
  final WalletPeriod period;

  @override
  Widget build(BuildContext context) {
    final (buckets, current) = _buildBuckets(rides, period);
    final maxValue = buckets.fold<double>(0, (m, b) => math.max(m, b.value));
    final maxY = maxValue <= 0 ? 10000.0 : _niceCeil(maxValue * 1.15);
    final barWidth = buckets.length > 7 ? 14.0 : 26.0;

    const axisStyle = TextStyle(color: Colors.white, fontSize: 11);

    return BarChart(
      BarChartData(
        maxY: maxY,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(
          show: true,
          border: Border(
            left: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(formatCompact(value), style: axisStyle),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= buckets.length) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    buckets[i].label,
                    style: axisStyle.copyWith(
                      fontSize: buckets.length > 7 ? 9.5 : 12,
                      fontWeight: i == current ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.white,
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              formatFcfa(rod.toY),
              const TextStyle(
                color: kWalletInk,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < buckets.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: buckets[i].value,
                  width: barWidth,
                  borderRadius: BorderRadius.circular(5),
                  borderSide: const BorderSide(color: Colors.white, width: 1),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: i == current
                        ? const [MooviGradient.end, Colors.black]
                        : const [Color(0xFF2A1503), Colors.black],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Arrondit vers le haut à une valeur « ronde » (1, 2, 2.5, 5 × 10^n).
  static double _niceCeil(double v) {
    final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
      if (v <= m * exp) return m * exp;
    }
    return 10 * exp;
  }
}

// -----------------------------------------------------------------------------
// Encart commission
// -----------------------------------------------------------------------------

class _CommissionCard extends StatelessWidget {
  const _CommissionCard();

  @override
  Widget build(BuildContext context) {
    final pct = (kMooviCommissionRate * 100).round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD3A6),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFFC28A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.info_rounded, color: MooviGradient.brownCard),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Commission plateforme : $pct %',
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: kWalletInk,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Prélevée automatiquement sur chaque course pour garantir le service MOOVI.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: kWalletInk),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
