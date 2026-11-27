// Test d'intégration temps réel : nécessite une API Moovi de test démarrée.
// flutter test test/realtime_e2e_test.dart --dart-define=MOOVI_API_URL=http://127.0.0.1:5055
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:moovi/services/Auth.dart';
import 'package:moovi/services/api_client.dart';
import 'package:moovi/services/driver_service.dart';
import 'package:moovi/services/messaging_service.dart';
import 'package:moovi/services/realtime_service.dart';
import 'package:moovi/userScreens/dataService.dart';

const realtimeBudget = Duration(milliseconds: 2500);

/// Ignoré sans API de test explicite (`--dart-define=MOOVI_API_URL=...`).
const _apiUrl = String.fromEnvironment('MOOVI_API_URL');
const Object _skip = _apiUrl == '' ? 'Démarrer une API de test et passer --dart-define=MOOVI_API_URL' : false;

/// Autre participant (passager ou chauffeur) piloté en HTTP brut.
class Peer {
  String? token;
  Future<Map<String, dynamic>> call(String method, String path,
      [Map<String, dynamic>? body]) async {
    final req = http.Request(method, ApiClient.instance.uri(path));
    req.headers['Content-Type'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await req.send());
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 300) {
      throw StateError('$method $path -> ${res.statusCode} ${res.body}');
    }
    return Map<String, dynamic>.from(json['data'] as Map? ?? {});
  }

  Future<void> login(String phone) async {
    final s = await call('POST', '/api/auth/otp/send', {'phoneNumber': phone});
    final v = await call('POST', '/api/auth/otp/verify',
        {'phoneNumber': phone, 'code': s['debugOtp']});
    token = v['accessToken'] as String;
  }
}

Future<void> appLogin(String phone) async {
  await AuthService.instance.sendOTP(phone);
  await AuthService.instance.verifyOTPOrThrow(AuthService.instance.lastDebugOtp!);
  await waitConnected(true);
}

Future<void> waitConnected(bool value) async {
  final rt = RealtimeService.instance;
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (rt.connected.value != value) {
    if (DateTime.now().isAfter(end)) {
      fail('Socket ${value ? "non connecté" : "toujours connecté"}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Mémorise la dernière valeur d'un flux et attend une condition.
class Probe<T> {
  T? last;
  final _changes = StreamController<T>.broadcast();
  late final StreamSubscription<T> _sub;
  Probe(Stream<T> stream) {
    _sub = stream.listen((v) {
      last = v;
      _changes.add(v);
    }, onError: (Object e) => print('  (erreur flux : $e)'));
  }

  Future<Duration> until(bool Function(T v) test, String label,
      {Duration budget = realtimeBudget}) async {
    final sw = Stopwatch()..start();
    if (last != null && test(last as T)) return sw.elapsed;
    await _changes.stream.firstWhere(test).timeout(budget,
        onTimeout: () => throw TimeoutException('$label : pas reçu en $budget'));
    print('  OK ${label.padRight(52)} ${sw.elapsedMilliseconds} ms');
    return sw.elapsed;
  }

  Future<void> ready() => until((_) => true, 'chargement initial',
      budget: const Duration(seconds: 10));

  Future<void> cancel() async {
    await _sub.cancel();
    await _changes.close();
  }
}

void main() {
  setUpAll(() {
    RealtimeService.instance.init();
    MessagingService.instance.init();
  });

  test('Chauffeur dans l\'app : courses, chat, notifications, annulation', () async {
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    final driverPhone = '+241076${stamp.toString().padLeft(5, '0')}';
    final passengerPhone = '+241077${stamp.toString().padLeft(5, '0')}';

    await appLogin(driverPhone);
    print('  OK socket chauffeur connecté');
    final passenger = Peer();
    await passenger.login(passengerPhone);

    await ApiClient.instance.request('POST', '/api/drivers/register', body: {
      'vehicleType': 'voiture', 'brand': 'Toyota', 'model': 'Yaris',
      'color': 'Blanc', 'plate': 'GA-$stamp',
    });
    await DriverService.instance
        .setAvailability(isOnline: true, latitude: 0.41, longitude: 9.46);

    final rides = Probe(DriverService.instance
        .availableRidesStream(latitude: () => 0.41, longitude: () => 9.46));
    await rides.ready();

    final ride = await passenger.call('POST', '/api/rides', {
      'departureLat': 0.41, 'departureLng': 9.46, 'destinationLat': 0.45,
      'destinationLng': 9.43, 'departureAddress': 'Louis',
      'destinationAddress': 'Aéroport', 'price': 2500,
    });
    final rideId = ride['id'] as String;
    await rides.until((l) => l.any((r) => r['id'] == rideId),
        'ride:new -> course visible chez le chauffeur');

    await DriverService.instance.sendDriverOffer(rideId: rideId, price: 2700);
    final offers = await passenger.call('GET', '/api/rides/$rideId/offers');
    final offerId = (offers['offers'] as List).first['id'];

    final rideProbe = Probe(DriverService.instance.streamRide(rideId));
    await rideProbe.ready();
    await passenger.call('POST', '/api/rides/$rideId/offers/$offerId/accept');
    await rideProbe.until((r) => r['status'] == 'accepted',
        'ride:accepted -> course attribuée');
    await rides.until((l) => !l.any((r) => r['id'] == rideId),
        'course retirée de la liste disponible');

    final unreadBefore = MessagingService.instance.unreadCount.value;
    final chat = Probe(MessagingService.instance.messagesStream(rideId));
    await chat.ready();
    await passenger.call('POST', '/api/rides/$rideId/messages',
        {'content': 'Je suis devant la pharmacie'});
    await chat.until((m) => m.any((x) => x['content'] == 'Je suis devant la pharmacie'),
        'ride:message -> message passager reçu');
    final end = DateTime.now().add(realtimeBudget);
    while (MessagingService.instance.unreadCount.value <= unreadBefore) {
      if (DateTime.now().isAfter(end)) fail('notification:new non reçue');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    print('  OK notification:new -> compteur non lus incrémenté');

    final sentBySocket = RealtimeService.instance.emit('driver:location_update',
        {'latitude': 0.4123, 'longitude': 9.4612, 'heading': 45});
    expect(sentBySocket, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final seen = await passenger.call('GET', '/api/rides/$rideId');
    expect((seen['driverLocation'] as Map)['latitude'], closeTo(0.4123, 1e-6));
    print('  OK position chauffeur envoyée par le socket');

    await passenger.call('POST', '/api/rides/$rideId/cancel', {'reason': 'Test'});
    await rideProbe.until((r) => r['status'] == 'cancelled',
        'ride:cancelled -> annulation passager');

    await rides.cancel();
    await rideProbe.cancel();
    await chat.cancel();
    await DriverService.instance.setAvailability(isOnline: false);
    await AuthService.instance.logout();
    await waitConnected(false);
    print('  OK déconnexion -> socket fermé');
  }, timeout: const Timeout(Duration(minutes: 2)), skip: _skip);

  test('Passager dans l\'app : offres, suivi chauffeur, statuts, chat, paiement', () async {
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    final passengerPhone = '+241078${stamp.toString().padLeft(5, '0')}';
    final driverPhone = '+241079${stamp.toString().padLeft(5, '0')}';

    final driver = Peer();
    await driver.login(driverPhone);
    await driver.call('POST', '/api/drivers/register', {
      'vehicleType': 'voiture', 'brand': 'Kia', 'model': 'Rio',
      'color': 'Gris', 'plate': 'GB-$stamp',
    });
    await driver.call('PUT', '/api/drivers/me/availability',
        {'isAvailable': true, 'latitude': 0.411, 'longitude': 9.461});
    final driverId = (await driver.call('GET', '/api/drivers/me'))['id'];

    await appLogin(passengerPhone);
    print('  OK socket passager connecté');

    final nearby = Probe(NearbyDriversService()
        .getDrivers(() => (latitude: 0.41, longitude: 9.46)));
    await nearby.until((l) => l.any((d) => d['id'] == driverId),
        'chauffeur visible sur la carte', budget: const Duration(seconds: 10));
    await driver.call('PUT', '/api/drivers/me/location',
        {'latitude': 0.4135, 'longitude': 9.4625});
    await nearby.until(
        (l) => l.any((d) =>
            d['id'] == driverId && asNum(d['latitude']) == 0.4135),
        'driver:location_updated -> marqueur déplacé');

    final ride = await ApiClient.instance.request('POST', '/api/rides', body: {
      'departureLat': 0.41, 'departureLng': 9.46, 'destinationLat': 0.45,
      'destinationLng': 9.43, 'departureAddress': 'Glass',
      'destinationAddress': 'Akanda', 'price': 3000,
    });
    final rideId = ride['id'] as String;

    final offers = Probe(DriverService.instance.streamRideOffers(rideId));
    await offers.ready();
    await driver.call('POST', '/api/rides/$rideId/offers', {'price': 3200});
    await offers.until((l) => l.isNotEmpty,
        'ride:offer_received -> offre affichée');

    final rideProbe = Probe(DriverService.instance.streamRide(rideId));
    await rideProbe.ready();
    await DriverService.instance.acceptDriverOffer(
        rideId: rideId, offerId: offers.last!.first['id'].toString());

    await driver.call('PUT', '/api/drivers/me/location',
        {'latitude': 0.4101, 'longitude': 9.4601});
    await rideProbe.until(
        (r) => asNum((r['driverLocation'] as Map?)?['latitude']) == 0.4101,
        'ride:driver_location -> suivi du chauffeur');

    await driver.call('POST', '/api/rides/$rideId/arrived');
    await rideProbe.until((r) => r['status'] == 'driver_arrived',
        'ride:status_changed -> chauffeur arrivé');

    final chat = Probe(MessagingService.instance.messagesStream(rideId));
    await chat.ready();
    await driver.call('POST', '/api/rides/$rideId/messages', {'content': 'Je suis là'});
    await chat.until((m) => m.any((x) => x['content'] == 'Je suis là'),
        'ride:message -> message chauffeur reçu');
    final mine = await MessagingService.instance.sendMessage(rideId, 'J\'arrive');
    expect(mine['senderRole'], 'passenger');

    await driver.call('POST', '/api/rides/$rideId/start');
    await rideProbe.until((r) => r['status'] == 'in_progress',
        'ride:status_changed -> course démarrée');
    await driver.call('POST', '/api/rides/$rideId/complete');
    await rideProbe.until((r) => r['status'] == 'completed',
        'ride:status_changed -> course terminée');
    await driver.call('POST', '/api/rides/$rideId/pay/cash');
    await rideProbe.until((r) => r['isPaid'] == true,
        'ride:paid -> paiement espèces confirmé');

    final notifs = await MessagingService.instance.getNotifications();
    expect(notifs.any((n) => n['type'] == 'ride_message'), isTrue);
    print('  OK ${notifs.length} notifications listées');

    await nearby.cancel();
    await offers.cancel();
    await rideProbe.cancel();
    await chat.cancel();
    await AuthService.instance.logout();
    await waitConnected(false);
  }, timeout: const Timeout(Duration(minutes: 2)), skip: _skip);
}
