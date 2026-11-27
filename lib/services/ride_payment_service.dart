import 'dart:async';
import 'api_client.dart';

/// Résultat de l'envoi d'une demande de paiement Mobile Money (PawaPay).
class RidePaymentInitiateResult {
  final bool success;
  final String? depositId;
  final String? status;
  final String? message;
  final bool simulated;
  final String? errorMessage;

  /// Vrai si la course est déjà réglée (ex. prise en charge totale par Moovi).
  final bool alreadySettled;

  const RidePaymentInitiateResult({
    required this.success,
    this.depositId,
    this.status,
    this.message,
    this.simulated = false,
    this.errorMessage,
    this.alreadySettled = false,
  });

  factory RidePaymentInitiateResult.fromJson(Map<String, dynamic> json) {
    final ride = json['ride'];
    return RidePaymentInitiateResult(
      success: true,
      depositId: json['depositId']?.toString(),
      status: json['status']?.toString(),
      message: json['message']?.toString(),
      simulated: json['simulated'] == true,
      alreadySettled: ride is Map && ride['isPaid'] == true,
    );
  }

  factory RidePaymentInitiateResult.error(String message) =>
      RidePaymentInitiateResult(success: false, errorMessage: message);
}

/// Statut d'un paiement (COMPLETED / FAILED / en attente), normalisé par l'API.
class RidePaymentStatus {
  final String status;
  final String? message;
  const RidePaymentStatus({required this.status, this.message});

  bool get isCompleted => status.toUpperCase() == 'COMPLETED';

  /// Débit reçu alors que la course était déjà réglée (remboursement prévu).
  bool get isDuplicate => status.toUpperCase() == 'DUPLICATE';
  bool get isFailed => const ['FAILED', 'REJECTED', 'CANCELLED', 'TIMEOUT']
      .contains(status.toUpperCase());

  factory RidePaymentStatus.fromJson(Map<String, dynamic> json) => RidePaymentStatus(
      status: json['status']?.toString() ?? 'SUBMITTED',
      message: json['message']?.toString());
}

/// Paiement d'une course par le passager : Airtel Money / Moov Money via
/// PawaPay. Le jeton PawaPay reste dans le `.env` de l'API, qui initie le
/// débit, vérifie le statut et marque la course payée (commission incluse).
class RidePaymentService {
  RidePaymentService._();
  static final instance = RidePaymentService._();

  /// `POST /api/rides/{rideId}/pay/mobile-money`
  Future<RidePaymentInitiateResult> initiatePayment({
    required String rideId,
    required String phoneNumber,
    required String operatorCode,
    String country = 'GAB',
  }) async {
    try {
      return RidePaymentInitiateResult.fromJson(await ApiClient.instance.request(
          'POST', '/api/rides/$rideId/pay/mobile-money', body: {
        'phoneNumber': phoneNumber,
        'operatorCode': operatorCode,
        'country': country,
      }));
    } on ApiException catch (e) {
      // Une demande est déjà en attente sur le téléphone : on la reprend au
      // lieu d'en créer une seconde (qui pourrait débiter deux fois).
      final pending = e.details?['depositId']?.toString();
      if (e.code == 'PAYMENT_PENDING' && pending != null) {
        return RidePaymentInitiateResult(
          success: true,
          depositId: pending,
          status: 'SUBMITTED',
          message: 'Une demande de paiement est déjà en attente : validez-la sur votre téléphone.',
        );
      }
      return RidePaymentInitiateResult.error(e.message);
    } catch (e) {
      return RidePaymentInitiateResult.error(errorMessage(e));
    }
  }

  /// `GET /api/payments/mobile-money/{depositId}/status`
  Future<RidePaymentStatus> checkStatus(String depositId) async {
    try {
      return RidePaymentStatus.fromJson(await ApiClient.instance
          .request('GET', '/api/payments/mobile-money/$depositId/status'));
    } on ApiException catch (e) {
      // 5xx / 429 : panne passagère, le paiement peut encore aboutir.
      if (e.statusCode >= 500 || e.statusCode == 429) {
        return RidePaymentStatus(status: 'SUBMITTED', message: e.message);
      }
      return RidePaymentStatus(status: 'FAILED', message: e.message);
    } catch (e) {
      // Erreur réseau passagère : on continue de vérifier.
      return RidePaymentStatus(status: 'SUBMITTED', message: errorMessage(e));
    }
  }

  Stream<RidePaymentStatus> pollStatus(
      {required String depositId,
      Duration interval = const Duration(seconds: 4),
      int maxAttempts = 30}) async* {
    for (var i = 0; i < maxAttempts; i++) {
      final result = await checkStatus(depositId);
      yield result;
      if (result.isCompleted || result.isFailed || result.isDuplicate) return;
      await Future<void>.delayed(interval);
    }
    yield const RidePaymentStatus(
      status: 'TIMEOUT',
      message: 'Le délai de validation sur votre téléphone a expiré.',
    );
  }
}
