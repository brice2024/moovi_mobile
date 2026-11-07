import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_colors.dart';
import 'profile_avatar.dart';
import 'user_profile.dart';

const _monoFont = 'monospace';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _phoneCtrl;

  final _picker = ImagePicker();
  XFile? _newPhoto;
  bool _removePhoto = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _firstNameCtrl = TextEditingController(text: widget.profile.firstName);
    _lastNameCtrl = TextEditingController(text: widget.profile.lastName);
    _phoneCtrl = TextEditingController(text: widget.profile.phone);
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  bool get _hasPhoto =>
      _newPhoto != null ||
      (!_removePhoto && (widget.profile.photoUrl?.isNotEmpty ?? false));

  // ---------------------------------------------------------------------------
  // Photo
  // ---------------------------------------------------------------------------

  Future<void> _pickPhoto() async {
    if (_saving) return;

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
              if (_hasPhoto)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: Colors.red),
                  title: const Text('Supprimer la photo',
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
      setState(() {
        _newPhoto = null;
        _removePhoto = true;
      });
      return;
    }

    try {
      final file = await _picker.pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (file != null && mounted) {
        setState(() {
          _newPhoto = file;
          _removePhoto = false;
        });
      }
    } catch (e) {
      _snack("Impossible d'accéder à la photo : $e");
    }
  }

  // ---------------------------------------------------------------------------
  // Enregistrement
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Vous devez être connecté.');
      return;
    }

    setState(() => _saving = true);

    try {
      final firstName = _firstNameCtrl.text.trim();
      final lastName = _lastNameCtrl.text.trim();
      final oldPath = widget.profile.photoPath;

      final data = <String, dynamic>{
        'firstName': firstName,
        'lastName': lastName,
        'phone': _phoneCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      String? photoUrl = _removePhoto ? null : widget.profile.photoUrl;
      var deleteOld = false;

      if (_newPhoto != null) {
        // Nom unique pour éviter le cache d'image côté client
        final newPath =
            'users/${user.uid}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instance.ref(newPath);
        await ref.putFile(
          File(_newPhoto!.path),
          SettableMetadata(contentType: 'image/jpeg'),
        );
        photoUrl = await ref.getDownloadURL();
        data['photoUrl'] = photoUrl;
        data['photoPath'] = newPath;
        deleteOld = true;
      } else if (_removePhoto) {
        data['photoUrl'] = FieldValue.delete();
        data['photoPath'] = FieldValue.delete();
        deleteOld = true;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(data, SetOptions(merge: true));

      // Nettoyage de l'ancienne photo (non bloquant)
      if (deleteOld && oldPath != null && oldPath.isNotEmpty) {
        try {
          await FirebaseStorage.instance.ref(oldPath).delete();
        } catch (_) {}
      }

      // Synchronise aussi le profil Firebase Auth (non bloquant)
      try {
        await user.updateDisplayName('$firstName $lastName'.trim());
        await user.updatePhotoURL(photoUrl);
      } catch (_) {}

      if (!mounted) return;
      _snack('Profil mis à jour');
      Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      _snack("Erreur d'enregistrement : ${e.message ?? e.code}");
    } catch (e) {
      _snack('Une erreur est survenue : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Material(
                    color: AppColors.cream.withOpacity(0.6),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _saving ? null : () => Navigator.of(context).pop(),
                      child: const SizedBox(
                        width: 42,
                        height: 42,
                        child: Icon(Icons.arrow_back_rounded,
                            color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Modifier mon profil',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.background,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      ProfileAvatar(
                        size: 110,
                        imageUrl: _removePhoto ? null : widget.profile.photoUrl,
                        file: _newPhoto != null ? File(_newPhoto!.path) : null,
                        badgeIcon: Icons.photo_camera_rounded,
                        onTap: _pickPhoto,
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _pickPhoto,
                        child: const Text(
                          'Changer la photo',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _LabeledField(
                        label: 'PRÉNOM',
                        hint: 'Ex: Wilson',
                        controller: _firstNameCtrl,
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Le prénom est obligatoire'
                            : null,
                      ),
                      _LabeledField(
                        label: 'NOM',
                        hint: 'Ex: Herwitz',
                        controller: _lastNameCtrl,
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Le nom est obligatoire'
                            : null,
                      ),
                      _LabeledField(
                        label: 'TÉLÉPHONE',
                        hint: 'Ex: +212 600-000000',
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
                        ],
                        validator: (v) {
                          final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                          return digits.length < 8
                              ? 'Numéro de téléphone invalide'
                              : null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: _SaveButton(loading: _saving, onPressed: _save),
            ),
          ],
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
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction = TextInputAction.next,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final TextCapitalization textCapitalization;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color? color, [double width = 1.5]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: color == null
              ? BorderSide.none
              : BorderSide(color: color, width: width),
        );

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
            child: TextFormField(
              controller: controller,
              validator: validator,
              textCapitalization: textCapitalization,
              textInputAction: textInputAction,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              style: const TextStyle(fontSize: 16, color: AppColors.background),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 16, color: AppColors.grey),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                border: border(null),
                enabledBorder: border(null),
                focusedBorder: border(AppColors.primary),
                errorBorder: border(Colors.red, 1),
                focusedErrorBorder: border(Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
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
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Text(
                'ENREGISTRER',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}
