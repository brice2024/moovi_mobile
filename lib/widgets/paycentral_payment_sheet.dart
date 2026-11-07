import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/paycentral_service.dart';
import '../services/driver_service.dart';
import '../theme/app_colors.dart';

enum PaymentMethodType {
  airtelMoney,
  moovMoney,
  cash,
}

/// Affiche la feuille de paiement PayCentral (Airtel Money, Moov Money, Cash)
Future<bool?> showPayCentralPaymentSheet({
  required BuildContext context,
  required String rideId,
  required int amount,
  required String departureAddress,
  required String destinationAddress,
  String? defaultPhone,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.55),
    builder: (_) => PayCentralPaymentSheet(
      rideId: rideId,
      amount: amount,
      departureAddress: departureAddress,
      destinationAddress: destinationAddress,
      defaultPhone: defaultPhone,
    ),
  );
}

class PayCentralPaymentSheet extends StatefulWidget {
  final String rideId;
  final int amount;
  final String departureAddress;
  final String destinationAddress;
  final String? defaultPhone;

  const PayCentralPaymentSheet({
    super.key,
    required this.rideId,
    required this.amount,
    required this.departureAddress,
    required this.destinationAddress,
    this.defaultPhone,
  });

  @override
  State<PayCentralPaymentSheet> createState() => _PayCentralPaymentSheetState();
}

class _PayCentralPaymentSheetState extends State<PayCentralPaymentSheet> {
  PaymentMethodType _selectedMethod = PaymentMethodType.airtelMoney;
  late final TextEditingController _phoneController;

  // États du flux de paiement
  bool _isLoading = false;
  bool _isPolling = false;
  String? _transactionId;
  String? _statusMessage;
  String? _errorMessage;
  bool _isSuccess = false;

  StreamSubscription<PayCentralStatusResult>? _pollingSubscription;

  @override
  void initState() {
    super.initState();
    // Numéro par défaut ou utilisateur connecté
    final userPhone = widget.defaultPhone ?? FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
    var initial = userPhone.replaceAll('+241', '').replaceAll(' ', '');
    if (initial.isEmpty) initial = '07123456'; // Suggestion Gabon pour test
    _phoneController = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _pollingSubscription?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  String get _providerName {
    switch (_selectedMethod) {
      case PaymentMethodType.airtelMoney:
        return 'airtel';
      case PaymentMethodType.moovMoney:
        return 'moov';
      case PaymentMethodType.cash:
        return 'cash';
    }
  }

  String get _providerLabel {
    switch (_selectedMethod) {
      case PaymentMethodType.airtelMoney:
        return 'Airtel Money Gabon';
      case PaymentMethodType.moovMoney:
        return 'Moov Money Gabon';
      case PaymentMethodType.cash:
        return 'Paiement en Espèces';
    }
  }

  Future<void> _handlePayment() async {
    setState(() {
      _errorMessage = null;
    });

    // Cas Espèces
    if (_selectedMethod == PaymentMethodType.cash) {
      await DriverService.instance.markRideAsPaid(
        rideId: widget.rideId,
        paymentMethod: 'cash',
        amount: widget.amount,
        provider: 'cash',
      );
      if (!mounted) return;
      setState(() {
        _isSuccess = true;
      });
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.pop(context, true);
      return;
    }

    // Cas PayCentral (Airtel / Moov Money)
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMessage = 'Veuillez saisir votre numéro Mobile Money');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Connexion à PayCentral en cours...';
    });

    final reference = 'MOOVI-${widget.rideId.substring(0, widget.rideId.length.clamp(0, 8))}-${DateTime.now().millisecondsSinceEpoch}';

    final result = await PayCentralService.instance.initiatePayment(
      amount: widget.amount,
      phone: phone,
      description: 'Course Moovi : ${widget.departureAddress} -> ${widget.destinationAddress}',
      merchantReference: reference,
      provider: _providerName,
    );

    if (!mounted) return;

    if (!result.success || result.transactionId == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = result.errorMessage ?? result.message ?? 'Échec de l\'envoi de la demande de paiement.';
      });
      return;
    }

    // Demande envoyée, attente de confirmation du client (saisie du PIN sur mobile)
    final txId = result.transactionId!;
    setState(() {
      _isLoading = false;
      _isPolling = true;
      _transactionId = txId;
      _statusMessage = result.message ??
          'Une demande de débit de ${widget.amount} FCFA a été envoyée sur votre téléphone.\nConfirmez en saisissant votre code PIN.';
    });

    // Lancement du polling de statut
    _pollingSubscription = PayCentralService.instance
        .pollPaymentStatus(
          transactionId: txId,
          interval: const Duration(seconds: 4),
          maxAttempts: 25,
        )
        .listen((statusResult) async {
          if (!mounted) return;

          if (statusResult.isCompleted) {
            _pollingSubscription?.cancel();
            await DriverService.instance.markRideAsPaid(
              rideId: widget.rideId,
              paymentMethod: 'paycentral',
              transactionId: txId,
              amount: widget.amount,
              provider: _providerName,
            );
            if (!mounted) return;
            setState(() {
              _isPolling = false;
              _isSuccess = true;
            });
            await Future.delayed(const Duration(seconds: 2));
            if (mounted) Navigator.pop(context, true);
          } else if (statusResult.isFailed) {
            _pollingSubscription?.cancel();
            setState(() {
              _isPolling = false;
              _errorMessage = statusResult.message ?? 'Le paiement a été refusé ou annulé.';
            });
          }
        }, onError: (e) {
          if (!mounted) return;
          setState(() {
            _isPolling = false;
            _errorMessage = 'Erreur de communication : $e';
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Écran de succès
            if (_isSuccess) ...[
              _buildSuccessView(),
            ] else if (_isPolling) ...[
              _buildPollingView(),
            ] else ...[
              _buildFormView(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFormView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Règlement de la course',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.background,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'PayCentral',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Total à régler au Gabon (FCFA)',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 14),

        // Carte récapitulative du montant
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MONTANT TOTAL',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.amount} FCFA',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const Icon(
                Icons.account_balance_wallet_rounded,
                size: 36,
                color: AppColors.primary,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        const Text(
          'Moyen de paiement',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.background,
          ),
        ),
        const SizedBox(height: 12),

        // Options de paiement
        _buildMethodOption(
          type: PaymentMethodType.airtelMoney,
          title: 'Airtel Money Gabon',
          subtitle: 'Débit instantané (07x)',
          icon: Icons.phone_android_rounded,
          color: Colors.red.shade700,
        ),
        const SizedBox(height: 8),
        _buildMethodOption(
          type: PaymentMethodType.moovMoney,
          title: 'Moov Money Gabon',
          subtitle: 'Débit instantané (06x)',
          icon: Icons.phone_android_rounded,
          color: Colors.blue.shade800,
        ),
        const SizedBox(height: 8),
        _buildMethodOption(
          type: PaymentMethodType.cash,
          title: 'Espèces (Cash)',
          subtitle: 'Payer directement au chauffeur',
          icon: Icons.payments_rounded,
          color: Colors.green.shade700,
        ),

        const SizedBox(height: 18),

        // Champ numéro Mobile Money
        if (_selectedMethod != PaymentMethodType.cash) ...[
          const Text(
            'Numéro Mobile Money (Gabon)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.background,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                const Text(
                  '+241',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.background,
                  ),
                ),
                const SizedBox(width: 10),
                Container(width: 1, height: 24, color: Colors.grey.shade300),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Ex: 07 12 34 56',
                    ),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Compatible Airtel Money (07...) et Moov Money (06...) via PayCentral',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 18),
        ],

        // Message d'erreur éventuel
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Bouton de confirmation
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handlePayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : Text(
                    _selectedMethod == PaymentMethodType.cash
                        ? 'Valider le paiement en espèces'
                        : 'Payer ${widget.amount} FCFA',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildMethodOption({
    required PaymentMethodType type,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedMethod == type;
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: AppColors.background,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Radio<PaymentMethodType>(
              value: type,
              groupValue: _selectedMethod,
              activeColor: AppColors.primary,
              onChanged: (val) {
                if (val != null) setState(() => _selectedMethod = val);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPollingView() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                backgroundColor: AppColors.primary.withOpacity(0.15),
              ),
            ),
            const Icon(
              Icons.phone_iphone_rounded,
              size: 40,
              color: AppColors.primary,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Confirmation sur votre téléphone',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.background,
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _statusMessage ?? 'Veuillez saisir votre code secret PIN pour confirmer la transaction PayCentral.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Montant : ${widget.amount} FCFA • $_providerLabel',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 28),
        OutlinedButton(
          onPressed: () {
            _pollingSubscription?.cancel();
            setState(() {
              _isPolling = false;
            });
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.grey.shade800,
            side: BorderSide(color: Colors.grey.shade400),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Annuler ou changer de méthode'),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildSuccessView() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Container(
          width: 80,
          height: 80,
          decoration: const BoxDecoration(
            color: Color(0xFFE8F5E9),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            size: 54,
            color: Color(0xFF2E7D32),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Paiement Confirmé !',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: AppColors.background,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Votre course de ${widget.amount} FCFA a été réglée avec succès.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 14),
        if (_transactionId != null)
          Text(
            'Réf PayCentral : $_transactionId',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

