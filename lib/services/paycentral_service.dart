import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Modèle pour le résultat d'initiation d'un paiement PayCentral
class PayCentralInitiateResult {
  final bool success;
  final String? transactionId;
  final String? providerReference;
  final String? status;
  final String? message;
  final int? amount;
  final String? currency;
  final String? provider;
  final String? rawResponse;
  final String? errorMessage;

  const PayCentralInitiateResult({
    required this.success,
    this.transactionId,
    this.providerReference,
    this.status,
    this.message,
    this.amount,
    this.currency,
    this.provider,
    this.rawResponse,
    this.errorMessage,
  });

  factory PayCentralInitiateResult.fromJson(Map<String, dynamic> json) {
    return PayCentralInitiateResult(
      success: json['success'] == true || json['status'] == 'processing' || json['status'] == 'success',
      transactionId: json['transaction_id']?.toString(),
      providerReference: json['provider_reference']?.toString(),
      status: json['status']?.toString() ?? 'processing',
      message: json['message']?.toString(),
      amount: (json['amount'] as num?)?.toInt(),
      currency: json['currency']?.toString() ?? 'XAF',
      provider: json['provider']?.toString(),
      rawResponse: jsonEncode(json),
    );
  }

  factory PayCentralInitiateResult.error(String error) {
    return PayCentralInitiateResult(
      success: false,
      errorMessage: error,
    );
  }
}

/// Modèle pour la vérification du statut d'une transaction PayCentral
class PayCentralStatusResult {
  final bool isSuccess;
  final String status; // 'processing', 'pending', 'success', 'completed', 'failed', 'cancelled'
  final String? message;
  final String? transactionId;
  final int? amount;
  final String? provider;
  final String? rawJson;

  const PayCentralStatusResult({
    required this.isSuccess,
    required this.status,
    this.message,
    this.transactionId,
    this.amount,
    this.provider,
    this.rawJson,
  });

  bool get isCompleted =>
      status.toLowerCase() == 'success' || status.toLowerCase() == 'completed';

  bool get isFailed =>
      status.toLowerCase() == 'failed' || status.toLowerCase() == 'cancelled';

  bool get isProcessing =>
      status.toLowerCase() == 'processing' || status.toLowerCase() == 'pending';

  factory PayCentralStatusResult.fromJson(Map<String, dynamic> json) {
    final statusStr = (json['status'] ?? json['data']?['status'] ?? 'unknown').toString();
    final isDone = statusStr.toLowerCase() == 'success' || statusStr.toLowerCase() == 'completed';

    return PayCentralStatusResult(
      isSuccess: isDone,
      status: statusStr,
      message: json['message']?.toString(),
      transactionId: (json['transaction_id'] ?? json['data']?['transaction_id'])?.toString(),
      amount: (json['amount'] as num?)?.toInt(),
      provider: json['provider']?.toString(),
      rawJson: jsonEncode(json),
    );
  }

  factory PayCentralStatusResult.error(String error) {
    return PayCentralStatusResult(
      isSuccess: false,
      status: 'error',
      message: error,
    );
  }
}

/// Service d'intégration de l'agrégateur de paiement PayCentral (Gabon du Numérique)
///
/// Documentation : https://paycentral.gabondunumerique.com/site/docs/integration.html
class PayCentralService {
  PayCentralService._();
  static final PayCentralService instance = PayCentralService._();

  static const String baseUrl = 'https://api-paycentral.gabondunumerique.com/api/v1';
  static const String defaultApiKey = 'sk_sandbox_7kzpxJCFmXgLvTsgOlNTUm3vY9j48EaVhpZlqafe';

  String _apiKey = defaultApiKey;

  void setApiKey(String key) {
    _apiKey = key;
  }

  Map<String, String> get _headers => {
        'X-Api-Key': _apiKey,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  /// Formate et normalise un numéro de téléphone gabonais vers le format international E.164 (+241...)
  /// Exemples acceptés :
  /// "07 12 34 56" -> "+24107123456"
  /// "06 12 34 56" -> "+24106123456"
  /// "+241 07 12 34 56" -> "+24107123456"
  /// "7123456" -> "+24107123456"
  static String formatGabonPhone(String input) {
    var cleaned = input.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.startsWith('+241')) {
      return cleaned;
    }
    if (cleaned.startsWith('241')) {
      return '+$cleaned';
    }
    if (cleaned.startsWith('0')) {
      return '+241$cleaned';
    }
    // Si l'utilisateur a tapé par ex 7xxxxxx ou 6xxxxxx (7 chiffres)
    if (cleaned.length == 8 && (cleaned.startsWith('7') || cleaned.startsWith('6'))) {
      return '+2410$cleaned';
    }
    return '+241$cleaned';
  }

  /// Détecte le provider Mobile Money Gabon en fonction du préfixe
  /// 07... -> Airtel Money Gabon
  /// 06... -> Moov Money Gabon
  static String detectGabonProvider(String phone) {
    final formatted = formatGabonPhone(phone);
    if (formatted.contains('+24107') || formatted.contains('+2417')) {
      return 'airtel';
    }
    if (formatted.contains('+24106') || formatted.contains('+2416')) {
      return 'moov';
    }
    return 'airtel'; // Par défaut
  }

  /// Initie un paiement Mobile Money direct via PayCentral (POST /payment/initiate)
  Future<PayCentralInitiateResult> initiatePayment({
    required int amount,
    required String phone,
    required String description,
    required String merchantReference,
    String? provider,
  }) async {
    try {
      final formattedPhone = formatGabonPhone(phone);
      final finalProvider = provider ?? detectGabonProvider(formattedPhone);

      final payload = {
        'amount': amount,
        'phone': formattedPhone,
        'description': description,
        'merchant_reference': merchantReference,
        'currency': 'XAF',
        'provider': finalProvider,
      };

      debugPrint('➡️ [PayCentral] Initiation du paiement : ${jsonEncode(payload)}');

      final response = await http
          .post(
            Uri.parse('$baseUrl/payment/initiate'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));

      debugPrint('⬅️ [PayCentral] Réponse code : ${response.statusCode}, corps : ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return PayCentralInitiateResult.fromJson(data);
      } else {
        String errMessage = 'Erreur HTTP ${response.statusCode}';
        try {
          final errJson = jsonDecode(response.body);
          if (errJson is Map && errJson.containsKey('message')) {
            errMessage = errJson['message'].toString();
          }
        } catch (_) {}
        return PayCentralInitiateResult.error(errMessage);
      }
    } on TimeoutException {
      return PayCentralInitiateResult.error('Délai d\'attente dépassé lors de la connexion à PayCentral');
    } catch (e) {
      debugPrint('❌ [PayCentral] Exception initiatePayment : $e');
      return PayCentralInitiateResult.error('Erreur réseau ou connexion : $e');
    }
  }

  /// Vérifie le statut d'un paiement en cours (GET /payment/{transaction_id}/status)
  Future<PayCentralStatusResult> checkPaymentStatus(String transactionId) async {
    try {
      debugPrint('➡️ [PayCentral] Vérification statut pour transaction : $transactionId');

      final response = await http
          .get(
            Uri.parse('$baseUrl/payment/$transactionId/status'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('⬅️ [PayCentral] Statut réponse : ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return PayCentralStatusResult.fromJson(data);
      } else {
        return PayCentralStatusResult.error('Code d\'erreur HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ [PayCentral] Exception checkPaymentStatus : $e');
      return PayCentralStatusResult.error('Erreur de vérification : $e');
    }
  }

  /// Sonde (poll) périodiquement le statut d'une transaction jusqu'à complétion, échec ou timeout.
  Stream<PayCentralStatusResult> pollPaymentStatus({
    required String transactionId,
    Duration interval = const Duration(seconds: 4),
    int maxAttempts = 30, // 30 x 4s = 2 minutes max
  }) async* {
    int attempts = 0;

    while (attempts < maxAttempts) {
      attempts++;
      final result = await checkPaymentStatus(transactionId);
      yield result;

      if (result.isCompleted || result.isFailed) {
        return; // Fin du cycle
      }

      await Future.delayed(interval);
    }

    // Timeout
    yield const PayCentralStatusResult(
      isSuccess: false,
      status: 'timeout',
      message: 'Le délai de validation sur votre téléphone a expiré.',
    );
  }
}

