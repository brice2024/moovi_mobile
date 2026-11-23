import 'package:flutter/material.dart';
import 'package:moovi/widgets/moovi_scaffold.dart';

import 'moovi_format.dart';

// Taux de commission : défini une seule fois dans DriverService.
import 'package:moovi/services/driver_service.dart' show kMooviCommissionRate;
export 'package:moovi/services/driver_service.dart' show kMooviCommissionRate;

const Color kWalletInk = Color(0xFF3A2208);
const Color _red = Color(0xFFC62828);
const Color _green = Color(0xFF1FA45B);

/// Transaction de `drivers/{uid}/wallet_transactions`.
class WalletTx {
  WalletTx(this.id, Map<String, dynamic> d)
      : type = d['type']?.toString() ?? '',
        amount = (d['amount'] as num?) ?? 0,
        ridePrice = d['ridePrice'] as num?,
        rideId = d['rideId']?.toString(),
        rate = (d['commissionRate'] as num?)?.toDouble(),
        operatorName = d['operatorName']?.toString(),
        description = d['description']?.toString(),
        date = asDate(d['createdAt']);

  final String id;
  final String type;
  final num amount;
  final num? ridePrice;
  final String? rideId;
  final double? rate;
  final String? operatorName;
  final String? description;
  final DateTime? date;

  bool get isCommission => type == 'commission';
  bool get isDeposit => type == 'deposit';

  /// Commission prélevée (valeur positive).
  num get commission => amount.abs();

  /// Net reçu par le chauffeur = prix de la course − commission.
  num? get net => ridePrice == null ? null : ridePrice! - commission;

  String get rideLabel {
    final raw = (rideId ?? id).replaceFirst('COMM-', '');
    final short = raw.length > 4 ? raw.substring(raw.length - 4) : raw;
    return 'Course #${short.toUpperCase()}';
  }

  String get rateLabel =>
      '${((rate ?? kMooviCommissionRate) * 100).round()} %';
}

/// Carte « Course #XXXX » de la maquette 20.
class WalletRideCard extends StatelessWidget {
  const WalletRideCard({super.key, required this.tx});
  final WalletTx tx;

  @override
  Widget build(BuildContext context) {
    final net = tx.net;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MooviGradient.cardStrong,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const _IconBox(icon: Icons.directions_car_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.rideLabel,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: kWalletInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatRelativeDate(tx.date),
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w500,
                        color: kWalletInk.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    net == null ? '–' : formatFcfa(net, withSign: true),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: MooviGradient.brownCard,
                    ),
                  ),
                  const Text(
                    'Net reçu',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: kWalletInk,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: kWalletInk.withValues(alpha: 0.1)),
          const SizedBox(height: 12),
          _Line(
            label: 'Prix de la course',
            value: tx.ridePrice == null ? '–' : formatFcfa(tx.ridePrice!, withSign: true),
            color: kWalletInk,
          ),
          const SizedBox(height: 6),
          _Line(
            label: 'Commission MOOVI (${tx.rateLabel})',
            value: formatFcfa(-tx.commission),
            color: _red,
          ),
        ],
      ),
    );
  }
}

/// Carte d'une recharge (ou autre opération) du portefeuille.
class WalletOperationCard extends StatelessWidget {
  const WalletOperationCard({super.key, required this.tx});
  final WalletTx tx;

  @override
  Widget build(BuildContext context) {
    final positive = tx.amount >= 0;
    final title = tx.isDeposit
        ? 'Recharge${tx.operatorName != null ? ' ${tx.operatorName}' : ' Mobile Money'}'
        : (tx.description ?? 'Opération');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MooviGradient.cardStrong,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          _IconBox(
            icon: tx.isDeposit
                ? Icons.account_balance_wallet_rounded
                : Icons.swap_horiz_rounded,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: kWalletInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatRelativeDate(tx.date),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    color: kWalletInk.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatFcfa(tx.amount, withSign: true),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: positive ? _green : _red,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFFFD9B8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: kWalletInk, size: 22),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(fontSize: 13, color: color)),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }
}

/// Encart vide utilisé quand il n'y a encore aucune opération.
class WalletEmptyCard extends StatelessWidget {
  const WalletEmptyCard({super.key, required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: MooviGradient.cardStrong.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        children: [
          const Icon(Icons.receipt_long_rounded, size: 38, color: MooviGradient.end),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: kWalletInk,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: kWalletInk.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}
