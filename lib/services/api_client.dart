import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Fichier à envoyer dans une requête multipart.
class UploadFile {
  final String field;
  final List<int> bytes;
  final String filename;
  const UploadFile(this.field, this.bytes, this.filename);
}

/// Client unique de l'API Moovi.
///
/// Aucune clé de service tierce n'est embarquée dans l'application : Google
/// Maps (Places / Routes) et PawaPay sont appelés par l'API, qui
/// détient les clés dans son fichier `.env`. L'URL par défaut est celle de
/// l'API sur le réseau local ; elle reste surchargeable au build avec
/// `--dart-define=MOOVI_API_URL=https://api.exemple.com`.
class ApiClient {
  ApiClient._();
  static final instance = ApiClient._();

  static const baseUrl = String.fromEnvironment('MOOVI_API_URL',
      defaultValue: 'http://192.168.0.155:5000');

  static const _accessKey = 'moovi_access_token';
  static const _refreshKey = 'moovi_refresh_token';
  static const _storage = FlutterSecureStorage();

  final http.Client _http = http.Client();

  String? accessToken;
  String? refreshToken;

  /// Appelé quand la session ne peut plus être rafraîchie (déconnexion forcée).
  void Function()? onSessionExpired;

  Future<void>? _refreshing;

  // ---------------------------------------------------------------------------
  // Jetons
  // ---------------------------------------------------------------------------

  Future<void> loadTokens() async {
    try {
      accessToken = await _storage.read(key: _accessKey);
      refreshToken = await _storage.read(key: _refreshKey);
    } catch (_) {
      accessToken = null;
      refreshToken = null;
    }
  }

  Future<void> saveTokens({String? access, String? refresh}) async {
    if (access != null) accessToken = access;
    if (refresh != null) refreshToken = refresh;
    try {
      if (accessToken != null) {
        await _storage.write(key: _accessKey, value: accessToken);
      }
      if (refreshToken != null) {
        await _storage.write(key: _refreshKey, value: refreshToken);
      }
    } catch (_) {
      // Le stockage sécurisé est optionnel : la session reste valable en mémoire.
    }
  }

  Future<void> clearTokens() async {
    accessToken = null;
    refreshToken = null;
    try {
      await _storage.delete(key: _accessKey);
      await _storage.delete(key: _refreshKey);
    } catch (_) {}
  }

  /// En-têtes d'authentification (ex. pour `Image.network` sur un fichier protégé).
  Map<String, String> get authHeaders =>
      accessToken == null ? const {} : {'Authorization': 'Bearer $accessToken'};

  Uri uri(String path, [Map<String, dynamic>? query]) {
    final cleanQuery = <String, String>{};
    query?.forEach((k, v) {
      if (v != null) cleanQuery[k] = '$v';
    });
    return Uri.parse('${baseUrl.replaceFirst(RegExp(r'/$'), '')}$path')
        .replace(queryParameters: cleanQuery.isEmpty ? null : cleanQuery);
  }

  // ---------------------------------------------------------------------------
  // Requêtes JSON
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> request(String method, String path,
      {Map<String, dynamic>? body,
      Map<String, dynamic>? query,
      bool authenticated = true}) {
    return _withRefresh(authenticated, () async {
      final request = http.Request(method, uri(path, query));
      request.headers['Accept'] = 'application/json';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      if (authenticated && accessToken != null) {
        request.headers['Authorization'] = 'Bearer $accessToken';
      }
      return _http.send(request).timeout(const Duration(seconds: 25));
    });
  }

  /// Envoi multipart (champs texte + fichiers), avec progression optionnelle.
  Future<Map<String, dynamic>> upload(
    String path, {
    Map<String, String> fields = const {},
    List<UploadFile> files = const [],
    String method = 'POST',
    void Function(double progress)? onProgress,
  }) {
    return _withRefresh(true, () async {
      final multipart = http.MultipartRequest(method, uri(path));
      multipart.fields.addAll(fields);
      for (final f in files) {
        multipart.files.add(
            http.MultipartFile.fromBytes(f.field, f.bytes, filename: f.filename));
      }
      final total = multipart.contentLength;
      var sent = 0;
      final byteStream = multipart.finalize().transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (chunk, sink) {
            sent += chunk.length;
            if (onProgress != null && total > 0) onProgress(sent / total);
            sink.add(chunk);
          },
        ),
      );
      final streamed = http.StreamedRequest(method, multipart.url)
        ..headers.addAll(multipart.headers)
        ..contentLength = total;
      streamed.headers['Accept'] = 'application/json';
      if (accessToken != null) {
        streamed.headers['Authorization'] = 'Bearer $accessToken';
      }
      final responseFuture = _http.send(streamed);
      await byteStream.pipe(streamed.sink);
      return responseFuture.timeout(const Duration(seconds: 120));
    });
  }

  // ---------------------------------------------------------------------------
  // Interne
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _withRefresh(
    bool authenticated,
    Future<http.StreamedResponse> Function() send,
  ) async {
    var response = await send();
    if (authenticated && response.statusCode == 401 && refreshToken != null) {
      final raw = await response.stream.bytesToString();
      final error = _decode(raw)['error'];
      final code = error is Map ? error['code']?.toString() : null;
      if (code == 'TOKEN_EXPIRED' || code == 'INVALID_TOKEN') {
        final refreshed = await _refreshAccessToken();
        if (!refreshed) {
          onSessionExpired?.call();
          throw const ApiException(
              'Votre session a expiré. Veuillez vous reconnecter.',
              401,
              'SESSION_EXPIRED');
        }
        response = await send();
      } else {
        if (code == 'TOKEN_REVOKED' || code == 'UNAUTHORIZED') {
          onSessionExpired?.call();
        }
        return _parse(401, raw);
      }
    }
    final raw = await response.stream.bytesToString();
    return _parse(response.statusCode, raw);
  }

  /// Renouvelle le jeton d'accès (utilisé aussi par la connexion temps réel).
  Future<bool> refreshAccessToken() =>
      refreshToken == null ? Future.value(false) : _refreshAccessToken();

  Future<bool> _refreshAccessToken() async {
    _refreshing ??= () async {
      try {
        final request = http.Request('POST', uri('/api/auth/refresh'))
          ..headers['Accept'] = 'application/json'
          ..headers['Authorization'] = 'Bearer $refreshToken';
        final response =
            await _http.send(request).timeout(const Duration(seconds: 20));
        final json = _decode(await response.stream.bytesToString());
        final data = json['data'];
        if (response.statusCode == 200 &&
            data is Map &&
            data['accessToken'] != null) {
          await saveTokens(access: data['accessToken'].toString());
        } else {
          await clearTokens();
        }
      } catch (_) {
        // Réseau indisponible : on conserve les jetons pour réessayer plus tard.
      }
    }();
    try {
      await _refreshing;
    } finally {
      _refreshing = null;
    }
    return accessToken != null && refreshToken != null;
  }

  Map<String, dynamic> _decode(String raw) {
    if (raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Map<String, dynamic> _parse(int statusCode, String raw) {
    final json = _decode(raw);
    if (statusCode < 200 || statusCode >= 300 || json['success'] == false) {
      final error = json['error'];
      final message = (error is Map ? error['message'] : null) ??
          json['message'] ??
          'Erreur serveur ($statusCode)';
      final code = (error is Map ? error['code'] : null) ?? json['code'];
      final details = error is Map && error['details'] is Map
          ? Map<String, dynamic>.from(error['details'] as Map)
          : null;
      throw ApiException(
          message.toString(), statusCode, code?.toString(), details);
    }
    final data = json['data'];
    final result =
        data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    if (json['message'] != null && !result.containsKey('message')) {
      result['message'] = json['message'];
    }
    return result;
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final String? code;
  final Map<String, dynamic>? details;
  const ApiException(this.message, this.statusCode, this.code, [this.details]);
  @override
  String toString() => message;
}

/// Flux qui interroge l'API à intervalle régulier (remplace les
/// `snapshots()` Firestore). L'interrogation s'arrête dès que plus personne
/// n'écoute le flux.
Stream<T> pollApi<T>(Future<T> Function() fetch,
    {Duration interval = const Duration(seconds: 4)}) {
  late StreamController<T> controller;
  Timer? timer;
  var busy = false;

  Future<void> tick() async {
    if (busy || controller.isClosed) return;
    busy = true;
    try {
      final value = await fetch();
      if (!controller.isClosed) controller.add(value);
    } catch (e, st) {
      if (!controller.isClosed) controller.addError(e, st);
    } finally {
      busy = false;
    }
  }

  controller = StreamController<T>(
    onListen: () {
      tick();
      timer = Timer.periodic(interval, (_) => tick());
    },
    onCancel: () {
      timer?.cancel();
      return controller.close();
    },
  );
  return controller.stream;
}

/// Lit un nombre (int/double/chaîne) renvoyé par l'API.
num? asNum(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

/// Lit une date ISO 8601 renvoyée par l'API (UTC sans fuseau côté serveur).
DateTime? asDate(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  final hasZone =
      value.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(value);
  return DateTime.tryParse(hasZone ? value : '${value}Z')?.toLocal();
}

/// Message lisible pour l'utilisateur à partir d'une erreur quelconque.
String errorMessage(Object error) {
  if (error is ApiException) return error.message;
  if (error is TimeoutException) {
    return 'Le serveur Moovi ne répond pas. Vérifiez votre connexion.';
  }
  return 'Connexion au serveur Moovi impossible. Vérifiez votre réseau.';
}
