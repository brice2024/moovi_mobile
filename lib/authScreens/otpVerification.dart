import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moovi/services/Auth.dart';
import 'package:moovi/userScreens/PagesManager.dart';
import 'package:moovi/userScreens/mapPage.dart';

import '../widgets/animations/fadeSlideIn.dart';
import '../widgets/cButton.dart';

class Otpverification extends StatefulWidget {
  final String phoneNumber;
  final String countryCode;

  const Otpverification({super.key, required this.phoneNumber, required this.countryCode});

  @override
  State<Otpverification> createState() => _OtpverificationState();
}

class _OtpverificationState extends State<Otpverification> {
  static const int _codeLength = 6;
  static const int _resendDelay = 30; // secondes

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  Timer? _timer;
  int _secondsLeft = _resendDelay;
  bool _hasError = false;

  bool get _canResend => _secondsLeft == 0;
  String get _code => _controllers.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_codeLength, (_) => TextEditingController());
    _focusNodes = List.generate(
      _codeLength,
          (i) => FocusNode(onKeyEvent: (node, event) => _onKey(i, event)),
    );
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

  void _resendCode() {
    if (!_canResend) return;

    // TODO: appeler ton API pour renvoyer le code
    for (final c in _controllers) {
      c.clear();
    }
    setState(() => _hasError = false);
    _focusNodes.first.requestFocus();
    _startTimer();

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

  Future<void> _submit() async {
    if (_code.length < _codeLength) {
      setState(() => _hasError = true);
      return;
    }
    // TODO: vérifier le code `_code` auprès de ton API
    debugPrint("Code saisi : $_code");

    await AuthService.instance.verifyOTP(_code);

  }

  // ------------------------------------------------------------------ UI

  Widget _buildBox(int index) {
    final primary = Theme.of(context).colorScheme.primary;
    final filled = _controllers[index].text.isNotEmpty;

    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color, width: width),
    );

    final idleColor = _hasError
        ? Colors.red
        : (filled ? primary : Colors.grey);

    return SizedBox(
      height: 40,
      width: 40,
      child: TextFormField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        autofocus: index == 0,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        textInputAction:
        index == _codeLength - 1 ? TextInputAction.done : TextInputAction.next,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
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
          fillColor: Colors.white,
          counterText: "",
          contentPadding: EdgeInsets.zero,
          enabledBorder: border(idleColor, filled ? 1.5 : 1),
          focusedBorder: border(_hasError ? Colors.red : primary, 2),
          border: border(idleColor, 1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Center(
            child: Column(
              children: [
                const SizedBox(height: 40),

                SizedBox(
                  height: 60,
                  child: Image.asset("assets/icon/MooviOrange.png"),
                ),

                const SizedBox(height: 100),

                const Text(
                  "Entrez le code de vérification",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  "Un code à $_codeLength chiffres a été envoyé au ${widget.countryCode} ${widget.phoneNumber}",
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 30),

                AutofillGroup(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(_codeLength, _buildBox),
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
                      style: TextStyle(color: Colors.red),
                    ),
                  )
                      : const SizedBox(width: double.infinity),
                ),

                const SizedBox(height: 5),

                // Timer / bouton de renvoi
                _canResend
                    ? GestureDetector(
                  onTap: _resendCode,
                  child: Text(
                    "Renvoyer le code",
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
                    : Text(
                  "Renvoyer le code dans $_formattedTime",
                  style: const TextStyle(color: Colors.grey , fontSize: 16),
                ),

                const SizedBox(height: 20),

                CustomButton(text: "Envoyer", onTap: () async {
                  await _submit();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const Pagesmanager(),
                    ),
                  );

                }),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}