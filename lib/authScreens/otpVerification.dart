import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moovi/services/Auth.dart';
import 'package:moovi/theme/app_colors.dart';
import 'package:moovi/widgets/moovi_scaffold.dart';

import '../widgets/animations/fadeSlideIn.dart';
import 'SignOrLogin.dart' show AuthPalette, MooviWhiteLogo;

class Otpverification extends StatefulWidget {
  final String phoneNumber;
  final String countryCode;

  const Otpverification({super.key, required this.phoneNumber, required this.countryCode});

  @override
  State<Otpverification> createState() => _OtpverificationState();
}

class _OtpverificationState extends State<Otpverification> {
  // Firebase envoie des codes à 6 chiffres (la maquette en montre 4 par simplification).
  static const int _codeLength = 6;
  static const int _resendDelay = 30; // secondes

  /// Bordure bleue des cases (maquettes 7-8).
  static const Color _activeBorder = Color(0xFF2F6BEA);
  static const Color _digitColor = Color(0xFF7A3E05);

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  Timer? _timer;
  int _secondsLeft = _resendDelay;
  bool _hasError = false;
  bool _verifying = false;

  bool get _canResend => _secondsLeft == 0;
  String get _code => _controllers.map((c) => c.text).join();
  bool get _isComplete => _code.length == _codeLength;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_codeLength, (_) => TextEditingController());
    _focusNodes = List.generate(
      _codeLength,
          (i) => FocusNode(onKeyEvent: (node, event) => _onKey(i, event)),
    );
    // Redessine les cases quand le focus change (bordure de la case active).
    for (final f in _focusNodes) {
      f.addListener(() {
        if (mounted) setState(() {});
      });
    }
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- Timer

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendDelay);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  String get _formattedTime {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  Future<void> _resendCode() async {
    if (!_canResend) return;

    for (final c in _controllers) {
      c.clear();
    }
    setState(() => _hasError = false);
    _focusNodes.first.requestFocus();
    _startTimer();

    try {
      await AuthService.instance
          .sendOTP(widget.countryCode + widget.phoneNumber);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Impossible de renvoyer le code (${e.code}).")),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Un nouveau code vous a été envoyé")),
    );
  }

  // ---------------------------------------------------------------- Focus

  /// Retour arrière sur une case vide : on recule et on efface la précédente.
  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onChanged(int index, String value) {
    if (_hasError) setState(() => _hasError = false);

    // Collage / auto-remplissage du code complet
    if (value.length >= _codeLength) {
      for (int i = 0; i < _codeLength; i++) {
        _controllers[i].text = value[i];
      }
      _focusNodes.last.requestFocus();
      FocusScope.of(context).unfocus();
      setState(() {});
      return;
    }

    // Saisie dans une case déjà remplie : on garde le dernier chiffre tapé
    if (value.length > 1) {
      final last = value[value.length - 1];
      _controllers[index].text = last;
      _controllers[index].selection =
      const TextSelection.collapsed(offset: 1);
      value = last;
    }

    if (value.isNotEmpty) {
      // Case remplie -> case suivante
      if (index < _codeLength - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        FocusScope.of(context).unfocus(); // dernière case : on ferme le clavier
      }
    } else if (index > 0) {
      // Suppression -> case précédente
      _focusNodes[index - 1].requestFocus();
    }

    setState(() {});
  }

  // --------------------------------------------------------------- Envoi

  /// Vérifie le code ; renvoie `true` si l'utilisateur est connecté.
  Future<bool> _submit() async {
    if (_code.length < _codeLength) {
      setState(() => _hasError = true);
      return false;
    }
    debugPrint("Code saisi : $_code");

    final ok = await AuthService.instance.verifyOTP(_code);
    if (!ok && mounted) {
      setState(() => _hasError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Code invalide ou expiré. Vérifiez le code ou demandez-en un nouveau."),
        ),
      );
    }
    return ok;
  }

  Future<void> _onVerify() async {
    if (_verifying) return;
    setState(() => _verifying = true);
    final ok = await _submit();
    if (!mounted) return;
    setState(() => _verifying = false);
    if (!ok) return;
    // Une fois connecté, l'AuthWrapper (première page)
    // affiche déjà l'accueil : il suffit de revenir dessus.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ------------------------------------------------------------------ UI

  Widget _buildBox(int index) {
    final filled = _controllers[index].text.isNotEmpty;
    final focused = _focusNodes[index].hasFocus;

    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: color, width: width),
    );

    // Bordure : rouge en erreur, bleue sur la case active ou quand le code
    // est complet (maquette 7), grise claire sinon (maquette 6).
    final Color idleColor;
    final double idleWidth;
    if (_hasError) {
      idleColor = AppColors.error;
      idleWidth = 2;
    } else if (_isComplete) {
      idleColor = _activeBorder;
      idleWidth = 2;
    } else {
      idleColor = const Color(0xFFE6E0DA);
      idleWidth = 1.5;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 62,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        boxShadow: focused || filled
            ? const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: TextFormField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        autofocus: index == 0,
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,
        keyboardType: TextInputType.number,
        cursorColor: _digitColor,
        textInputAction:
        index == _codeLength - 1 ? TextInputAction.done : TextInputAction.next,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: _digitColor,
        ),
        autofillHints: index == 0 ? const [AutofillHints.oneTimeCode] : null,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (value) => _onChanged(index, value),
        onTap: () {
          // Sélectionne le contenu pour qu'une nouvelle saisie le remplace
          _controllers[index].selection = TextSelection(
            baseOffset: 0,
            extentOffset: _controllers[index].text.length,
          );
        },
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          counterText: "",
          contentPadding: EdgeInsets.zero,
          enabledBorder: border(idleColor, idleWidth),
          focusedBorder: border(_hasError ? AppColors.error : _activeBorder, 2),
          border: border(idleColor, idleWidth),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Clavier ouvert : le logo se réduit en haut de l'écran (maquette 8).
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final fullNumber = '${widget.countryCode} ${widget.phoneNumber}';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: MooviGradient.end,
        body: MooviGradientBackground(
          child: SafeArea(
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        padding: EdgeInsets.only(
                          top: keyboardOpen ? 10 : 60,
                          bottom: keyboardOpen ? 40 : 70,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: MooviWhiteLogo(
                            key: ValueKey(keyboardOpen),
                            width: keyboardOpen ? 48 : 185,
                          ),
                        ),
                      ),

                      const Text(
                        "Entrez le code envoyé sur votre téléphone",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AuthPalette.title,
                          fontSize: 25,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text.rich(
                        TextSpan(
                          text: "Nous avons envoyé un code à $_codeLength chiffres au ",
                          children: [
                            TextSpan(
                              text: fullNumber,
                              style: const TextStyle(
                                color: AuthPalette.title,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),

                      const SizedBox(height: 36),

                      FadeSlideIn(
                        child: AutofillGroup(
                          child: Row(
                            children: [
                              for (int i = 0; i < _codeLength; i++) ...[
                                if (i > 0) const SizedBox(width: 8),
                                Expanded(child: _buildBox(i)),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Message d'erreur
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        child: _hasError
                            ? const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            "Veuillez saisir le code complet",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                            : const SizedBox(width: double.infinity),
                      ),

                      const SizedBox(height: 14),

                      // Timer / bouton de renvoi
                      if (!_canResend)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.access_time,
                              size: 16,
                              color: Color(0xFF5C3A16),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "Renvoyer le code dans $_formattedTime",
                              style: const TextStyle(
                                color: Color(0xFF5C3A16),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: _canResend ? _resendCode : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            "Renvoyer le code",
                            style: TextStyle(
                              color: _canResend
                                  ? Colors.white
                                  : const Color(0xFFFFE2C2),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              decoration: _canResend
                                  ? TextDecoration.underline
                                  : null,
                              decorationColor: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      _VerifyButton(
                        complete: _isComplete,
                        loading: _verifying,
                        onTap: _onVerify,
                      ),

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
                // Retour vers la saisie du numéro
                Positioned(
                  top: 4,
                  left: 4,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton « Vérifier » : orange clair tant que le code est incomplet
/// (maquette 6), brun quand il est complet (maquettes 7-8).
class _VerifyButton extends StatefulWidget {
  final bool complete;
  final bool loading;
  final VoidCallback onTap;

  const _VerifyButton({
    required this.complete,
    required this.loading,
    required this.onTap,
  });

  @override
  State<_VerifyButton> createState() => _VerifyButtonState();
}

class _VerifyButtonState extends State<_VerifyButton> {
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 240,
          height: 66,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: widget.complete
                ? AuthPalette.brownButton
                : AuthPalette.lightButton,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AuthPalette.buttonShadow,
          ),
          child: widget.loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Vérifier',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}
