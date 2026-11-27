import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../services/realtime_service.dart';
import '../../theme/app_colors.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  // Historique des courses du passager (`GET /api/users/me/rides`),
  // actualisé automatiquement.
  late final Stream<List<Map<String, dynamic>>> _rides = liveApi(
    _load,
    events: const {
      'ride:status_changed',
      'ride:paid',
      'ride:cancelled',
      'ride:expired',
      'ride:accepted',
    },
    fallback: const Duration(seconds: 20),
    safety: const Duration(seconds: 60),
  );

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await ApiClient.instance
        .request('GET', '/api/users/me/rides', query: {'perPage': 50});
    return (data['rides'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static String _statusLabel(String status, bool isPaid, String? method) {
    if (isPaid) {
      switch (method) {
        case 'cash':
          return 'RÉGLÉ (Espèces Cash)';
        case 'mobile_money':
          return 'RÉGLÉ (Mobile Money)';
        case 'moovi_promo':
          return 'OFFERT PAR MOOVI';
        default:
          return 'RÉGLÉ';
      }
    }
    switch (status) {
      case 'searching':
        return 'RECHERCHE CHAUFFEUR';
      case 'accepted':
      case 'driver_arrived':
      case 'in_progress':
        return 'EN COURS';
      case 'completed':
        return 'EN ATTENTE DE RÈGLEMENT';
      case 'cancelled':
        return 'ANNULÉE';
      case 'expired':
        return 'EXPIRÉE';
      default:
        return 'EN ATTENTE';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Historique des courses',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.background,
          ),
        ),
        centerTitle: false,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _rides,
        builder: (context, snapshot) {
          if (snapshot.hasError && !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Impossible de charger l’historique : ${errorMessage(snapshot.error!)}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final docs = snapshot.data!;

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Aucune course effectuée',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.background,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Vos prochains trajets au Gabon apparaîtront ici.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final data = docs[i];
              final from =
                  data['departureAddress']?.toString() ?? 'Point de départ';
              final to = data['destinationAddress']?.toString() ?? 'Destination';
              final price =
                  (asNum(data['finalPrice']) ?? asNum(data['price']) ?? 0)
                      .toInt();
              final status = data['status']?.toString() ?? 'searching';
              final isPaid = data['isPaid'] == true;
              final date = asDate(data['createdAt']);
              final dateText = date == null
                  ? ''
                  : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} à ${date.hour}h${date.minute.toString().padLeft(2, '0')}';
              final isCancelled = status == 'cancelled' || status == 'expired';

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$price FCFA',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: isCancelled ? Colors.grey : AppColors.primary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isPaid
                                ? const Color(0xFFE8F5E9)
                                : isCancelled
                                    ? Colors.grey.shade100
                                    : const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _statusLabel(status, isPaid,
                                data['paymentMethod']?.toString()),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: isPaid
                                  ? const Color(0xFF2E7D32)
                                  : isCancelled
                                      ? Colors.grey.shade700
                                      : AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (dateText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(dateText,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600)),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.radio_button_checked,
                            size: 14, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            from,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: SizedBox(
                        height: 12,
                        child: VerticalDivider(color: Colors.grey, thickness: 1),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            size: 14, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            to,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
