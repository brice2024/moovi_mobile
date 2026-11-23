import 'package:flutter/material.dart';
import 'package:moovi/widgets/moovi_scaffold.dart';

import 'settings_widgets.dart';

/// Choix de la langue : seul le français est disponible pour l'instant.
class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

  static const _upcoming = ['English', 'Español', 'Português'];

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Langue',
      subtitle: "Choisissez la langue de l'application.",
      children: [
        SettingsCard(
          children: [
            const SettingsTile(
              icon: Icons.language_rounded,
              title: 'Français',
              trailing: Icon(Icons.check_circle_rounded,
                  color: MooviGradient.end, size: 24),
            ),
            for (final lang in _upcoming)
              Opacity(
                opacity: 0.45,
                child: SettingsTile(
                  icon: Icons.language_rounded,
                  title: lang,
                  subtitle: 'Bientôt disponible',
                  showChevron: false,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
