import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'settings_widgets.dart';

/// Sécurité du compte : méthode de connexion, réinitialisation du mot de passe
/// (comptes e-mail) et déconnexion.
class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  bool _sending = false;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _resetPassword(String email) async {
    setState(() => _sending = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _snack('Un e-mail de réinitialisation a été envoyé à $email.');
    } on FirebaseAuthException catch (e) {
      _snack(e.code == 'too-many-requests'
          ? 'Trop de tentatives. Réessayez plus tard.'
          : "Impossible d'envoyer l'e-mail de réinitialisation.");
    } catch (_) {
      _snack("Impossible d'envoyer l'e-mail de réinitialisation.");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se déconnecter'),
        content: const Text('Voulez-vous vraiment vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    // Retour à la racine : l'AuthWrapper affichera l'écran de connexion.
    Navigator.of(context).popUntil((route) => route.isFirst);
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final providers = user?.providerData.map((p) => p.providerId).toSet() ?? {};
    final email = user?.email;
    final phone = user?.phoneNumber;
    final hasPassword = providers.contains('password') && (email ?? '').isNotEmpty;

    return SettingsScaffold(
      title: 'Sécurité',
      subtitle: 'Gérez la connexion à votre compte Moovi.',
      children: [
        SettingsCard(
          children: [
            if ((phone ?? '').isNotEmpty)
              SettingsTile(
                icon: Icons.phone_iphone_rounded,
                title: 'Téléphone',
                subtitle: phone,
                showChevron: false,
              ),
            if ((email ?? '').isNotEmpty)
              SettingsTile(
                icon: Icons.alternate_email_rounded,
                title: 'E-mail',
                subtitle: email,
                showChevron: false,
              ),
            SettingsTile(
              icon: Icons.verified_user_rounded,
              title: 'Méthode de connexion',
              subtitle: hasPassword
                  ? 'E-mail et mot de passe'
                  : providers.contains('phone')
                      ? 'Numéro de téléphone (code SMS)'
                      : providers.contains('google.com')
                          ? 'Compte Google'
                          : 'Inconnue',
              showChevron: false,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SettingsCard(
          children: [
            if (hasPassword)
              SettingsTile(
                icon: Icons.lock_reset_rounded,
                title: 'Réinitialiser le mot de passe',
                subtitle: 'Un lien vous sera envoyé par e-mail',
                trailing: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _sending ? null : () => _resetPassword(email!),
              ),
            SettingsTile(
              icon: Icons.logout_rounded,
              title: 'Se déconnecter',
              titleColor: const Color(0xFFC62828),
              showChevron: false,
              onTap: _signOut,
            ),
          ],
        ),
      ],
    );
  }
}
