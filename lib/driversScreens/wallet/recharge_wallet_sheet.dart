import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/pawapay_service.dart';
import '../../services/driver_service.dart';
import '../test/driver_theme.dart';

/// Ouvre le formulaire de rechargement multi-pays PawaPay pour le chauffeur
Future<bool?> showRechargeWalletSheet({
  required BuildContext context,
  required String driverId,
  int? defaultAmount,
  String? defaultCountryCode,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (_) => RechargeWalletSheet(
      driverId: driverId,
      initialAmount: defaultAmount,
      initialCountryCode: defaultCountryCode,
    ),
  );
}

class RechargeWalletSheet extends StatefulWidget {
  final String driverId;
  final int? initialAmount;
  final String? initialCountryCode;

  const RechargeWalletSheet({
    super.key,
    required this.driverId,
    this.initialAmount,
    this.initialCountryCode,
  });

  @override
  State<RechargeWalletSheet> createState() => _RechargeWalletSheetState();
}

class _RechargeWalletSheetState extends State<RechargeWalletSheet> {
  late PawaPayCountry _selectedCountry;
  late PawaPayOperator _selectedOperator;
  late int _selectedAmount;
  late final TextEditingController _amountController;
  late final TextEditingController _phoneController;

  bool _isLoading = false;
  bool _isPolling = false;
  String? _statusMessage;
  String? _errorMessage;
  bool _isSuccess = false;
  StreamSubscription<PawaPayDepositResult>? _pollingSubscription;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    final userPhone = user?.phoneNumber ?? '';

    // Détection initiale du pays
    if (widget.initialCountryCode != null) {
      _selectedCountry = PawaPayService.findCountry(widget.initialCountryCode!);
    } else if (userPhone.isNotEmpty) {
      _selectedCountry = PawaPayService.detectCountryFromPhone(userPhone);
    } else {
      _selectedCountry = kPawaPayCountries.first; // Gabon par défaut
    }

    _selectedOperator = _selectedCountry.operators.first;
    _selectedAmount = widget.initialAmount ?? _selectedCountry.suggestedAmounts[1];
    _amountController = TextEditingController(text: _selectedAmount.toString());

    var phone = userPhone.replaceAll(_selectedCountry.dialCode, '').replaceAll(' ', '');
    if (phone.isEmpty || !PawaPayService.instance.isProduction) {
      phone = PawaPayService.getSandboxTestNumber(_selectedCountry.code);
    }
    _phoneController = TextEditingController(text: phone);
  }

  @override
  void dispose() {
    _pollingSubscription?.cancel();
    _amountController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _onCountryChanged(PawaPayCountry country) {
    setState(() {
      _selectedCountry = country;
      _selectedOperator = country.operators.first;
      _selectedAmount = country.suggestedAmounts[1];
      _amountController.text = _selectedAmount.toString();
      if (!PawaPayService.instance.isProduction) {
        _phoneController.text = PawaPayService.getSandboxTestNumber(country.code);
      }
    });
  }

  Future<void> _handleRecharge() async {
    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _errorMessage = 'Veuillez saisir un montant valide');
      return;
    }

    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMessage = 'Veuillez saisir votre numéro Mobile Money');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = 'Connexion à PawaPay (${_selectedCountry.name})...';
    });

    final depositResult = await PawaPayService.instance.initiateDeposit(
      amount: amount,
      phoneNumber: phone,
      country: _selectedCountry,
      operator: _selectedOperator,
      description: 'Recharge Moovi',
    );

    if (!mounted) return;

    if (!depositResult.success) {
      setState(() {
        _isLoading = false;
        _errorMessage = depositResult.errorMessage ?? 'Échec de l\'envoi de la demande de paiement PawaPay';
      });
      return;
    }

    setState(() {
      _isLoading = false;
      _isPolling = true;
      _statusMessage =
          'Une demande de validation de $amount ${_selectedCountry.currency} a été envoyée sur votre compte ${_selectedOperator.name}.\nVeuillez saisir votre code PIN sur votre téléphone.';
    });

    _pollingSubscription = PawaPayService.instance
        .pollDepositStatus(
          depositId: depositResult.depositId,
          isSimulated: depositResult.isSimulated,
        )
        .listen((status) async {
          if (!mounted) return;

          if (status.isCompleted) {
            _pollingSubscription?.cancel();

            // Créditer le solde du chauffeur dans Firestore
            await DriverService.instance.rechargeDriverWallet(
              driverId: widget.driverId,
              amount: amount,
              depositId: depositResult.depositId,
              operatorCode: _selectedOperator.code,
              operatorName: '${_selectedOperator.name} (${_selectedCountry.flag} ${_selectedCountry.name})',
              phoneNumber: phone,
            );

            if (!mounted) return;
            setState(() {
              _isPolling = false;
              _isSuccess = true;
            });

            await Future.delayed(const Duration(milliseconds: 1800));
            if (mounted) Navigator.pop(context, true);
          } else if (status.isFailed) {
            _pollingSubscription?.cancel();
            setState(() {
              _isPolling = false;
              _errorMessage = status.rejectionReason ?? status.errorMessage ?? 'Paiement refusé ou annulé.';
            });
          }
        }, onError: (err) {
          if (!mounted) return;
          setState(() {
            _isPolling = false;
            _errorMessage = 'Erreur de connexion : $err';
          });
        });
  }

  Color _getOperatorBrandColor(String brand) {
    switch (brand) {
      case 'mixx':
      case 'tmoney':
        return const Color(0xFF005691); // Mixx by yas / Togocom
      case 'airtel':
        return const Color(0xFFE50914);
      case 'moov':
        return const Color(0xFF0D47A1); // Moov Africa
      case 'mtn':
        return const Color(0xFFFFCC00);
      case 'orange':
        return const Color(0xFFFF6600);
      case 'wave':
        return const Color(0xFF1EA6FD);
      case 'vodacom':
        return const Color(0xFFE60000);
      case 'mpesa':
        return const Color(0xFF00A859);
      case 'celtiis':
        return const Color(0xFF0A2540);
      case 'zamtel':
        return const Color(0xFF007A3D);
      case 'telecel':
        return const Color(0xFFE30613);
      case 'at':
        return const Color(0xFF1B365D);
      case 'tnm':
        return const Color(0xFF1C6B38);
      case 'emola':
        return const Color(0xFFF37021);
      case 'halotel':
        return const Color(0xFFE84E1B);
      default:
        return MooviColors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
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

            if (_isSuccess)
              _buildSuccessView()
            else if (_isPolling)
              _buildPollingView()
            else
              _buildFormView(),
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
              'Recharger mon Portefeuille',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: MooviColors.dark,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: PawaPayService.instance.isProduction
                    ? const Color(0xFFE8F5E9)
                    : MooviColors.orangeSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                PawaPayService.instance.isProduction
                    ? 'PawaPay Réel (Live)'
                    : 'PawaPay Sandbox (Test)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: PawaPayService.instance.isProduction
                      ? MooviColors.green
                      : MooviColors.orange,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Rechargez votre compte pour couvrir les commissions Moovi et continuer à accepter des courses.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.3),
        ),
        const SizedBox(height: 16),

        // SÉLECTEUR DE PAYS PAWAPAY
        const Text(
          'PAYS DE RÈGLEMENT (PAWAPAY)',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: MooviColors.grey),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<PawaPayCountry>(
              value: _selectedCountry,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: MooviColors.orange),
              items: kPawaPayCountries.map((country) {
                return DropdownMenuItem<PawaPayCountry>(
                  value: country,
                  child: Row(
                    children: [
                      Text(country.flag, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Text(
                        country.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${country.dialCode} • ${country.currency}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (country) {
                if (country != null) _onCountryChanged(country);
              },
            ),
          ),
        ),

        const SizedBox(height: 16),

        // MONTANTS PRÉDÉFINIS SELON LE PAYS
        Text(
          'MONTANT DE LA RECHARGE (${_selectedCountry.currency})',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: MooviColors.grey),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _selectedCountry.suggestedAmounts.map((amt) {
            final isSelected = _selectedAmount == amt;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedAmount = amt;
                  _amountController.text = amt.toString();
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: isSelected ? MooviColors.orange : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? MooviColors.orange : Colors.grey.shade300,
                  ),
                ),
                child: Text(
                  '$amt ${_selectedCountry.currency}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : MooviColors.dark,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),

        // Saisie montant libre
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              const Icon(Icons.wallet_rounded, size: 20, color: MooviColors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    final parsed = int.tryParse(val) ?? 0;
                    setState(() => _selectedAmount = parsed);
                  },
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Autre montant...',
                  ),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _selectedCountry.currency,
                style: const TextStyle(fontWeight: FontWeight.w800, color: MooviColors.grey),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // SÉLECTION DE L'OPÉRATEUR MOBILE MONEY DU PAYS
        Text(
          'OPÉRATEURS DISPONIBLES EN ${_selectedCountry.name.toUpperCase()}',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: MooviColors.grey),
        ),
        const SizedBox(height: 8),
        Column(
          children: _selectedCountry.operators.map((op) {
            final isSelected = _selectedOperator.code == op.code;
            final brandColor = _getOperatorBrandColor(op.brand);

            return GestureDetector(
              onTap: () => setState(() => _selectedOperator = op),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: isSelected ? MooviColors.orangeSoft : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? MooviColors.orange : Colors.grey.shade300,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: brandColor.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.phone_android_rounded, color: brandColor, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            op.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: MooviColors.dark,
                            ),
                          ),
                          if (op.prefix.isNotEmpty)
                            Text(
                              'Préfixe habituel : ${op.prefix}...',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                        ],
                      ),
                    ),
                    Radio<String>(
                      value: op.code,
                      groupValue: _selectedOperator.code,
                      activeColor: MooviColors.orange,
                      onChanged: (val) {
                        setState(() => _selectedOperator = op);
                      },
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        // NUMÉRO DE TÉLÉPHONE AVEC INDICATIF DU PAYS
        const Text(
          'NUMÉRO DU COMPTE MOBILE MONEY',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: MooviColors.grey),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Text(
                '${_selectedCountry.flag} ${_selectedCountry.dialCode}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MooviColors.dark),
              ),
              const SizedBox(width: 10),
              Container(width: 1, height: 22, color: Colors.grey.shade300),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Numéro ${_selectedOperator.name}',
                  ),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),

        if (!PawaPayService.instance.isProduction) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Mode Sandbox : Numéro de test pré-rempli (${_phoneController.text}) pour simuler un succès immédiat.',
                  style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],

        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        // BOUTON CONFIRMATION
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleRecharge,
            style: ElevatedButton.styleFrom(
              backgroundColor: MooviColors.orange,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : Text(
                    'Recharger ${_selectedAmount > 0 ? '$_selectedAmount ${_selectedCountry.currency}' : ''}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildPollingView() {
    return Column(
      children: [
        const SizedBox(height: 16),
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 76,
              height: 76,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                valueColor: const AlwaysStoppedAnimation(MooviColors.orange),
                backgroundColor: MooviColors.orange.withOpacity(0.15),
              ),
            ),
            const Icon(Icons.phone_iphone_rounded, size: 36, color: MooviColors.orange),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Confirmation sur votre mobile',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: MooviColors.dark),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _statusMessage ?? 'Veuillez confirmer la transaction PawaPay en saisissant votre code PIN secret sur votre téléphone.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade700),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$_selectedAmount ${_selectedCountry.currency} • ${_selectedOperator.name} (${_selectedCountry.flag})',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () {
            _pollingSubscription?.cancel();
            setState(() => _isPolling = false);
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: MooviColors.dark,
            side: const BorderSide(color: MooviColors.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Annuler'),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildSuccessView() {
    return Column(
      children: [
        const SizedBox(height: 16),
        Container(
          width: 76,
          height: 76,
          decoration: const BoxDecoration(
            color: Color(0xFFE8F5E9),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded, size: 48, color: MooviColors.green),
        ),
        const SizedBox(height: 16),
        const Text(
          'Portefeuille Rechargé !',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: MooviColors.dark),
        ),
        const SizedBox(height: 6),
        Text(
          'Votre solde Moovi a été crédité de $_selectedAmount ${_selectedCountry.currency}.\nVotre compte est actif pour accepter des courses.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
