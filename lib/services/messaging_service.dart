import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'realtime_service.dart';
import 'session.dart';

/// Messagerie de course et notifications, via l'API Moovi + Socket.IO.
class MessagingService {
  MessagingService._();
  static final instance = MessagingService._();

  final _api = ApiClient.instance;

  // ───────────────────────────────────────────────────────────────────────
  // CHAT DE COURSE (`/api/rides/<id>/messages`, événement `ride:message`)
  // ───────────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMessages(String rideId) async {
    final data = await _api.request('GET', '/api/rides/$rideId/messages');
    return _list(data['messages']);
  }

  /// Envoie par REST : l'API enregistre le message, notifie le destinataire
  /// et le diffuse en temps réel aux deux participants.
  Future<Map<String, dynamic>> sendMessage(String rideId, String content) =>
      _api.request('POST', '/api/rides/$rideId/messages',
          body: {'content': content});

  /// Fil de discussion : chargé une fois, puis complété à chaque
  /// `ride:message` reçu (sans requête supplémentaire).
  Stream<List<Map<String, dynamic>>> messagesStream(String rideId) =>
      liveApi<List<Map<String, dynamic>>>(
        () => getMessages(rideId),
        rideId: rideId,
        events: const {'ride:message'},
        where: (e) => e.data['rideId']?.toString() == rideId,
        onEvent: (e, last) => mergeMessage(last ?? const [], e.data),
        fallback: const Duration(seconds: 5),
        safety: const Duration(seconds: 60),
      );

  /// Ajoute un message à la liste sans doublon (même id).
  static List<Map<String, dynamic>> mergeMessage(
      List<Map<String, dynamic>> list, Map<String, dynamic> message) {
    final id = message['id']?.toString();
    if (id != null && list.any((m) => m['id']?.toString() == id)) return list;
    return [...list, message];
  }

  // ───────────────────────────────────────────────────────────────────────
  // NOTIFICATIONS (`/api/notifications`, événement `notification:new`)
  // ───────────────────────────────────────────────────────────────────────

  /// Nombre de notifications non lues, tenu à jour en temps réel.
  final ValueNotifier<int> unreadCount = ValueNotifier(0);

  StreamSubscription<RealtimeEvent>? _notifSub;
  StreamSubscription<AppUser?>? _sessionSub;

  /// À appeler au démarrage : suit le compteur de non-lues.
  void init() {
    _notifSub ??= RealtimeService.instance
        .on(const {'notification:new', 'realtime:connected'}).listen((e) {
      if (e.name == 'notification:new') {
        unreadCount.value = unreadCount.value + 1;
      } else {
        refreshUnreadCount();
      }
    });
    _sessionSub ??= AppSession.instance.changes.listen((user) {
      if (user == null) {
        unreadCount.value = 0;
      } else {
        refreshUnreadCount();
      }
    });
    if (AppSession.instance.currentUser != null) refreshUnreadCount();
  }

  Future<void> refreshUnreadCount() async {
    try {
      final data = await _api.request('GET', '/api/notifications',
          query: {'perPage': 1, 'unreadOnly': 'true'});
      unreadCount.value = asNum(data['unreadCount'])?.toInt() ?? 0;
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getNotifications({int perPage = 50}) async {
    final data = await _api
        .request('GET', '/api/notifications', query: {'perPage': perPage});
    unreadCount.value = asNum(data['unreadCount'])?.toInt() ?? unreadCount.value;
    return _list(data['notifications']);
  }

  /// Liste des notifications : une nouvelle notification apparaît en tête
  /// dès sa réception.
  Stream<List<Map<String, dynamic>>> notificationsStream() =>
      liveApi<List<Map<String, dynamic>>>(
        getNotifications,
        events: const {'notification:new'},
        onEvent: (e, last) {
          final id = e.data['id']?.toString();
          final list = last ?? const <Map<String, dynamic>>[];
          if (list.any((n) => n['id']?.toString() == id)) return list;
          return [e.data, ...list];
        },
        fallback: const Duration(seconds: 15),
        safety: const Duration(seconds: 90),
      );

  Future<void> markRead(dynamic notificationId) async {
    await _api.request('POST', '/api/notifications/$notificationId/read');
    if (unreadCount.value > 0) unreadCount.value = unreadCount.value - 1;
  }

  Future<void> markAllRead() async {
    await _api.request('POST', '/api/notifications/read-all');
    unreadCount.value = 0;
  }

  List<Map<String, dynamic>> _list(dynamic value) => (value as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}
