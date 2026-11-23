import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moovi/widgets/moovi_scaffold.dart';

import 'DriverDocsVerificationPage.dart';

const _ink = Color(0xFF3A2208);

/// Informations de la voiture. Les pièces justificatives sont désormais
/// envoyées sur l'écran « Vérification Chauffeur ».
class Carinfos extends StatelessWidget {
  const Carinfos({super.key});

  @override
  Widget build(BuildContext context) {
    return const VehicleInfoForm(
      vehicleKey: 'car',
      title: 'Votre voiture',
      subtitle:
          'Renseignez les informations de votre voiture pour commencer à rouler.',
      icon: Icons.directions_car_rounded,
      brandHint: 'Ex : Toyota',
      modelHint: 'Ex : Corolla',
    );
  }
}

/// Formulaire véhicule commun voiture / moto.
/// Enregistre `drivers/{uid}.{vehicleKey}` = {brand, model, color, plate}
/// (`DriverService.isDriverRegistered` s'appuie sur la présence de `car` ou `moto`)
/// puis ouvre la vérification des documents.
class VehicleInfoForm extends StatefulWidget {
  const VehicleInfoForm({
    super.key,
    required this.vehicleKey,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.brandHint,
    required this.modelHint,
  });

  /// 'car' ou 'moto'.
  final String vehicleKey;
  final String title;
  final String subtitle;
  final IconData icon;
  final String brandHint;
  final String modelHint;

  @override
  State<VehicleInfoForm> createState() => _VehicleInfoFormState();
}

class _VehicleInfoFormState extends State<VehicleInfoForm> {
  final _formKey = GlobalKey<FormState>();
  final _brandCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  /// Pré-remplit le formulaire si le véhicule a déjà été enregistré.
  Future<void> _prefill() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('drivers').doc(uid).get();
      final v = snap.data()?[widget.vehicleKey];
      if (v is! Map || !mounted) return;
      void fill(TextEditingController c, Object? value) {
        if (c.text.isEmpty && value is String) c.text = value;
      }

      fill(_brandCtrl, v['brand']);
      fill(_modelCtrl, v['model']);
      fill(_colorCtrl, v['color']);
      fill(_plateCtrl, v['plate']);
    } catch (_) {
      // Pas bloquant : le formulaire reste vide.
    }
  }

  @override
  void dispose() {
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _colorCtrl.dispose();
    _plateCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _onContinue() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Vous devez être connecté.');
      return;
    }

    setState(() => _saving = true);
    try {
      final ref = FirebaseFirestore.instance.collection('drivers').doc(user.uid);
      final existing = (await ref.get()).data();

      await ref.set({
        widget.vehicleKey: {
          'brand': _brandCtrl.text.trim(),
          'model': _modelCtrl.text.trim(),
          'color': _colorCtrl.text.trim(),
          'plate': _plateCtrl.text.trim().toUpperCase(),
        },
        'vehicleType': widget.vehicleKey,
        // pending | approved | rejected — on n'écrase pas un statut existant
        // (compte déjà validé ou refusé par le back-office).
        if (existing?['verificationStatus'] == null)
          'verificationStatus': 'pending',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DriverVerificationPage()),
      );
    } on FirebaseException catch (e) {
      _snack("Impossible d'enregistrer le véhicule : ${e.message ?? e.code}");
    } catch (_) {
      _snack("Impossible d'enregistrer le véhicule. Réessayez.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MooviGradient.start,
      body: MooviGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              const MooviHeader(title: 'Informations du véhicule'),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(widget.icon, color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              widget.title,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 20, 18, 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Column(
                          children: [
                            _LabeledField(
                              label: 'Marque',
                              hint: widget.brandHint,
                              controller: _brandCtrl,
                              validator: _required,
                              textCapitalization: TextCapitalization.words,
                            ),
                            _LabeledField(
                              label: 'Modèle',
                              hint: widget.modelHint,
                              controller: _modelCtrl,
                              validator: _required,
                              textCapitalization: TextCapitalization.words,
                            ),
                            _LabeledField(
                              label: 'Couleur',
                              hint: 'Ex : Noir métallisé',
                              controller: _colorCtrl,
                              validator: _required,
                              textCapitalization: TextCapitalization.sentences,
                            ),
                            _LabeledField(
                              label: "Plaque d'immatriculation",
                              hint: 'Ex : AB-123-CD',
                              controller: _plateCtrl,
                              validator: _required,
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[A-Za-z0-9\- ]')),
                              ],
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _onContinue(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: MooviGradient.card,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: _ink, size: 22),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "À l'étape suivante, vous ajouterez les photos du "
                                'véhicule et vos documents (carte grise, permis, '
                                "carte d'identité).",
                                style: TextStyle(fontSize: 12.5, height: 1.4, color: _ink),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 62,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _onContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: MooviGradient.end,
                      disabledBackgroundColor: Colors.white.withValues(alpha: 0.6),
                      elevation: 6,
                      shadowColor: Colors.black26,
                      shape: const StadiumBorder(),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: MooviGradient.end),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Continuer',
                                  style: TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.w700)),
                              SizedBox(width: 10),
                              Icon(Icons.arrow_forward_rounded, size: 22),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.hint,
    required this.controller,
    this.validator,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: width),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            validator: validator,
            textCapitalization: textCapitalization,
            textInputAction: textInputAction,
            inputFormatters: inputFormatters,
            onFieldSubmitted: onSubmitted,
            style: const TextStyle(fontSize: 15, color: _ink),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(fontSize: 15, color: _ink.withValues(alpha: 0.4)),
              filled: true,
              fillColor: MooviGradient.cardStrong,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: border(Colors.transparent),
              enabledBorder: border(Colors.transparent),
              focusedBorder: border(MooviGradient.end, 1.5),
              errorBorder: border(const Color(0xFFC62828)),
              focusedErrorBorder: border(const Color(0xFFC62828), 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
