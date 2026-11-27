import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../widgets/in_app_notifications.dart';
import '../widgets/notifications_page.dart';
import '../widgets/ride_chat_page.dart';
import 'realtime_service.dart';
import 'session.dart';

/// Notifications système quand l'application est en arrière-plan.
///
/// Les événements arrivent par Socket.IO : la connexion reste ouverte tant que
/// le processus vit (en mode chauffeur, le service de position de premier plan
/// le maintient). Au premier plan, c'est le bandeau [InAppNotifications] qui
/// s'affiche à la place.
class LocalNotifications with WidgetsBindingObserver {
  LocalNotifications._();
  static final instance = LocalNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  StreamSubscription<RealtimeEvent>? _sub;
  AppLifecycleState _state = AppLifecycleState.resumed;
  int _nextId = 1;

  static const _channel = AndroidNotificationDetails(
    'moovi_events',
    'Courses et messages',
    channelDescription: 'Nouvelles courses, offres, messages et paiements',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<void> init() async {
    if (_sub != null) return;
    WidgetsBinding.instance.addObserver(this);
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) => _open(r.payload),
    );
    _sub = RealtimeService.instance
        .on(const {'notification:new', 'ride:new'}).listen(_onEvent);
    // Passagers aussi : offres, chauffeur arrivé, paiement… en arrière-plan.
    // L'autorisation est demandée une fois connecté (Android 13+, iOS).
    if (AppSession.instance.currentUser != null) unawaited(requestPermission());
    _sessionSub = AppSession.instance.changes.listen((user) {
      if (user != null) unawaited(requestPermission());
    });
  }

  StreamSubscription<AppUser?>? _sessionSub;

  /// Demande l'autorisation d'afficher des notifications (Android 13+, iOS).
  Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _state = state;

  void _onEvent(RealtimeEvent e) {
    if (_state == AppLifecycleState.resumed) return;
    final String title;
    final String body;
    final Map<String, dynamic> payload;
    if (e.name == 'ride:new') {
      final ride = e.data['ride'] is Map
          ? Map<String, dynamic>.from(e.data['ride'] as Map)
          : e.data;
      final price = ride['price'] ?? ride['finalPrice'];
      title = 'Nouvelle course${price != null ? ' · $price FCFA' : ''}';
      body = '${ride['departureAddress'] ?? 'Départ'} → '
          '${ride['destinationAddress'] ?? 'Destination'}';
      payload = {'type': 'ride_new'};
    } else {
      title = e.data['title']?.toString() ?? 'Moovi';
      body = e.data['body']?.toString() ?? '';
      final p = e.data['payload'];
      payload = {
        'type': e.data['type']?.toString(),
        'rideId': p is Map ? p['rideId']?.toString() : null,
        'title': title,
      };
    }
    _plugin.show(
      _nextId++,
      title,
      body,
      const NotificationDetails(
        android: _channel,
        iOS: DarwinNotificationDetails(presentSound: true),
      ),
      payload: jsonEncode(payload),
    );
  }

  void _open(String? raw) {
    if (raw == null) return;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    // Une nouvelle course : l'application revient simplement au premier plan,
    // sur la liste des courses déjà affichée.
    if (data['type'] == 'ride_new') return;
    final nav = InAppNotifications.instance.navigatorKey.currentState;
    if (nav == null) return;
    final rideId = data['rideId']?.toString();
    nav.push(MaterialPageRoute(
      builder: (_) => data['type'] == 'ride_message' && rideId != null
          ? RideChatPage(rideId: rideId, title: data['title']?.toString() ?? 'Discussion')
          : const NotificationsPage(),
    ));
  }
}
