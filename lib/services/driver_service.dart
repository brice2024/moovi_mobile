import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'Auth.dart';
import 'api_client.dart';
import 'realtime_service.dart';

/// Accès chauffeur & courses via l'API Moovi (remplace Firestore).
///
/// Les anciens `snapshots()` Firestore sont remplacés par des flux temps réel
/// ([liveApi]) : rechargés à chaque événement Socket.IO de l'API, avec une
/// interrogation périodique de secours si le socket est coupé. La logique métier
/// sensible (commission 15 %, crédit du portefeuille, attribution atomique
/// d'une course) est exécutée par le serveur.
class DriverService {
  DriverService._();
  static final DriverService instance = DriverService._();

  final _api = ApiClient.instance;

  /// Dernier profil chauffeur connu (`GET /api/drivers/me`).
  Map<String, dynamic>? cachedDriver;

  // ───────────────────────────────────────────────────────────────────────
  // PROFIL CHAUFFEUR
  // ───────────────────────────────────────────────────────────────────────

  /// Profil chauffeur de l'utilisateur connecté, ou null s'il n'est pas inscrit.
  Future<Map<String, dynamic>?> getMyDriver() async {
    try {
      final data = await _api.request('GET', '/api/drivers/me');
      cachedDriver = data;
      return data;
    } on ApiException catch (e) {
      if (e.code == 'DRIVER_NOT_REGISTERED') {
        cachedDriver = null;
        return null;
      }
      rethrow;
    }
  }

  /// Vérifie si l'utilisateur connecté est déjà inscrit en tant que chauffeur.
  Future<bool> isDriverRegistered() async {
    final driver = await getMyDriver();
    return driver != null;
  }

  /// Inscription / mise à jour du véhicule avec tous les documents en une
  /// seule requête multipart (`POST /api/drivers/register`).
  Future<Map<String, dynamic>> registerVehicle({
    required String vehicleType,
    required String brand,
    required String model,
    required String color,
    required String plate,
    List<UploadFile> documents = const [],
    void Function(double progress)? onProgress,
  }) async {
    final data = await _api.upload(
      '/api/drivers/register',
      fields: {
        'vehicleType': vehicleType,
        'brand': brand,
        'model': model,
        'color': color,
        'plate': plate,
      },
      files: documents,
      onProgress: onProgress,
    );
    cachedDriver = data;
    // Le rôle passe à « driver » côté serveur : on rafraîchit la session.
    AuthService.instance.refreshProfile().then((_) {}, onError: (_) {});
    return data;
  }

  /// Documents du chauffeur (`GET /api/drivers/me/documents`).
  Future<Map<String, dynamic>> getDocuments() =>
      _api.request('GET', '/api/drivers/me/documents');

  Stream<Map<String, dynamic>> streamDocuments() => liveApi(
        getDocuments,
        events: const {
          'driver:verification_updated',
          'driver:vehicle_verification_updated',
          'notification:new',
        },
        where: (e) =>
            e.name != 'notification:new' ||
            const {'document_reviewed', 'driver_verification'}
                .contains(e.data['type']),
        fallback: const Duration(seconds: 15),
      );

  /// (Ré)envoi d'un document (`POST /api/drivers/me/documents/{type}`).
  Future<Map<String, dynamic>> uploadDocument(
          String docType, List<int> bytes, String filename) =>
      _api.upload('/api/drivers/me/documents/$docType',
          files: [UploadFile('file', bytes, filename)]);

  // ───────────────────────────────────────────────────────────────────────
  // DISPONIBILITÉ & POSITION
  // ───────────────────────────────────────────────────────────────────────

  Timer? _heartbeat;

  /// Passe le chauffeur en ligne / hors ligne (`PUT /api/drivers/me/availability`).
  /// Lève [ApiException] (ex. `WALLET_BLOCKED`, `DRIVER_NOT_VERIFIED`).
  Future<Map<String, dynamic>> setAvailability({
    required bool isOnline,
    double? latitude,
    double? longitude,
  }) async {
    final data = await _api.request('PUT', '/api/drivers/me/availability', body: {
      'isAvailable': isOnline,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });
    if (isOnline) {
      startLocationHeartbeat();
    } else {
      stopLocationHeartbeat();
    }
    return data;
  }

  /// Envoie la position GPS : par le socket s'il est connecté
  /// (`driver:location_update`), sinon par `PUT /api/drivers/me/location`.
  Future<void> updateLocation(double latitude, double longitude,
      {double? heading}) async {
    final sent = RealtimeService.instance.emit('driver:location_update', {
      'latitude': latitude,
      'longitude': longitude,
      if (heading != null) 'heading': heading,
    });
    if (sent) return;
    await _api.request('PUT', '/api/drivers/me/location', body: {
      'latitude': latitude,
      'longitude': longitude,
      if (heading != null) 'heading': heading,
    });
  }

  /// Envoie la position toutes les 10 s : l'API remet hors ligne un chauffeur
  /// sans signal depuis `DRIVER_DISCONNECT_GRACE_SECONDS` (30 s) et transmet
  /// la position au passager pendant une course.
  ///
  /// Un flux de position en service de premier plan (notification permanente
  /// sur Android, indicateur bleu sur iOS) garde l'application active quand le
  /// chauffeur passe sur une autre application (GPS, appel) : la position et
  /// la connexion temps réel continuent, et les courses restent reçues.
  void startLocationHeartbeat(
      {Duration interval = const Duration(seconds: 10)}) {
    _heartbeat?.cancel();
    _startBackgroundPositionStream();
    Future<void> beat() async {
      try {
        final last = _lastPosition;
        final fresh = last != null &&
            DateTime.now().difference(last.timestamp) < const Duration(seconds: 15);
        final pos = fresh
            ? last
            : await Geolocator.getCurrentPosition()
                .timeout(const Duration(seconds: 8));
        await updateLocation(pos.latitude, pos.longitude, heading: pos.heading);
      } catch (e) {
        debugPrint('Position chauffeur non envoyée : $e');
      }
    }

    beat();
    _heartbeat = Timer.periodic(interval, (_) => beat());
  }

  Position? _lastPosition;
  StreamSubscription<Position>? _positionSub;

  void _startBackgroundPositionStream() {
    if (_positionSub != null) return;
    final LocationSettings settings;
    if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Moovi chauffeur en ligne',
          notificationText:
              'Votre position est partagée pour recevoir des courses.',
          notificationChannelName: 'Mode chauffeur',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else if (Platform.isIOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    } else {
      return;
    }
    _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) => _lastPosition = pos,
      onError: (Object e) {
        debugPrint('Flux de position interrompu : $e');
        _positionSub?.cancel();
        _positionSub = null;
      },
    );
  }

  void stopLocationHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _positionSub?.cancel();
    _positionSub = null;
    _lastPosition = null;
  }

  // ───────────────────────────────────────────────────────────────────────
  // COURSES
  // ───────────────────────────────────────────────────────────────────────

  /// Courses en recherche à proximité, filtrées selon le véhicule du chauffeur.
  Future<List<Map<String, dynamic>>> getAvailableRides(
      {double? latitude, double? longitude}) async {
    final data = await _api.request('GET', '/api/rides/available', query: {
      'lat': latitude,
      'lng': longitude,
    });
    return _list(data['rides']);
  }

  /// Nouvelles courses (`ride:new`) et courses retirées (prises, annulées,
  /// expirées) en temps réel.
  Stream<List<Map<String, dynamic>>> availableRidesStream(
          {double? Function()? latitude, double? Function()? longitude}) =>
      liveApi(
        () => getAvailableRides(
            latitude: latitude?.call(), longitude: longitude?.call()),
        events: const {
          'ride:new',
          'ride:taken',
          'ride:expired',
          'ride:cancelled',
          'ride:accepted',
          'driver:offline',
          'driver:verification_updated',
        },
        safety: const Duration(seconds: 20),
      );

  Future<Map<String, dynamic>> getRide(String rideId) =>
      _api.request('GET', '/api/rides/$rideId');

  /// Écoute une course spécifique (statut, paiement, position du chauffeur).
  /// Statut, paiement et annulation sont rechargés à chaque événement ; la
  /// position du chauffeur (`ride:driver_location`) est appliquée directement.
  Stream<Map<String, dynamic>> streamRide(String rideId,
          {Duration interval = const Duration(seconds: 4)}) =>
      liveApi(
        () => getRide(rideId),
        rideId: rideId,
        events: const {
          'ride:accepted',
          'ride:status_changed',
          'ride:cancelled',
          'ride:expired',
          'ride:paid',
          'ride:taken',
          'ride:driver_location',
        },
        where: (e) => e.rideId == rideId,
        onEvent: (e, last) {
          if (e.name != 'ride:driver_location' || last == null) return null;
          return {
            ...last,
            'driverLocation': {
              'latitude': e.data['latitude'],
              'longitude': e.data['longitude'],
              'heading': e.data['heading'],
              'updatedAt': e.data['timestamp'],
            },
          };
        },
        fallback: interval,
        safety: const Duration(seconds: 20),
      );

  /// Course active de l'utilisateur (`role` : passenger | driver).
  Future<Map<String, dynamic>?> getActiveRide({String? role}) async {
    final data =
        await _api.request('GET', '/api/rides/active', query: {'role': role});
    final ride = data['ride'];
    return ride is Map ? Map<String, dynamic>.from(ride) : null;
  }

  /// Propositions des chauffeurs pour une course donnée.
  Future<List<Map<String, dynamic>>> getRideOffers(String rideId,
      {String sortBy = 'price'}) async {
    final data = await _api.request('GET', '/api/rides/$rideId/offers',
        query: {'sortBy': sortBy});
    return _list(data['offers']);
  }

  Stream<List<Map<String, dynamic>>> streamRideOffers(String rideId) => liveApi(
        () => getRideOffers(rideId),
        rideId: rideId,
        events: const {
          'ride:offer_received',
          'ride:offer_withdrawn',
          'ride:accepted',
          'ride:cancelled',
          'ride:expired',
        },
        where: (e) => e.rideId == rideId,
        fallback: const Duration(seconds: 3),
        safety: const Duration(seconds: 20),
      );

  /// Envoie ou met à jour l'offre du chauffeur connecté. Le nom, le véhicule,
  /// la note et la photo sont renseignés par le serveur depuis le profil.
  Future<Map<String, dynamic>> sendDriverOffer({
    required String rideId,
    required int price,
    int? arrivalMinutes,
    String? message,
  }) =>
      _api.request('POST', '/api/rides/$rideId/offers', body: {
        'price': price,
        if (arrivalMinutes != null) 'arrivalMinutes': arrivalMinutes,
        if (message != null && message.isNotEmpty) 'message': message,
      });

  /// Le passager accepte l'offre d'un chauffeur (attribution atomique côté API).
  Future<Map<String, dynamic>> acceptDriverOffer({
    required String rideId,
    required String offerId,
  }) =>
      _api.request('POST', '/api/rides/$rideId/offers/$offerId/accept');

  /// Avancement de la course par le chauffeur :
  /// 'driver_arrived', 'in_progress', 'completed' ou 'cancelled'.
  Future<Map<String, dynamic>> updateRideStatus({
    required String rideId,
    required String newStatus,
    String? reason,
  }) {
    switch (newStatus) {
      case 'driver_arrived':
        return _api.request('POST', '/api/rides/$rideId/arrived');
      case 'in_progress':
        return _api.request('POST', '/api/rides/$rideId/start');
      case 'completed':
        return _api.request('POST', '/api/rides/$rideId/complete');
      case 'cancelled':
        return cancelRide(rideId, reason: reason);
      default:
        throw ArgumentError('Statut de course inconnu : $newStatus');
    }
  }

  /// Annulation par le passager ou le chauffeur assigné.
  Future<Map<String, dynamic>> cancelRide(String rideId, {String? reason}) =>
      _api.request('POST', '/api/rides/$rideId/cancel',
          body: {if (reason != null) 'reason': reason});

  /// Note la course terminée (1 à 5).
  Future<Map<String, dynamic>> rateRide(String rideId,
          {required int score, String? comment}) =>
      _api.request('POST', '/api/rides/$rideId/rate', body: {
        'score': score,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      });

  /// Le chauffeur confirme l'encaissement en espèces. L'API marque la course
  /// payée et prélève atomiquement la commission Moovi (15 %) du portefeuille.
  Future<Map<String, dynamic>> confirmCashPayment(String rideId) =>
      _api.request('POST', '/api/rides/$rideId/pay/cash');

  // ───────────────────────────────────────────────────────────────────────
  // PORTEFEUILLE CHAUFFEUR & COMMISSIONS MOOVI
  // ───────────────────────────────────────────────────────────────────────

  /// Solde, état de blocage et transactions (`GET /api/wallet`).
  Future<Map<String, dynamic>> getWallet({int perPage = 30}) =>
      _api.request('GET', '/api/wallet', query: {'perPage': perPage});

  /// Écoute le portefeuille du chauffeur connecté.
  Stream<Map<String, dynamic>> streamDriverWallet() => liveApi(
        getWallet,
        events: const {'wallet:updated', 'ride:paid'},
        fallback: const Duration(seconds: 8),
      );

  /// Historique des courses et revenus du chauffeur.
  Future<Map<String, dynamic>> getMyDriverRides({int perPage = 20}) =>
      _api.request('GET', '/api/drivers/me/rides', query: {'perPage': perPage});

  List<Map<String, dynamic>> _list(dynamic value) => (value as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}
