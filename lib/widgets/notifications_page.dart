import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/messaging_service.dart';
import 'ride_chat_page.dart';

/// Notifications de l'utilisateur, mises à jour en temps réel.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const _orange = Color(0xFFFF7A00);
  late final Stream<List<Map<String, dynamic>>> _stream =
      MessagingService.instance.notificationsStream();
  final _readLocally = <String>{};

  static IconData _icon(String? type) {
    switch (type) {
      case 'ride_message':
        return Icons.chat_bubble_outline;
      case 'ride_offer':
      case 'offer_accepted':
        return Icons.local_offer_outlined;
      case 'ride_paid':
      case 'wallet_recharged':
      case 'referral_reward':
        return Icons.account_balance_wallet_outlined;
      case 'document_reviewed':
      case 'driver_verification':
        return Icons.verified_user_outlined;
      case 'ride_cancelled':
      case 'ride_expired':
        return Icons.cancel_outlined;
      default:
        return Icons.directions_car_outlined;
    }
  }

  static String _when(dynamic iso) {
    final d = asDate(iso);
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return "À l'instant";
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _open(Map<String, dynamic> n) async {
    final id = n['id']?.toString();
    if (id != null && n['isRead'] != true && !_readLocally.contains(id)) {
      setState(() => _readLocally.add(id));
      MessagingService.instance.markRead(id).catchError((_) {});
    }
    final payload = n['payload'];
    final rideId = payload is Map ? payload['rideId']?.toString() : null;
    if (n['type'] == 'ride_message' && rideId != null && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              RideChatPage(rideId: rideId, title: n['title']?.toString() ?? 'Messages'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        title: const Text('Notifications',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await MessagingService.instance.markAllRead();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(errorMessage(e))));
                return;
              }
              if (mounted) setState(() => _readLocally.add('*'));
            },
            child: const Text('Tout lire', style: TextStyle(color: _orange)),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError && !snap.hasData) {
            return Center(child: Text(errorMessage(snap.error!)));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: _orange));
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const Center(
                child: Text('Aucune notification',
                    style: TextStyle(color: Colors.grey)));
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = items[i];
              final unread = n['isRead'] != true &&
                  !_readLocally.contains('*') &&
                  !_readLocally.contains(n['id']?.toString());
              return ListTile(
                tileColor: unread ? const Color(0xFFFFF1E4) : Colors.white,
                leading: CircleAvatar(
                  backgroundColor: _orange.withValues(alpha: 0.12),
                  child: Icon(_icon(n['type']?.toString()), color: _orange),
                ),
                title: Text(n['title']?.toString() ?? '',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: unread ? FontWeight.w800 : FontWeight.w500,
                        fontSize: 14)),
                subtitle: Text(
                    '${n['body'] ?? ''}\n${_when(n['createdAt'])}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
                isThreeLine: true,
                onTap: () => _open(n),
              );
            },
          );
        },
      ),
    );
  }
}

/// Icône cloche avec le nombre de notifications non lues.
class NotificationBell extends StatelessWidget {
  final Color color;
  const NotificationBell({super.key, this.color = Colors.black});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MessagingService.instance.unreadCount,
      builder: (context, count, _) => IconButton(
        tooltip: 'Notifications',
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const NotificationsPage())),
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text(count > 99 ? '99+' : '$count'),
          child: Icon(Icons.notifications_none, color: color),
        ),
      ),
    );
  }
}
