import 'package:flutter/material.dart';
import 'package:moovi/widgets/moovi_scaffold.dart';

/// Brun foncé des textes posés sur les cartes claires des maquettes.
const Color kMooviInk = Color(0xFF3A2208);

/// Carte blanche arrondie regroupant des lignes de réglages (maquette 17).
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(const Divider(height: 1, thickness: 1, color: Color(0xFFF3ECE5)));
      }
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Column(children: rows),
    );
  }
}

/// Petit carré crème contenant une icône brune.
class SettingsIconBox extends StatelessWidget {
  const SettingsIconBox({super.key, required this.icon, this.color = kMooviInk});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: MooviGradient.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 21, color: color),
    );
  }
}

/// Ligne de réglage : icône, titre, texte optionnel à droite et chevron.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.titleColor = kMooviInk,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            SettingsIconBox(icon: icon, color: titleColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: kMooviInk.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailingText != null) ...[
              Text(
                trailingText!,
                style: TextStyle(
                  fontSize: 13,
                  color: kMooviInk.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(width: 4),
            ],
            if (trailing != null) trailing!,
            if (showChevron && trailing == null)
              Icon(Icons.chevron_right_rounded,
                  size: 24, color: kMooviInk.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}

/// Squelette commun des pages de réglages : dégradé, en-tête avec retour,
/// contenu défilant.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MooviGradient.start,
      body: MooviGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              MooviHeader(title: title),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  children: [
                    if (subtitle != null) ...[
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    ...children,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
