import 'dart:async';

import 'package:flutter/material.dart';

import '../services/realtime_service.dart';
import 'notifications_page.dart';
import 'ride_chat_page.dart';

/// Affiche un bandeau dans l'application à chaque `notification:new` reçu
/// par Socket.IO (nouvelle offre, message, paiement, document validé…).
class InAppNotifications {
  InAppNotifications._();
  static final instance = InAppNotifications._();

  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  final navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<RealtimeEvent>? _sub;

  void init() {
    _sub ??= RealtimeService.instance
        .on(const {'notification:new'}).listen(_show);
  }

  void _show(RealtimeEvent e) {
    final payload = e.data['payload'];
    final rideId = payload is Map ? payload['rideId']?.toString() : null;
    final type = e.data['type']?.toString();
    // Inutile d'annoncer un message si la discussion est déjà ouverte.
    if (type == 'ride_message' && rideId != null &&
        RideChatPage.openRideId == rideId) {
      return;
    }
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    final title = e.data['title']?.toString() ?? 'Moovi';
    final body = e.data['body']?.toString() ?? '';
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (body.isNotEmpty)
              Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        action: SnackBarAction(
          label: type == 'ride_message' ? 'Répondre' : 'Voir',
          onPressed: () {
            final nav = navigatorKey.currentState;
            if (nav == null) return;
            nav.push(MaterialPageRoute(
              builder: (_) => type == 'ride_message' && rideId != null
                  ? RideChatPage(rideId: rideId, title: title)
                  : const NotificationsPage(),
            ));
          },
        ),
      ));
  }
}
