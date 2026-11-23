import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:moovi/widgets/moovi_scaffold.dart';

import '../../driversScreens/ChooseVehiclePage.dart';
import '../../driversScreens/DriverDocsVerificationPage.dart';
import '../../driversScreens/test/offers_page.dart';
import '../../services/driver_service.dart';
import '../../widgets/UserbottomNavBar.dart';
import '../settings/language_page.dart';
import '../settings/notifications_settings_page.dart';
import '../settings/security_page.dart';
import '../settings/settings_widgets.dart';
import 'edit_profile_page.dart';
import 'profile_avatar.dart';
import 'user_profile.dart';

/// Onglet « PROFIL » (maquette 17).
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, this.onBack});

  /// Flèche retour de l'en-tête (ramène à l'onglet « COURSE »).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: MooviGradient.start,
      body: MooviGradientBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              MooviHeader(title: 'Profil', onBack: onBack),
              Expanded(
                child: user == null
                    ? const _Message('Vous devez être connecté.')
                    : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return const _Message('Impossible de charger le profil.');
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            );
                          }

                          var profile =
                              UserProfile.fromMap(user.uid, snapshot.data!.data());
                          // Repli sur le numéro de l'auth si absent de Firestore
                          if (profile.phone.isEmpty &&
                              (user.phoneNumber ?? '').isNotEmpty) {
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
                          return _ProfileContent(profile: profile);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(text, style: const TextStyle(color: Colors.white)),
      );
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.profile});

  final UserProfile profile;

  void _openEdit(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditProfilePage(profile: profile)),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  /// Non inscrit -> choix du véhicule ; inscrit mais non validé -> vérification ;
  /// validé -> offres de courses.
  Future<void> _openDriverMode(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final data = await DriverService.instance.getDriverData(uid);
    if (!context.mounted) return;

    final registered =
        data != null && (data.containsKey('car') || data.containsKey('moto'));
    final Widget page;
    if (!registered) {
      page = const ChooseVehiclePage();
    } else if (data['verificationStatus'] != 'approved') {
      page = const DriverVerificationPage();
    } else {
      page = const OffersPage();
    }
    _push(context, page);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, mooviNavBarInset(context)),
      child: Column(
        children: [
          ProfileAvatar(
            size: 112,
            imageUrl: profile.photoUrl,
            badgeIcon: Icons.edit_rounded,
            ringColor: Colors.white,
            badgeColor: Colors.white,
            badgeIconColor: kMooviInk,
            onTap: () => _openEdit(context),
          ),
          const SizedBox(height: 12),
          Text(
            profile.fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          if (profile.phone.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              profile.phone,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: OutlinedButton(
              onPressed: () => _openEdit(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white, width: 1.2),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: const StadiumBorder(),
              ),
              child: const Text(
                'Modifier profil',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.star_rounded,
                  value: profile.rating > 0
                      ? profile.rating.toStringAsFixed(1)
                      : '–',
                  label: 'NOTE',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _RidesCountCard(
                  uid: profile.uid,
                  storedCount: profile.ridesCount,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _DriverBanner(onTap: () => _openDriverMode(context)),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                onTap: () => _push(context, const NotificationsSettingsPage()),
              ),
              SettingsTile(
                icon: Icons.shield_rounded,
                title: 'Sécurité',
                onTap: () => _push(context, const SecurityPage()),
              ),
              SettingsTile(
                icon: Icons.language_rounded,
                title: 'Langue',
                trailingText: 'Français',
                onTap: () => _push(context, const LanguagePage()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Nombre de courses : valeur stockée sur le profil, ou à défaut le nombre de
/// courses payées dans `users/{uid}/rides`.
class _RidesCountCard extends StatefulWidget {
  const _RidesCountCard({required this.uid, required this.storedCount});

  final String uid;
  final int storedCount;

  @override
  State<_RidesCountCard> createState() => _RidesCountCardState();
}

class _RidesCountCardState extends State<_RidesCountCard> {
  late final Future<int> _paidRides = _countPaidRides();

  Future<int> _countPaidRides() async {
    try {
      final agg = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('rides')
          .where('isPaid', isEqualTo: true)
          .count()
          .get();
      return agg.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _paidRides,
      builder: (context, snap) {
        final count = math.max(widget.storedCount, snap.data ?? 0);
        return _StatCard(
          icon: Icons.directions_car_rounded,
          value: '$count',
          label: 'COURSES',
        );
      },
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
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: MooviGradient.card,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: MooviGradient.end),
              const SizedBox(width: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: MooviGradient.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: kMooviInk,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverBanner extends StatelessWidget {
  const _DriverBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MooviGradient.brownCard,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 20, 26),
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
                      "Gagnez de l'argent avec Moovi",
                      style: TextStyle(fontSize: 12, color: Color(0xD9FFFFFF)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 50,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.trending_up_rounded,
                    color: Colors.white, size: 26),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
