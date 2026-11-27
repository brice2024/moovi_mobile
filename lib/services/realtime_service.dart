import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_client.dart';
import 'session.dart';

/// Événement Socket.IO reçu de l'API Moovi.
class RealtimeEvent {
  final String name;
  final Map<String, dynamic> data;
  const RealtimeEvent(this.name, this.data);

  /// Identifiant de course porté par l'événement (`rideId` ou `id`).
  String? get rideId =>
      (data['rideId'] ?? (name.startsWith('ride:') ? data['id'] : null))
          ?.toString();
}

/// Connexion temps réel unique à l'API (Socket.IO, authentifiée par JWT).
///
/// - se connecte dès qu'un utilisateur est en session et se coupe à la
///   déconnexion ;
/// - renouvelle le jeton d'accès si le serveur refuse la connexion ;
/// - se réabonne aux courses suivies après chaque reconnexion.
///
/// Les écrans n'écoutent pas directement le socket : ils passent par
/// [liveApi], qui recharge les données depuis l'API à chaque événement
/// pertinent (source de vérité unique) et repasse en interrogation
/// périodique tant que le socket est coupé.
class RealtimeService {
  RealtimeService._();
  static final instance = RealtimeService._();

  io.Socket? _socket;
  final _events = StreamController<RealtimeEvent>.broadcast();
  final _rides = <String, int>{};
  StreamSubscription<AppUser?>? _sessionSub;
  Timer? _retryTimer;
  int _retries = 0;

  /// Vrai quand le socket est connecté et authentifié.
  final ValueNotifier<bool> connected = ValueNotifier(false);

  /// Tous les événements serveur. `realtime:connected` est émis localement à
  /// chaque (re)connexion pour que les écrans se resynchronisent.
  Stream<RealtimeEvent> get events => _events.stream;

  /// Événements filtrés par nom.
  Stream<RealtimeEvent> on(Set<String> names) =>
      events.where((e) => names.contains(e.name));

  /// À appeler une fois au démarrage, après la restauration de session.
  void init() {
    _sessionSub ??= AppSession.instance.changes.listen((user) {
      if (user == null) {
        disconnect();
      } else {
        connect();
      }
    });
    if (AppSession.instance.currentUser != null) connect();
  }

  void connect() {
    if (ApiClient.instance.accessToken == null) return;
    final existing = _socket;
    if (existing != null) {
      if (!existing.connected && !existing.active) existing.connect();
      return;
    }

    final socket = io.io(
      ApiClient.baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .enableForceNew()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          // Lu à chaque tentative : utilise toujours le dernier jeton d'accès.
          .setAuthFn((cb) => cb({'token': ApiClient.instance.accessToken ?? ''}))
          .build(),
    );

    socket.onConnect((_) {
      _retries = 0;
      _retryTimer?.cancel();
      connected.value = true;
      for (final rideId in _rides.keys) {
        socket.emit('join_ride', {'rideId': rideId});
      }
      _events.add(const RealtimeEvent('realtime:connected', {}));
    });
    socket.onDisconnect((_) => connected.value = false);
    socket.onConnectError((error) {
      connected.value = false;
      debugPrint('Temps réel : connexion refusée ($error)');
      _scheduleRetry();
    });
    socket.onAny((event, data) {
      final payload = data is Map
          ? Map<String, dynamic>.from(data)
          : (data is List && data.isNotEmpty && data.first is Map)
              ? Map<String, dynamic>.from(data.first as Map)
              : <String, dynamic>{};
      _events.add(RealtimeEvent(event, payload));
    });

    _socket = socket;
    socket.connect();
  }

  /// Le serveur refuse la connexion si le jeton est expiré : on le renouvelle
  /// puis on retente avec un délai croissant (2 s → 30 s).
  void _scheduleRetry() {
    final socket = _socket;
    if (socket == null || socket.active) return; // reconnexion automatique
    _retryTimer?.cancel();
    final delay = Duration(seconds: (2 << _retries.clamp(0, 4)).clamp(2, 30));
    _retries++;
    _retryTimer = Timer(delay, () async {
      if (_socket != socket || socket.connected) return;
      await ApiClient.instance.refreshAccessToken();
      if (ApiClient.instance.accessToken == null) return;
      socket.connect();
    });
  }

  void disconnect() {
    _retryTimer?.cancel();
    _rides.clear();
    final socket = _socket;
    _socket = null;
    connected.value = false;
    if (socket != null) {
      socket.clearListeners();
      socket.dispose();
    }
  }

  /// Envoie un événement si le socket est connecté. Renvoie false sinon,
  /// pour que l'appelant utilise la route REST équivalente.
  bool emit(String event, [Map<String, dynamic>? data]) {
    final socket = _socket;
    if (socket == null || !socket.connected) return false;
    socket.emit(event, data ?? const {});
    return true;
  }

  /// Suit une course (room `ride:<id>`). Compteur de références : la room est
  /// quittée quand plus aucun écran ne suit la course.
  void joinRide(String rideId) {
    _rides[rideId] = (_rides[rideId] ?? 0) + 1;
    if (_rides[rideId] == 1) emit('join_ride', {'rideId': rideId});
  }

  void leaveRide(String rideId) {
    final count = (_rides[rideId] ?? 0) - 1;
    if (count > 0) {
      _rides[rideId] = count;
      return;
    }
    _rides.remove(rideId);
    emit('leave_ride', {'rideId': rideId});
  }
}

/// Flux de données « temps réel » adossé à l'API.
///
/// Charge [fetch] à l'abonnement, puis le recharge :
/// - à chaque événement Socket.IO dont le nom est dans [events] et qui passe
///   [where] (regroupés sur 300 ms) ;
/// - à chaque reconnexion du socket ;
/// - périodiquement en secours : [fallback] tant que le socket est coupé,
///   [safety] quand il est connecté (filet de sécurité, ex. événement manqué).
///
/// [rideId] abonne le socket à la room de la course pendant l'écoute.
/// [onEvent] permet d'appliquer un événement localement sans requête
/// (ex. position du chauffeur) : s'il renvoie une valeur, elle est émise et
/// aucun rechargement n'est déclenché.
Stream<T> liveApi<T>(
  Future<T> Function() fetch, {
  Set<String> events = const {},
  bool Function(RealtimeEvent e)? where,
  T? Function(RealtimeEvent e, T? last)? onEvent,
  String? rideId,
  Duration fallback = const Duration(seconds: 5),
  Duration safety = const Duration(seconds: 45),
}) {
  final rt = RealtimeService.instance;
  late StreamController<T> controller;
  StreamSubscription<RealtimeEvent>? sub;
  Timer? poll;
  Timer? debounce;
  T? last;
  var busy = false;
  var pending = false;

  Future<void> load() async {
    if (controller.isClosed) return;
    if (busy) {
      pending = true;
      return;
    }
    busy = true;
    try {
      final value = await fetch();
      last = value;
      if (!controller.isClosed) controller.add(value);
    } catch (e, st) {
      if (!controller.isClosed) controller.addError(e, st);
    } finally {
      busy = false;
      if (pending) {
        pending = false;
        unawaited(load());
      }
    }
  }

  void schedulePoll() {
    poll?.cancel();
    poll = Timer.periodic(rt.connected.value ? safety : fallback, (_) => load());
  }

  void onConnectionChange() => schedulePoll();

  controller = StreamController<T>(
    onListen: () {
      if (rideId != null) rt.joinRide(rideId);
      sub = rt.events.listen((e) {
        if (e.name == 'realtime:connected') {
          unawaited(load());
          return;
        }
        if (!events.contains(e.name)) return;
        if (where != null && !where(e)) return;
        if (onEvent != null) {
          final local = onEvent(e, last);
          if (local != null) {
            last = local;
            if (!controller.isClosed) controller.add(local);
            return;
          }
        }
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 300), load);
      });
      rt.connected.addListener(onConnectionChange);
      schedulePoll();
      unawaited(load());
    },
    onCancel: () {
      sub?.cancel();
      poll?.cancel();
      debounce?.cancel();
      rt.connected.removeListener(onConnectionChange);
      if (rideId != null) rt.leaveRide(rideId);
      return controller.close();
    },
  );
  return controller.stream;
}
