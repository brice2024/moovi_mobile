import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../driversScreens/ChooseVehiclePage.dart';
import '../../driversScreens/test/offers_page.dart';
import '../../services/driver_service.dart';
import '../../theme/app_colors.dart';
import 'edit_profile_page.dart';
import 'profile_avatar.dart';
import 'user_profile.dart';

const _monoFont = 'monospace';

class ProfilePage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: Text('Vous devez être connecté.')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Impossible de charger le profil.'));
            }
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            var profile = UserProfile.fromMap(user.uid, snapshot.data!.data());
            // Repli sur le numéro de l'auth si absent de Firestore
            if (profile.phone.isEmpty && (user.phoneNumber ?? '').isNotEmpty) {
              profile = UserProfile(
                uid: profile.uid,
                firstName: profile.firstName,
                lastName: profile.lastName,
                phone: user.phoneNumber!,
                photoUrl: profile.photoUrl,
                photoPath: profile.photoPath,
                rating: profile.rating,
                ridesCount: profile.ridesCount,
              );
            }

            return _ProfileContent(
              profile: profile,
              onDriverMode: onDriverMode,
              onNotifications: onNotifications,
              onSecurity: onSecurity,
              onLanguage: onLanguage,
              languageLabel: languageLabel,
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
          _DriverBanner(onTap: () async {
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) return;
            final isDriver = await DriverService.instance.isDriverRegistered(user.uid);
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
