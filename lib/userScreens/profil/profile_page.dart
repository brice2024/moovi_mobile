import '../../widgets/account_pages.dart';
import 'package:flutter/material.dart';
import '../../services/Auth.dart';
import '../../services/api_client.dart';
import '../../services/session.dart';
import '../../driversScreens/ChooseVehiclePage.dart';
import '../../driversScreens/test/offers_page.dart';
import '../../services/driver_service.dart';
import '../../theme/app_colors.dart';
import 'edit_profile_page.dart';
import '../../widgets/notifications_page.dart';
import 'profile_avatar.dart';
import 'user_profile.dart';

const _monoFont = 'monospace';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    this.onDriverMode,
    this.onNotifications,
    this.onSecurity,
    this.onLanguage,
    this.languageLabel = 'Français',
  });

  final VoidCallback? onDriverMode;
  final VoidCallback? onNotifications;
  final VoidCallback? onSecurity;
  final VoidCallback? onLanguage;
  final String languageLabel;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  void initState() {
    super.initState();
    // Profil à jour depuis l'API (`GET /api/auth/me`).
    AuthService.instance.refreshProfile().then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: StreamBuilder<AppUser?>(
          stream: AppSession.instance.changes,
          initialData: AppSession.instance.currentUser,
          builder: (context, snapshot) {
            final user = snapshot.data;
            if (user == null) {
              return const Center(child: Text('Vous devez être connecté.'));
            }

            final profile = UserProfile.fromMap(user.id, user.raw);

            return _ProfileContent(
              profile: profile,
              onDriverMode: widget.onDriverMode,
              onNotifications: widget.onNotifications ??
                  () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const NotificationsPage()),
                      ),
              onSecurity: widget.onSecurity ??
                  () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SecurityPage()),
                      ),
              onLanguage: widget.onLanguage ?? () => showLanguageSheet(context),
              languageLabel: widget.languageLabel,
            );
          },
        ),
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.profile,
    required this.languageLabel,
    this.onDriverMode,
    this.onNotifications,
    this.onSecurity,
    this.onLanguage,
  });

  final UserProfile profile;
  final String languageLabel;
  final VoidCallback? onDriverMode;
  final VoidCallback? onNotifications;
  final VoidCallback? onSecurity;
  final VoidCallback? onLanguage;

  void _openEdit(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditProfilePage(profile: profile)),
    );
  }

  /// Code de parrainage et crédits (`GET /api/users/me/referral`).
  Future<void> _showReferral(BuildContext context) async {
    try {
      final data =
          await ApiClient.instance.request('GET', '/api/users/me/referral');
      if (!context.mounted) return;
      final code = data['referralCode']?.toString() ?? '';
      final credit = asNum(data['availableCredit'])?.toInt() ?? 0;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Parrainage Moovi'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Votre code de parrainage :'),
              const SizedBox(height: 6),
              SelectableText(code,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
              const SizedBox(height: 12),
              Text('Crédit disponible : $credit FCFA'),
              const SizedBox(height: 6),
              const Text(
                'Vous et votre filleul recevez chacun un bonus après sa première course payée.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vraiment vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Déconnexion'),
          ),
        ],
      ),
    );
    if (ok == true) await AuthService.instance.logout();
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer mon compte'),
        content: const Text(
            'Votre compte sera désactivé et vos données personnelles anonymisées. Cette action est irréversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AuthService.instance.deleteAccount();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: Column(
        children: [
          ProfileAvatar(
            size: 100,
            imageUrl: profile.photoUrl,
            badgeIcon: Icons.edit_rounded,
            onTap: () => _openEdit(context),
          ),
          const SizedBox(height: 10),
          Text(
            profile.fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.background,
            ),
          ),
          if (profile.phone.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              profile.phone,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 30,
            child: OutlinedButton(
              onPressed: () => _openEdit(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.background,
                side: const BorderSide(color: AppColors.primary, width: 1.2),
                padding: const EdgeInsets.symmetric(horizontal: 22),
                shape: const StadiumBorder(),
              ),
              child: const Text(
                'Modifier profil',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.star_rounded,
                  value: profile.rating.toStringAsFixed(1),
                  label: 'RATING',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _StatCard(
                  icon: Icons.directions_car_outlined,
                  value: '${profile.ridesCount}',
                  label: 'COURSES',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _DriverBanner(onTap: onDriverMode ?? () async {
            bool isDriver;
            try {
              isDriver = await DriverService.instance.isDriverRegistered();
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(errorMessage(e))));
              return;
            }
            if (!context.mounted) return;
            if (isDriver) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const OffersPage(),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ChooseVehiclePage(),
                ),
              );
            }
          }),
          const SizedBox(height: 22),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFEAEAEA), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.notifications_none_rounded,
                  title: 'Notifications',
                  onTap: onNotifications,
                ),
                const _TileDivider(),
                _SettingsTile(
                  icon: Icons.shield_outlined,
                  title: 'Sécurité',
                  onTap: onSecurity,
                ),
                const _TileDivider(),
                _SettingsTile(
                  icon: Icons.language_rounded,
                  title: 'Langue',
                  trailingText: languageLabel,
                  onTap: onLanguage,
                ),
                const _TileDivider(),
                _SettingsTile(
                  icon: Icons.card_giftcard_rounded,
                  title: 'Parrainage',
                  onTap: () => _showReferral(context),
                ),
                const _TileDivider(),
                _SettingsTile(
                  icon: Icons.logout_rounded,
                  title: 'Déconnexion',
                  onTap: () => _confirmLogout(context),
                ),
                const _TileDivider(),
                _SettingsTile(
                  icon: Icons.delete_outline_rounded,
                  title: 'Supprimer mon compte',
                  onTap: () => _confirmDelete(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 65,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cream.withOpacity(0.6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontFamily: _monoFont,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: AppColors.darkBrown,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverBanner extends StatelessWidget {
  const _DriverBanner({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 16, 22),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Passer en mode chauffeur',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Gagnez de l\'argent avec Moovi',
                        style: TextStyle(fontSize: 12, color: Color(0xCCFFFFFF)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.trending_up_rounded,
                      color: Colors.white, size: 26),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.trailingText,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? trailingText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 25,
              decoration: BoxDecoration(
                color: AppColors.cream.withOpacity(0.6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 21, color: AppColors.primary),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkBrown,
                ),
              ),
            ),
            if (trailingText != null) ...[
              Text(
                trailingText!,
                style: const TextStyle(fontSize: 13, color: AppColors.darkBrown),
              ),
              const SizedBox(width: 4),
            ],
            const Icon(Icons.chevron_right_rounded,
                size: 24, color: AppColors.darkBrown),
          ],
        ),
      ),
    );
  }
}

class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: Color(0xFFF1EEEA));
}
