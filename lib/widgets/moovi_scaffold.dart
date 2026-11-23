import 'package:flutter/material.dart';

/// Couleurs du dégradé orange des maquettes (brun en haut à gauche -> orange en bas à droite).
class MooviGradient {
  static const Color start = Color(0xFFA9560B);
  static const Color end = Color(0xFFFF8A00);

  static const LinearGradient background = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [start, end],
  );

  /// Crème des cartes posées sur le dégradé.
  static const Color card = Color(0xFFFFE9D6);
  static const Color cardStrong = Color(0xFFFFF4EA);
  static const Color brownCard = Color(0xFF7A3E05);
}

/// Fond en dégradé orange plein écran, utilisé par la plupart des écrans des maquettes.
class MooviGradientBackground extends StatelessWidget {
  final Widget child;
  const MooviGradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: MooviGradient.background),
      child: child,
    );
  }
}

/// En-tête des maquettes : petit logo « MOOVI » centré, puis flèche retour + titre blanc.
class MooviHeader extends StatelessWidget {
  final String? title;
  final VoidCallback? onBack;
  final bool showBack;
  final bool showLogo;
  final Widget? trailing;

  const MooviHeader({
    super.key,
    this.title,
    this.onBack,
    this.showBack = true,
    this.showLogo = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showLogo)
            const Center(
              child: Text(
                'MOOVI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          if (title != null || showBack)
            Row(
              children: [
                if (showBack && (onBack != null || canPop))
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  ),
                if (title != null)
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (trailing != null) trailing!,
              ],
            ),
        ],
      ),
    );
  }
}
