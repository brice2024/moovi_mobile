import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_intl_phone_field/country_picker_dialog.dart';
import 'package:flutter_intl_phone_field/flutter_intl_phone_field.dart';
import 'package:moovi/theme/app_colors.dart';
import 'package:moovi/widgets/moovi_scaffold.dart';
import '../services/Auth.dart';
import '../widgets/animations/fadeSlideIn.dart';
import 'otpVerification.dart';

/// Couleurs propres aux écrans d'authentification (maquettes 5 à 8).
class AuthPalette {
  /// Titres brun foncé posés sur le dégradé.
  static const Color title = Color(0xFF4A2500);

  /// Bouton principal brun (dégradé de gauche à droite).
  static const LinearGradient brownButton = LinearGradient(
    colors: [Color(0xFF9A4F00), Color(0xFFC86D05)],
  );

  /// Bouton orange clair (état inactif).
  static const LinearGradient lightButton = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE88A1C), Color(0xFFF9A23A), Color(0xFFEB8E22)],
  );

  static const List<BoxShadow> buttonShadow = [
    BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 5)),
  ];
}

/// Logo « MOOVI » blanc (asset orange recoloré).
class MooviWhiteLogo extends StatelessWidget {
  final double width;
  const MooviWhiteLogo({super.key, this.width = 180});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/MooviOrange.png',
      width: width,
      fit: BoxFit.contain,
      color: Colors.white,
      colorBlendMode: BlendMode.srcIn,
    );
  }
}

class Signorlogin extends StatefulWidget {
  const Signorlogin({super.key});

  @override
  State<Signorlogin> createState() => _SignorloginState();
}

class _SignorloginState extends State<Signorlogin> {
  final _phoneController = TextEditingController();
  // Indicatif par défaut : Gabon.
  String _Countrycode = '+241';

  //booléen pour vérifier la validité du numéro
  bool isPhoneValid = false;
  bool _sending = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    if (_sending) return;
    //envoyer un code de vérification au numéro
    debugPrint(_Countrycode + _phoneController.text);

    //vérifier que le numéro est renseigné avant de passer à la page suivante passer à la page de vérification
    if (!isPhoneValid) return;

    setState(() => _sending = true);
    try {
      await AuthService.instance.sendOTP(_Countrycode + _phoneController.text);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      final message = switch (e.code) {
        'invalid-phone-number' => "Ce numéro de téléphone n'est pas valide.",
        'too-many-requests' => "Trop de tentatives. Réessayez plus tard.",
        'network-request-failed' => "Pas de connexion internet.",
        _ => "Impossible d'envoyer le code (${e.code}). Réessayez.",
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _sending = false);
    // Android peut valider le numéro tout seul :
    // l'AuthWrapper affiche alors directement l'accueil.
    if (AuthService.instance.currentUser != null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Otpverification(
          phoneNumber: _phoneController.text,
          countryCode: _Countrycode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: MooviGradient.end,
        body: MooviGradientBackground(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 60),
                  const Center(child: MooviWhiteLogo(width: 185)),
                  const SizedBox(height: 70),

                  const Text(
                    "Entrez votre numéro de téléphone",
                    style: TextStyle(
                      color: AuthPalette.title,
                      fontSize: 27,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Un code de vérification vous sera envoyé par SMS.",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 40),

                  FadeSlideIn(
                    child: IntlPhoneField(
                      controller: _phoneController,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      initialCountryCode: 'GA',
                      languageCode: 'fr',
                      pickerDialogStyle: PickerDialogStyle(
                        searchFieldInputDecoration: const InputDecoration(
                          labelText: 'Rechercher un pays',
                          prefixIcon: Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      invalidMessage: 'Le numéro de téléphone est incorrect',
                      cursorColor: AppColors.primary,
                      style: const TextStyle(
                        color: AuthPalette.title,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                      dropdownTextStyle: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      dropdownIconPosition: IconPosition.trailing,
                      dropdownIcon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: Colors.black87,
                      ),
                      dropdownDecoration: BoxDecoration(
                        color: MooviGradient.card,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      flagsButtonMargin: const EdgeInsets.fromLTRB(6, 6, 14, 6),
                      flagsButtonPadding:
                          const EdgeInsets.symmetric(horizontal: 10),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: '077 12 34 56',
                        hintStyle: const TextStyle(
                          color: Color(0xFFC9B8A8),
                          fontSize: 17,
                        ),
                        counterText: '',
                        errorStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AuthPalette.title,
                            width: 1.5,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AppColors.error,
                            width: 1.5,
                          ),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AppColors.error,
                            width: 1.5,
                          ),
                        ),
                      ),

                      validator: (phone) {
                        if (phone == null || phone.number.isEmpty) {
                          return 'Veuillez entrer votre numéro';
                        }

                        if (!phone.isValidNumber()) {
                          return 'Le numéro de téléphone est incorrect';
                        }

                        return null;
                      },
                      onChanged: (phone) {
                        setState(() {
                          isPhoneValid = phone.isValidNumber();
                        });
                        _Countrycode = phone.countryCode;
                      },

                      onCountryChanged: (country) {
                        setState(() {
                          isPhoneValid = false;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  _ContinueButton(
                    loading: _sending,
                    enabled: isPhoneValid,
                    onTap: _onContinue,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton « Continuer » brun avec flèche (maquette 5).
class _ContinueButton extends StatefulWidget {
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  const _ContinueButton({
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_ContinueButton> createState() => _ContinueButtonState();
}

class _ContinueButtonState extends State<_ContinueButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 100),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: widget.enabled || widget.loading ? 1 : 0.75,
          child: Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 30),
            decoration: BoxDecoration(
              gradient: AuthPalette.brownButton,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AuthPalette.buttonShadow,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Continuer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.loading)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(Icons.arrow_forward, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
