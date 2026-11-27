import 'dart:async';

import 'api_client.dart';

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
      PawaPayOperator(code: 'AIRTEL_COD', name: 'Airtel Money RDC', brand: 'airtel', prefix: '99'),
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
      PawaPayOperator(code: 'VODAFONE_GHA', name: 'Telecel Cash', brand: 'telecel', prefix: '20'),
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
      PawaPayOperator(code: 'AIRTEL_OAPI_UGA', name: 'Airtel Money Uganda', brand: 'airtel', prefix: '075'),
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
      PawaPayOperator(code: 'AIRTEL_OAPI_ZMB', name: 'Airtel Money Zambia', brand: 'airtel', prefix: '097'),
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
      PawaPayOperator(code: 'VODACOM_MOZ', name: 'M-Pesa Vodacom', brand: 'vodacom', prefix: '84'),
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

/// Résultat d'une initiation / vérification de dépôt PawaPay
class PawaPayDepositResult {
  final bool success;
  final String depositId;
  final String status;
  final String? rejectionReason;
  final String? errorMessage;
  final bool isSimulated;
  final double? walletBalance;

  const PawaPayDepositResult({
    required this.success,
    required this.depositId,
    required this.status,
    this.rejectionReason,
    this.errorMessage,
    this.isSimulated = false,
    this.walletBalance,
  });

  bool get isCompleted => status.toUpperCase() == 'COMPLETED';
  bool get isFailed => const {
        'FAILED',
        'REJECTED',
        'EXPIRED',
        'CANCELLED',
        'TIMEOUT',
        'ERROR',
      }.contains(status.toUpperCase());
  bool get isPending =>
      status.toUpperCase() == 'ACCEPTED' ||
      status.toUpperCase() == 'SUBMITTED' ||
      status.toUpperCase() == 'PROCESSING';
}

/// Recharge du portefeuille chauffeur via PawaPay, **par l'intermédiaire de
/// l'API Moovi**. Le jeton PawaPay est stocké dans le `.env` de l'API et
/// n'est plus embarqué dans l'application ; c'est l'API qui crédite le solde
/// (webhook ou vérification de statut), jamais l'application.
class PawaPayService {
  PawaPayService._();
  static final PawaPayService instance = PawaPayService._();

  /// Environnement PawaPay configuré côté API : production | sandbox | simulation.
  String environment = 'production';

  bool get isProduction => environment == 'production';
  bool get isSimulation => environment == 'simulation';

  /// Pays / opérateurs acceptés par l'API (sous-ensemble de [kPawaPayCountries]).
  List<PawaPayCountry> countries = kPawaPayCountries;

  /// Charge l'environnement PawaPay et la liste des opérateurs acceptés par
  /// le serveur, pour ne proposer que des combinaisons valides.
  Future<void> loadConfiguration() async {
    try {
      final data = await ApiClient.instance.request('GET', '/api/wallet/countries');
      environment = data['environment']?.toString() ?? environment;
      final allowed = <String, Set<String>>{};
      for (final c in (data['countries'] as List? ?? const [])) {
        if (c is! Map) continue;
        allowed[c['code'].toString()] = {
          for (final op in (c['operators'] as List? ?? const []))
            if (op is Map) op['code'].toString(),
        };
      }
      if (allowed.isEmpty) return;
      final filtered = <PawaPayCountry>[];
      for (final country in kPawaPayCountries) {
        final codes = allowed[country.code];
        if (codes == null) continue;
        final ops = country.operators.where((o) => codes.contains(o.code)).toList();
        if (ops.isEmpty) continue;
        filtered.add(PawaPayCountry(
          code: country.code,
          name: country.name,
          flag: country.flag,
          dialCode: country.dialCode,
          currency: country.currency,
          operators: ops,
          suggestedAmounts: country.suggestedAmounts,
        ));
      }
      if (filtered.isNotEmpty) countries = filtered;
    } catch (_) {}
  }

  /// Trouve un pays par son code (ex: GAB, CMR, CIV)
  static PawaPayCountry findCountry(String countryCode) {
    final list = PawaPayService.instance.countries;
    return list.firstWhere(
      (c) => c.code.toUpperCase() == countryCode.toUpperCase(),
      orElse: () => list.firstWhere((c) => c.code == 'GAB',
          orElse: () => list.first),
    );
  }

  /// Détecte le pays à partir d'un numéro de téléphone international
  static PawaPayCountry detectCountryFromPhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    for (final country in PawaPayService.instance.countries) {
      if (cleaned.startsWith(country.dialCode) ||
          cleaned.startsWith(country.dialCode.replaceAll('+', ''))) {
        return country;
      }
    }
    return findCountry('GAB'); // Gabon par défaut
  }

  /// Retourne un numéro de test Sandbox officiel PawaPay pour simuler un succès
  static String getSandboxTestNumber(String countryCode) {
    switch (countryCode.toUpperCase()) {
      case 'TGO':
        return '90345678';
      case 'GAB':
        return '74345678';
      case 'CMR':
        return '653456789';
      case 'CIV':
        return '0503456789';
      case 'BEN':
        return '51345789';
      case 'SEN':
        return '773456789';
      default:
        return '90345678';
    }
  }

  /// Initie une recharge (`POST /api/wallet/recharge`).
  Future<PawaPayDepositResult> initiateDeposit({
    required int amount,
    required String phoneNumber,
    required PawaPayCountry country,
    required PawaPayOperator operator,
    String description = 'Recharge Moovi',
  }) async {
    try {
      final data = await ApiClient.instance.request('POST', '/api/wallet/recharge', body: {
        'amount': amount,
        'country': country.code,
        'operatorCode': operator.code,
        'phoneNumber': phoneNumber,
      });
      return PawaPayDepositResult(
        success: true,
        depositId: data['depositId']?.toString() ?? '',
        status: data['gatewayStatus']?.toString() ?? 'SUBMITTED',
        isSimulated: data['simulated'] == true,
      );
    } catch (e) {
      return PawaPayDepositResult(
        success: false,
        depositId: '',
        status: 'FAILED',
        errorMessage: errorMessage(e),
      );
    }
  }

  /// Vérifie l'état d'un dépôt (`GET /api/wallet/recharge/{id}/status`).
  Future<PawaPayDepositResult> checkDepositStatus(String depositId) async {
    try {
      final data = await ApiClient.instance
          .request('GET', '/api/wallet/recharge/$depositId/status');
      final tx = data['transaction'];
      return PawaPayDepositResult(
        success: data['status']?.toString().toUpperCase() == 'COMPLETED',
        depositId: depositId,
        status: data['status']?.toString() ?? 'SUBMITTED',
        isSimulated: data['simulated'] == true,
        walletBalance: asNum(data['walletBalance'])?.toDouble(),
        rejectionReason: tx is Map && tx['status'] == 'failed'
            ? 'Paiement refusé ou annulé.'
            : null,
      );
    } catch (e) {
      // Erreur passagère : on continue de sonder.
      return PawaPayDepositResult(
        success: false,
        depositId: depositId,
        status: 'PROCESSING',
        errorMessage: errorMessage(e),
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
    var attempts = 0;
    while (attempts < maxAttempts) {
      attempts++;
      final result = await checkDepositStatus(depositId);
      yield result;
      if (result.isCompleted || result.isFailed) return;
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
