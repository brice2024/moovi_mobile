import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Opérateur Mobile Money supporté par PawaPay
class PawaPayOperator {
  final String code; // Ex: AIRTEL_GAB, MOOV_GAB, MTN_MOMO_CMR
  final String name; // Ex: Airtel Money
  final String brand; // airtel, moov, mtn, orange, wave, vodacom, celtiis, tnm, zamtel, telecel
  final String prefix; // Ex: 07, 06, 67, 69

  const PawaPayOperator({
    required this.code,
    required this.name,
    required this.brand,
    this.prefix = '',
  });
}

/// Pays supporté par PawaPay avec sa devise, indicatif et opérateurs
class PawaPayCountry {
  final String code; // GAB, CMR, CIV, SEN, BEN, TGO, COD, COG, GHA, KEN, RWA, UGA, ZMB, TZA, MOZ, MWI
  final String name;
  final String flag;
  final String dialCode;
  final String currency;
  final List<PawaPayOperator> operators;
  final List<int> suggestedAmounts;

  const PawaPayCountry({
    required this.code,
    required this.name,
    required this.flag,
    required this.dialCode,
    required this.currency,
    required this.operators,
    required this.suggestedAmounts,
  });
}

/// Registre officiel multi-pays PawaPay
const List<PawaPayCountry> kPawaPayCountries = [
  // 1. TOGO (Mixx by yas & Moov Africa)
  PawaPayCountry(
    code: 'TGO',
    name: 'Togo',
    flag: '🇹🇬',
    dialCode: '+228',
    currency: 'XOF',
    suggestedAmounts: [1000, 2000, 5000, 10000],
    operators: [
      PawaPayOperator(
        code: 'TMONEY_TGO',
        name: 'Mixx by yas (T-Money Togocom)',
        brand: 'mixx',
        prefix: '90, 91, 92, 93, 70',
      ),
      PawaPayOperator(
        code: 'MOOV_TGO',
        name: 'Moov Africa Togo (Flooz)',
        brand: 'moov',
        prefix: '96, 97, 98, 99',
      ),
    ],
  ),

  // 2. GABON
  PawaPayCountry(
    code: 'GAB',
    name: 'Gabon',
    flag: '🇬🇦',
    dialCode: '+241',
    currency: 'XAF',
    suggestedAmounts: [2000, 5000, 10000, 20000],
    operators: [
      PawaPayOperator(code: 'AIRTEL_GAB', name: 'Airtel Money Gabon', brand: 'airtel', prefix: '07'),
      PawaPayOperator(code: 'MOOV_GAB', name: 'Moov Money Gabon', brand: 'moov', prefix: '06'),
    ],
  ),

  // 2. CAMEROUN
  PawaPayCountry(
    code: 'CMR',
    name: 'Cameroun',
    flag: '🇨🇲',
    dialCode: '+237',
    currency: 'XAF',
    suggestedAmounts: [2000, 5000, 10000, 25000],
    operators: [
      PawaPayOperator(code: 'MTN_MOMO_CMR', name: 'MTN Mobile Money', brand: 'mtn', prefix: '67'),
      PawaPayOperator(code: 'ORANGE_CMR', name: 'Orange Money', brand: 'orange', prefix: '69'),
    ],
  ),

  // 3. CÔTE D'IVOIRE
  PawaPayCountry(
    code: 'CIV',
    name: 'Côte d\'Ivoire',
    flag: '🇨🇮',
    dialCode: '+225',
    currency: 'XOF',
    suggestedAmounts: [2000, 5000, 10000, 25000],
    operators: [
      PawaPayOperator(code: 'ORANGE_CIV', name: 'Orange Money', brand: 'orange', prefix: '07'),
      PawaPayOperator(code: 'MTN_MOMO_CIV', name: 'MTN MoMo', brand: 'mtn', prefix: '05'),
      PawaPayOperator(code: 'WAVE_CIV', name: 'Wave Côte d\'Ivoire', brand: 'wave', prefix: '01'),
      PawaPayOperator(code: 'MOOV_CIV', name: 'Moov Money', brand: 'moov', prefix: '01'),
    ],
  ),

  // 4. SÉNÉGAL
  PawaPayCountry(
    code: 'SEN',
    name: 'Sénégal',
    flag: '🇸🇳',
    dialCode: '+221',
    currency: 'XOF',
    suggestedAmounts: [2000, 5000, 10000, 20000],
    operators: [
      PawaPayOperator(code: 'ORANGE_SEN', name: 'Orange Money', brand: 'orange', prefix: '77'),
      PawaPayOperator(code: 'WAVE_SEN', name: 'Wave Sénégal', brand: 'wave', prefix: '76'),
      PawaPayOperator(code: 'FREE_SEN', name: 'Free Money', brand: 'free', prefix: '78'),
    ],
  ),

  // 5. BÉNIN
  PawaPayCountry(
    code: 'BEN',
    name: 'Bénin',
    flag: '🇧🇯',
    dialCode: '+229',
    currency: 'XOF',
    suggestedAmounts: [2000, 5000, 10000, 20000],
    operators: [
      PawaPayOperator(code: 'MTN_MOMO_BEN', name: 'MTN MoMo', brand: 'mtn', prefix: '97'),
      PawaPayOperator(code: 'MOOV_BEN', name: 'Moov Money', brand: 'moov', prefix: '95'),
      PawaPayOperator(code: 'CELTIIS_BEN', name: 'Celtiis Cash', brand: 'celtiis', prefix: '40'),
    ],
  ),


  // 7. RD CONGO
  PawaPayCountry(
    code: 'COD',
    name: 'RD Congo',
    flag: '🇨🇩',
    dialCode: '+243',
    currency: 'CDF',
    suggestedAmounts: [5000, 10000, 25000, 50000],
    operators: [
      PawaPayOperator(code: 'VODACOM_MPESA_COD', name: 'Vodacom M-Pesa', brand: 'vodacom', prefix: '81'),
      PawaPayOperator(code: 'AIRTEL_O_COD', name: 'Airtel Money RDC', brand: 'airtel', prefix: '99'),
      PawaPayOperator(code: 'ORANGE_COD', name: 'Orange Money RDC', brand: 'orange', prefix: '89'),
      PawaPayOperator(code: 'AFRIMONEY_COD', name: 'Afrimoney RDC', brand: 'africell', prefix: '90'),
    ],
  ),

  // 8. CONGO BRAZZAVILLE
  PawaPayCountry(
    code: 'COG',
    name: 'Congo-Brazzaville',
    flag: '🇨🇬',
    dialCode: '+242',
    currency: 'XAF',
    suggestedAmounts: [2000, 5000, 10000, 20000],
    operators: [
      PawaPayOperator(code: 'AIRTEL_COG', name: 'Airtel Money Congo', brand: 'airtel', prefix: '05'),
      PawaPayOperator(code: 'MTN_MOMO_COG', name: 'MTN MoMo Congo', brand: 'mtn', prefix: '06'),
    ],
  ),

  // 9. GHANA
  PawaPayCountry(
    code: 'GHA',
    name: 'Ghana',
    flag: '🇬🇭',
    dialCode: '+233',
    currency: 'GHS',
    suggestedAmounts: [50, 100, 250, 500],
    operators: [
      PawaPayOperator(code: 'MTN_MOMO_GHA', name: 'MTN MoMo Ghana', brand: 'mtn', prefix: '24'),
      PawaPayOperator(code: 'AIRTELTIGO_GHA', name: 'AT Money Ghana', brand: 'at', prefix: '26'),
      PawaPayOperator(code: 'TELECEL_GHA', name: 'Telecel Cash', brand: 'telecel', prefix: '20'),
    ],
  ),

  // 10. KENYA
  PawaPayCountry(
    code: 'KEN',
    name: 'Kenya',
    flag: '🇰🇪',
    dialCode: '+254',
    currency: 'KES',
    suggestedAmounts: [500, 1000, 2500, 5000],
    operators: [
      PawaPayOperator(code: 'MPESA_KEN', name: 'Safaricom M-Pesa', brand: 'mpesa', prefix: '07'),
      PawaPayOperator(code: 'AIRTEL_KEN', name: 'Airtel Money Kenya', brand: 'airtel', prefix: '07'),
    ],
  ),

  // 11. RWANDA
  PawaPayCountry(
    code: 'RWA',
    name: 'Rwanda',
    flag: '🇷🇼',
    dialCode: '+250',
    currency: 'RWF',
    suggestedAmounts: [2000, 5000, 10000, 25000],
    operators: [
      PawaPayOperator(code: 'MTN_MOMO_RWA', name: 'MTN MoMo Rwanda', brand: 'mtn', prefix: '078'),
      PawaPayOperator(code: 'AIRTEL_RWA', name: 'Airtel Money Rwanda', brand: 'airtel', prefix: '073'),
    ],
  ),

  // 12. OUGANDA
  PawaPayCountry(
    code: 'UGA',
    name: 'Ouganda',
    flag: '🇺🇬',
    dialCode: '+256',
    currency: 'UGX',
    suggestedAmounts: [10000, 25000, 50000, 100000],
    operators: [
      PawaPayOperator(code: 'MTN_MOMO_UGA', name: 'MTN MoMo Uganda', brand: 'mtn', prefix: '077'),
      PawaPayOperator(code: 'AIRTEL_UGA', name: 'Airtel Money Uganda', brand: 'airtel', prefix: '075'),
    ],
  ),

  // 13. ZAMBIE
  PawaPayCountry(
    code: 'ZMB',
    name: 'Zambie',
    flag: '🇿🇲',
    dialCode: '+260',
    currency: 'ZMW',
    suggestedAmounts: [50, 100, 250, 500],
    operators: [
      PawaPayOperator(code: 'AIRTEL_ZMB', name: 'Airtel Money Zambia', brand: 'airtel', prefix: '097'),
      PawaPayOperator(code: 'MTN_MOMO_ZMB', name: 'MTN MoMo Zambia', brand: 'mtn', prefix: '096'),
      PawaPayOperator(code: 'ZAMTEL_ZMB', name: 'Zamtel Mobile Money', brand: 'zamtel', prefix: '095'),
    ],
  ),

  // 14. TANZANIE
  PawaPayCountry(
    code: 'TZA',
    name: 'Tanzanie',
    flag: '🇹🇿',
    dialCode: '+255',
    currency: 'TZS',
    suggestedAmounts: [10000, 25000, 50000, 100000],
    operators: [
      PawaPayOperator(code: 'VODACOM_TZA', name: 'Vodacom M-Pesa', brand: 'vodacom', prefix: '075'),
      PawaPayOperator(code: 'AIRTEL_TZA', name: 'Airtel Money Tanzania', brand: 'airtel', prefix: '078'),
      PawaPayOperator(code: 'TIGO_TZA', name: 'Tigo Pesa', brand: 'tigo', prefix: '071'),
      PawaPayOperator(code: 'HALOTEL_TZA', name: 'HaloPesa', brand: 'halotel', prefix: '062'),
    ],
  ),

  // 15. MOZAMBIQUE
  PawaPayCountry(
    code: 'MOZ',
    name: 'Mozambique',
    flag: '🇲🇿',
    dialCode: '+258',
    currency: 'MZN',
    suggestedAmounts: [200, 500, 1000, 2000],
    operators: [
      PawaPayOperator(code: 'EMOLA_MOZ', name: 'e-Mola Movitel', brand: 'emola', prefix: '86'),
      PawaPayOperator(code: 'MPESA_MOZ', name: 'M-Pesa Vodacom', brand: 'vodacom', prefix: '84'),
    ],
  ),

  // 16. MALAWI
  PawaPayCountry(
    code: 'MWI',
    name: 'Malawi',
    flag: '🇲🇼',
    dialCode: '+265',
    currency: 'MWK',
    suggestedAmounts: [5000, 10000, 25000, 50000],
    operators: [
      PawaPayOperator(code: 'AIRTEL_MWI', name: 'Airtel Money Malawi', brand: 'airtel', prefix: '099'),
      PawaPayOperator(code: 'TNM_MWI', name: 'TNM Mpamba', brand: 'tnm', prefix: '088'),
    ],
  ),
];

/// Résultat d'une initiation de dépôt PawaPay
class PawaPayDepositResult {
  final bool success;
  final String depositId;
  final String status;
  final String? rejectionReason;
  final String? errorMessage;
  final bool isSimulated;

  const PawaPayDepositResult({
    required this.success,
    required this.depositId,
    required this.status,
    this.rejectionReason,
    this.errorMessage,
    this.isSimulated = false,
  });

  bool get isCompleted => status.toUpperCase() == 'COMPLETED';
  bool get isFailed =>
      status.toUpperCase() == 'FAILED' ||
      status.toUpperCase() == 'REJECTED' ||
      status.toUpperCase() == 'EXPIRED';
  bool get isPending =>
      status.toUpperCase() == 'ACCEPTED' ||
      status.toUpperCase() == 'SUBMITTED' ||
      status.toUpperCase() == 'PROCESSING';
}

/// Service d'intégration universel multi-pays PawaPay
class PawaPayService {
  PawaPayService._();
  static final PawaPayService instance = PawaPayService._();

  static const String sandboxUrl = 'https://api.sandbox.pawapay.cloud';
  static const String productionUrl = 'https://api.pawapay.cloud';

  bool isProduction = false;
  String _apiToken = '';

  String get baseUrl => isProduction ? productionUrl : sandboxUrl;

  void configure({required String apiToken, bool production = false}) {
    _apiToken = apiToken;
    isProduction = production;
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_apiToken',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  /// Trouve un pays par son code (ex: GAB, CMR, CIV)
  static PawaPayCountry findCountry(String countryCode) {
    return kPawaPayCountries.firstWhere(
      (c) => c.code.toUpperCase() == countryCode.toUpperCase(),
      orElse: () => kPawaPayCountries.first,
    );
  }

  /// Détecte le pays à partir d'un numéro de téléphone international
  static PawaPayCountry detectCountryFromPhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    for (final country in kPawaPayCountries) {
      if (cleaned.startsWith(country.dialCode) ||
          cleaned.startsWith(country.dialCode.replaceAll('+', ''))) {
        return country;
      }
    }
    return kPawaPayCountries.first; // Gabon par défaut
  }

  /// Formate le numéro au format international attendu par PawaPay (MSISDN standard sans +)
  static String formatPhoneForPawaPay(String input, PawaPayCountry country) {
    var cleaned = input.replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
    final prefixDigits = country.dialCode.replaceAll('+', '');

    if (cleaned.startsWith(prefixDigits)) {
      return cleaned;
    }

    if (cleaned.startsWith('0')) {
      cleaned = cleaned.substring(1);
    }
    return '$prefixDigits$cleaned';
  }

  /// Retourne un numéro de test Sandbox officiel PawaPay pour simuler un succès
  static String getSandboxTestNumber(String countryCode) {
    switch (countryCode.toUpperCase()) {
      case 'TGO':
        return '90345678'; // 22890345678 -> COMPLETED (Mixx by yas / Togocom & Moov Africa)
      case 'GAB':
        return '74345678'; // 24174345678 -> COMPLETED
      case 'CMR':
        return '653456789'; // 237653456789 -> COMPLETED
      case 'CIV':
        return '0503456789'; // 2250503456789 -> COMPLETED
      case 'BEN':
        return '51345789'; // 22951345789 -> COMPLETED
      case 'SEN':
        return '773456789'; // 221773456789 -> COMPLETED
      default:
        return '90345678';
    }
  }

  /// Génère un UUID v4 standard conforme aux exigences de PawaPay
  static String generateDepositId() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // IETF variant
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// Initie une demande de dépôt (rechargement portefeuille) via PawaPay
  ///
  /// Appel : POST /deposits
  Future<PawaPayDepositResult> initiateDeposit({
    required int amount,
    required String phoneNumber,
    required PawaPayCountry country,
    required PawaPayOperator operator,
    String? depositId,
    String description = 'Recharge Moovi',
  }) async {
    final finalDepositId = depositId ?? generateDepositId();
    final formattedPhone = formatPhoneForPawaPay(phoneNumber, country);

    if (_apiToken.isEmpty) {
      debugPrint('ℹ️ [PawaPay] Mode Simulation Sandbox (${country.name} - ${operator.name})');
      await Future.delayed(const Duration(milliseconds: 1500));
      return PawaPayDepositResult(
        success: true,
        depositId: finalDepositId,
        status: 'SUBMITTED',
        isSimulated: true,
      );
    }

    final safeDescription = description.length > 22
        ? description.substring(0, 22)
        : description;

    final payload = {
      'depositId': finalDepositId,
      'amount': amount.toString(),
      'currency': country.currency,
      'country': country.code,
      'correspondent': operator.code,
      'payer': {
        'type': 'MSISDN',
        'address': {
          'value': formattedPhone,
        },
      },
      'customerTimestamp': DateTime.now().toUtc().toIso8601String(),
      'statementDescription': safeDescription,
    };

    debugPrint('➡️ [PawaPay ${country.name}] Dépôt : ${jsonEncode(payload)}');

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/deposits'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));

      debugPrint('⬅️ [PawaPay] Réponse (${response.statusCode}) : ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic data = jsonDecode(response.body);
        final status = (data is Map ? data['status'] : null)?.toString() ?? 'ACCEPTED';
        return PawaPayDepositResult(
          success: true,
          depositId: finalDepositId,
          status: status,
        );
      } else {
        String errMsg = 'Erreur HTTP ${response.statusCode}';
        try {
          final errData = jsonDecode(response.body);
          if (errData is Map && errData.containsKey('errorMessage')) {
            errMsg = errData['errorMessage'].toString();
          }
        } catch (_) {}
        return PawaPayDepositResult(
          success: false,
          depositId: finalDepositId,
          status: 'FAILED',
          errorMessage: errMsg,
        );
      }
    } on TimeoutException {
      return PawaPayDepositResult(
        success: false,
        depositId: finalDepositId,
        status: 'TIMEOUT',
        errorMessage: 'Délai d\'attente dépassé lors de la connexion à PawaPay',
      );
    } catch (e) {
      debugPrint('❌ [PawaPay] Exception : $e');
      return PawaPayDepositResult(
        success: false,
        depositId: finalDepositId,
        status: 'ERROR',
        errorMessage: 'Erreur réseau : $e',
      );
    }
  }

  /// Vérifie l'état d'un dépôt (GET /deposits/{depositId})
  Future<PawaPayDepositResult> checkDepositStatus(
    String depositId, {
    bool isSimulated = false,
  }) async {
    if (isSimulated || _apiToken.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 1000));
      return PawaPayDepositResult(
        success: true,
        depositId: depositId,
        status: 'COMPLETED',
        isSimulated: true,
      );
    }

    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/deposits/$depositId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic data = jsonDecode(response.body);
        Map<String, dynamic> item = {};
        if (data is List && data.isNotEmpty) {
          item = data.first as Map<String, dynamic>;
        } else if (data is Map<String, dynamic>) {
          item = data;
        }

        final status = item['status']?.toString() ?? 'UNKNOWN';
        final failureReason = item['failureReason']?.toString();

        return PawaPayDepositResult(
          success: status.toUpperCase() == 'COMPLETED',
          depositId: depositId,
          status: status,
          rejectionReason: failureReason,
        );
      } else {
        return PawaPayDepositResult(
          success: false,
          depositId: depositId,
          status: 'FAILED',
          errorMessage: 'Erreur vérification HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      return PawaPayDepositResult(
        success: false,
        depositId: depositId,
        status: 'ERROR',
        errorMessage: 'Erreur réseau : $e',
      );
    }
  }

  /// Sonde (polling) le statut d'une transaction jusqu'à validation finale
  Stream<PawaPayDepositResult> pollDepositStatus({
    required String depositId,
    bool isSimulated = false,
    Duration interval = const Duration(seconds: 4),
    int maxAttempts = 30,
  }) async* {
    int attempts = 0;

    if (isSimulated || _apiToken.isEmpty) {
      yield PawaPayDepositResult(
        success: false,
        depositId: depositId,
        status: 'SUBMITTED',
        isSimulated: true,
      );
      await Future.delayed(const Duration(seconds: 4));
      yield PawaPayDepositResult(
        success: false,
        depositId: depositId,
        status: 'PROCESSING',
        isSimulated: true,
      );
      await Future.delayed(const Duration(seconds: 4));
      yield PawaPayDepositResult(
        success: true,
        depositId: depositId,
        status: 'COMPLETED',
        isSimulated: true,
      );
      return;
    }

    while (attempts < maxAttempts) {
      attempts++;
      final result = await checkDepositStatus(depositId);
      yield result;

      if (result.isCompleted || result.isFailed) {
        return;
      }

      await Future.delayed(interval);
    }

    yield PawaPayDepositResult(
      success: false,
      depositId: depositId,
      status: 'TIMEOUT',
      errorMessage: 'Délai d\'attente de validation USSD dépassé.',
    );
  }
}
