import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/Auth.dart';
import '../../services/api_client.dart';
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

    setState(() => _saving = true);

    try {
      // Le numéro est l'identifiant de connexion (vérifié par code OTP) : il
      // n'est pas modifiable ici.
      final data = <String, dynamic>{
        'firstName': _firstNameCtrl.text.trim(),
        'lastName': _lastNameCtrl.text.trim(),
      };

      // 1. Profil (`PATCH /api/users/me`)
      var user = await ApiClient.instance
          .request('PATCH', '/api/users/me', body: data);

      // 2. Photo : l'API remplace et supprime l'ancien fichier elle-même.
      if (_newPhoto != null) {
        final name = _newPhoto!.name.toLowerCase();
        final ext = const ['jpg', 'jpeg', 'png', 'webp']
                .contains(name.split('.').last)
            ? name.split('.').last
            : 'jpg';
        final result = await ApiClient.instance.upload(
          '/api/users/me/avatar',
          files: [
            UploadFile('avatar', await _newPhoto!.readAsBytes(), 'avatar.$ext')
          ],
        );
        if (result['user'] is Map) {
          user = {
            ...user,
            ...Map<String, dynamic>.from(result['user'] as Map),
          };
        }
      } else if (_removePhoto) {
        user = {
          ...user,
          ...await ApiClient.instance.request('DELETE', '/api/users/me/avatar'),
        };
      }

      AuthService.instance.updateUserFromJson(user);

      if (!mounted) return;
      _snack('Profil mis à jour');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _snack("Erreur d'enregistrement : ${e.message}");
    } catch (e) {
      _snack(errorMessage(e));
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
                        label: 'TÉLÉPHONE (NUMÉRO DE CONNEXION)',
                        hint: '',
                        controller: _phoneCtrl,
                        readOnly: true,
                        textInputAction: TextInputAction.done,
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
    this.readOnly = false,
  });

  final bool readOnly;

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
              readOnly: readOnly,
              enabled: !readOnly,
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
