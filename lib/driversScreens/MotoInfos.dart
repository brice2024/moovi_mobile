import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_colors.dart';
import 'DriverDocsVerificationPage.dart';
import 'test/offers_page.dart';

const _monoFont = 'monospace'; // remplace par 'SpaceMono' si tu l'ajoutes aux assets

/// Tous les fichiers à fournir. `name` sert de clé Firestore et de nom de fichier Storage.
/// Renommé en MotoDocType pour éviter un conflit avec DocType de CarInfos.
enum MotoDocType {
  license('Permis de conduire', 'Recto / Verso', Icons.description_rounded),
  registration('Carte grise', 'Certificat définitif', Icons.badge_rounded),
  front('Face', 'Vue de face', Icons.two_wheeler_rounded),
  left('Profil gauche', 'Côté gauche', Icons.two_wheeler_rounded),
  right('Profil droit', 'Côté droit', Icons.two_wheeler_rounded),
  back('Arrière', 'Vue arrière', Icons.two_wheeler_rounded),
  plate('Plaque', "Plaque d'immatriculation", Icons.pin_rounded);

  const MotoDocType(this.label, this.subtitle, this.icon);
  final String label;
  final String subtitle;
  final IconData icon;

  bool get isDocument => this == license || this == registration;
}

class Motoinfos extends StatefulWidget {
  const Motoinfos({super.key});

  @override
  State<Motoinfos> createState() => _MotoinfosState();
}

class _MotoinfosState extends State<Motoinfos> {
  final _brandCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();

  final _picker = ImagePicker();
  final Map<MotoDocType, XFile> _files = {};

  bool _uploading = false;
  double _progress = 0;

  static const _documents = [MotoDocType.license, MotoDocType.registration];
  static const _motoPhotos = [
    MotoDocType.front,
    MotoDocType.left,
    MotoDocType.right,
    MotoDocType.back,
    MotoDocType.plate,
  ];

  int get _remaining => MotoDocType.values.length - _files.length;

  @override
  void dispose() {
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _colorCtrl.dispose();
    _plateCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Sélection
  // ---------------------------------------------------------------------------

  Future<void> _pick(MotoDocType type) async {
    if (_uploading) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded,
                    color: AppColors.primary),
                title: const Text('Prendre une photo'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded,
                    color: AppColors.primary),
                title: const Text('Choisir dans la galerie'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              if (_files.containsKey(type))
                ListTile(
                  leading:
                  const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  title: const Text('Supprimer',
                      style: TextStyle(color: Colors.red)),
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
            ],
          ),
        ),
      ),
    );

    if (action == null) return;

    if (action == 'delete') {
      setState(() => _files.remove(type));
      return;
    }

    try {
      final file = await _picker.pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (file != null && mounted) {
        setState(() => _files[type] = file);
      }
    } catch (e) {
      _snack("Impossible d'accéder à la photo : $e");
      debugPrint('$e');
    }
  }

  // ---------------------------------------------------------------------------
  // Envoi Storage + Firestore
  // ---------------------------------------------------------------------------

  Future<void> _onContinue() async {
    final textsOk = _brandCtrl.text.trim().isNotEmpty &&
        _modelCtrl.text.trim().isNotEmpty &&
        _colorCtrl.text.trim().isNotEmpty &&
        _plateCtrl.text.trim().isNotEmpty;

    if (!textsOk || _remaining != 0) {
      _snack('Veuillez remplir tous les champs et ajouter tous les documents');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Vous devez être connecté.');
      return;
    }

    setState(() {
      _uploading = true;
      _progress = 0;
    });

    try {
      final uid = user.uid;
      final uploaded = <String, Map<String, String>>{};
      var done = 0;
      final total = _files.length;

      await Future.wait(_files.entries.map((entry) async {
        // Dossier "moto" séparé pour ne pas écraser les fichiers de la voiture.
        final path = 'drivers/$uid/moto/${entry.key.name}.jpg';
        final ref = FirebaseStorage.instance.ref(path);

        await ref.putFile(
          File(entry.value.path),
          SettableMetadata(contentType: 'image/jpeg'),
        );
        final url = await ref.getDownloadURL();
        uploaded[entry.key.name] = {'url': url, 'path': path};

        done++;
        if (mounted) setState(() => _progress = done / total);
      }));

      await FirebaseFirestore.instance.collection('drivers').doc(uid).set({
        'moto': {
          'brand': _brandCtrl.text.trim(),
          'model': _modelCtrl.text.trim(),
          'color': _colorCtrl.text.trim(),
          'plate': _plateCtrl.text.trim().toUpperCase(),
          // Documents rangés dans "moto" pour ne pas se mélanger à ceux de la voiture.
          'documents': uploaded,
        },
        'verificationStatus': 'pending', // pending | approved | rejected
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      _snack('Informations envoyées avec succès');

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DriverVerificationPage(
            onContinue: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const OffersPage()),
              );
            },
          ),
        ),
      );
    } on FirebaseException catch (e) {
      _snack("Erreur d'envoi : ${e.message ?? e.code}");
    } catch (e) {
      _snack('Une erreur est survenue : $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Informations de la Moto',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.background,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Renseignez les informations de votre moto\npour commencer à rouler.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: AppColors.grey,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _LabeledField(
                      label: 'MARQUE',
                      hint: 'Ex: Yamaha',
                      controller: _brandCtrl,
                      textCapitalization: TextCapitalization.words,
                    ),
                    _LabeledField(
                      label: 'MODÈLE',
                      hint: 'Ex: MT-07',
                      controller: _modelCtrl,
                      textCapitalization: TextCapitalization.words,
                    ),
                    _LabeledField(
                      label: 'COULEUR',
                      hint: 'Ex: Noir Métallisé',
                      controller: _colorCtrl,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    _LabeledField(
                      label: "PLAQUE D'IMMATRICULATION",
                      hint: 'Ex: AB-123-CD',
                      controller: _plateCtrl,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
                      ],
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 4),
                    _SectionHeader(
                      title: 'Documents requis',
                      trailing:
                      _remaining == 0 ? 'Complet' : '$_remaining à fournir',
                    ),
                    const SizedBox(height: 14),
                    for (final type in _documents) ...[
                      _DocumentCard(
                        type: type,
                        file: _files[type],
                        onTap: () => _pick(type),
                      ),
                      const SizedBox(height: 14),
                    ],
                    const SizedBox(height: 10),
                    const _SectionHeader(title: 'Photos de la moto'),
                    const SizedBox(height: 14),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.85,
                      children: [
                        for (final type in _motoPhotos)
                          _PhotoTile(
                            type: type,
                            file: _files[type],
                            onTap: () => _pick(type),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: _ContinueButton(
                onPressed: _onContinue,
                loading: _uploading,
                progress: _progress,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Widgets
// -----------------------------------------------------------------------------

BoxDecoration _cardDecoration(double radius) => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(radius),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withOpacity(0.06),
      blurRadius: 14,
      offset: const Offset(0, 4),
    ),
  ],
);

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, color: AppColors.background),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              fontFamily: _monoFont,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.hint,
    required this.controller,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.textInputAction = TextInputAction.next,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: _monoFont,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.darkBrown,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: controller,
              textCapitalization: textCapitalization,
              textInputAction: textInputAction,
              inputFormatters: inputFormatters,
              style: const TextStyle(fontSize: 16, color: AppColors.background),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 16, color: AppColors.grey),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte horizontale (permis, carte grise) avec miniature une fois la photo choisie.
class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.type,
    required this.file,
    required this.onTap,
  });

  final MotoDocType type;
  final XFile? file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final added = file != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(18),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 50,
              height: 50,
              color: AppColors.cream.withOpacity(0.5),
              child: added
                  ? Image.file(File(file!.path), fit: BoxFit.cover)
                  : Icon(type.icon, size: 24, color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.background,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  type.subtitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.grey),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 34,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                backgroundColor:
                added ? AppColors.cream.withOpacity(0.5) : Colors.white,
                side: const BorderSide(color: AppColors.primary, width: 1),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                added ? 'MODIFIER' : 'AJOUTER',
                style: const TextStyle(
                  fontFamily: _monoFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tuile carrée pour les photos de la moto.
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.type,
    required this.file,
    required this.onTap,
  });

  final MotoDocType type;
  final XFile? file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final added = file != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: _cardDecoration(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (added)
                Image.file(File(file!.path), fit: BoxFit.cover)
              else
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(type.icon, size: 28, color: AppColors.primary),
                      const SizedBox(height: 8),
                      Text(
                        type.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.background,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Icon(Icons.add_circle_outline_rounded,
                          size: 16, color: AppColors.grey),
                    ],
                  ),
                ),
              if (added) ...[
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    color: Colors.black54,
                    child: Text(
                      type.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  top: 6,
                  right: 6,
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: AppColors.primary,
                    child: Icon(Icons.check, size: 14, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({
    required this.onPressed,
    required this.loading,
    required this.progress,
  });

  final VoidCallback onPressed;
  final bool loading;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.7),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: loading
            ? Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'ENVOI ${(progress * 100).round()}%',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
                color: Colors.white,
              ),
            ),
          ],
        )
            : const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'CONTINUER',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}