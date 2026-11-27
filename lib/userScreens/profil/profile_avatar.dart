import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';


/// Avatar rond avec anneau orange et petit badge (crayon / appareil photo).
/// Priorité d'affichage : [file] (aperçu local) > [imageUrl] > icône par défaut.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    this.size = 100,
    this.imageUrl,
    this.file,
    this.badgeIcon = Icons.edit_rounded,
    this.onTap,
  });

  final double size;
  final String? imageUrl;
  final File? file;
  final IconData badgeIcon;

  /// Appelé au clic sur l'avatar ou sur le badge.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final badgeSize = size * 0.28;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 3),
              ),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                padding: const EdgeInsets.all(2),
                child: ClipOval(child: _image()),
              ),
            ),
            if (onTap != null)
              Positioned(
                right: size * 0.02,
                bottom: size * 0.02,
                child: Container(
                  width: badgeSize,
                  height: badgeSize,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Icon(badgeIcon, size: badgeSize * 0.5, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _image() {
    if (file != null) {
      return Image.file(file!, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        color: AppColors.cream.withOpacity(0.6),
        child: Icon(Icons.person_rounded, size: size * 0.5, color: AppColors.primary),
      );
}
