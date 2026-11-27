import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'driver_service.dart';
import 'session.dart';

/// Authentification via l'API Moovi (OTP WhatsApp/SMS, email, JWT).
class AuthService {
  AuthService._() {
    ApiClient.instance.onSessionExpired = () {
      if (AppSession.instance.currentUser != null) _clearLocal();
    };
  }
  static final instance = AuthService._();

  static const _userKey = 'moovi_user';
  static const _storage = FlutterSecureStorage();

  AppUser? get currentUser => AppSession.instance.currentUser;
  String? _pendingPhone;

  /// Dernier code OTP renvoyé par l'API en mode développement
  /// (`OTP_DEBUG_RETURN_CODE=true`), sinon null.
  String? lastDebugOtp;

  /// Restaure la session enregistrée au démarrage de l'application.
  Future<void> restoreSession() async {
    await ApiClient.instance.loadTokens();
    if (ApiClient.instance.accessToken == null) return;

    // Affiche immédiatement l'utilisateur mis en cache, puis le rafraîchit.
    try {
      final cached = await _storage.read(key: _userKey);
      if (cached != null) {
        AppSession.instance.setUser(AppUser.fromJson(
            Map<String, dynamic>.from(jsonDecode(cached) as Map)));
      }
    } catch (_) {}

    try {
      await refreshProfile().timeout(const Duration(seconds: 8));
    } on ApiException catch (e) {
      if (e.statusCode == 401) await _clearLocal();
    } catch (_) {
      // Hors ligne : on garde l'utilisateur en cache.
    }
  }

  /// Recharge le profil depuis `GET /api/auth/me`.
  Future<AppUser> refreshProfile() async {
    final data = await ApiClient.instance.request('GET', '/api/auth/me');
    return _setUser(data);
  }

  /// Met à jour l'utilisateur courant à partir d'une réponse de l'API.
  AppUser updateUserFromJson(Map<String, dynamic> json) => _setUser(json);

  Future<AppUser> register(
          {required String fullname,
          required String email,
          required String password,
          String? referralCode}) async =>
      _apply(await ApiClient.instance.request('POST', '/api/auth/register',
          authenticated: false,
          body: {
            'fullname': fullname,
            'email': email.trim(),
            'password': password,
            if (referralCode != null && referralCode.isNotEmpty)
              'referralCode': referralCode,
          }));

  Future<AppUser> login(
          {required String email, required String password}) async =>
      _apply(await ApiClient.instance.request('POST', '/api/auth/login',
          authenticated: false,
          body: {'email': email.trim(), 'password': password}));

  /// Demande l'envoi d'un code OTP (WhatsApp via WAHA côté API).
  Future<void> sendOTP(String phoneNumber) async {
    _pendingPhone = phoneNumber;
    final data = await ApiClient.instance.request('POST', '/api/auth/otp/send',
        authenticated: false, body: {'phoneNumber': phoneNumber});
    lastDebugOtp = data['debugOtp']?.toString();
  }

  /// Vérifie le code OTP. Lève une [ApiException] avec le message de l'API
  /// (code incorrect, expiré, trop de tentatives…).
  Future<AppUser> verifyOTPOrThrow(String code) async {
    if (_pendingPhone == null) {
      throw const ApiException(
          'Aucun code demandé pour ce numéro.', 400, 'NO_PENDING_OTP');
    }
    return _apply(await ApiClient.instance.request('POST', '/api/auth/otp/verify',
        authenticated: false,
        body: {'phoneNumber': _pendingPhone, 'code': code}));
  }

  Future<bool> verifyOTP(String code) async {
    try {
      await verifyOTPOrThrow(code);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<AppUser> _apply(Map<String, dynamic> data) async {
    await ApiClient.instance.saveTokens(
      access: data['accessToken']?.toString(),
      refresh: data['refreshToken']?.toString(),
    );
    return _setUser(Map<String, dynamic>.from(data['user'] as Map? ?? const {}));
  }

  AppUser _setUser(Map<String, dynamic> json) {
    final user = AppUser.fromJson(json);
    AppSession.instance.setUser(user);
    _storage.write(key: _userKey, value: jsonEncode(json)).catchError((_) {});
    return user;
  }

  Future<void> logout() async {
    // Chauffeur : hors ligne AVANT de révoquer les jetons (après, la requête
    // ne serait plus authentifiée et il resterait « en ligne » côté serveur).
    final driver = DriverService.instance;
    driver.stopLocationHeartbeat();
    if (driver.cachedDriver != null) {
      try {
        await driver.setAvailability(isOnline: false);
      } catch (_) {}
    }
    try {
      await ApiClient.instance.request('POST', '/api/auth/logout',
          body: {'refreshToken': ApiClient.instance.refreshToken});
    } catch (_) {}
    await _clearLocal();
  }

  /// Désactive et anonymise le compte (`DELETE /api/users/me`).
  Future<void> deleteAccount() async {
    await ApiClient.instance.request('DELETE', '/api/users/me');
    await _clearLocal();
  }

  Future<void> _clearLocal() async {
    DriverService.instance.stopLocationHeartbeat();
    DriverService.instance.cachedDriver = null;
    await ApiClient.instance.clearTokens();
    try {
      await _storage.delete(key: _userKey);
    } catch (_) {}
    AppSession.instance.setUser(null);
  }
}
