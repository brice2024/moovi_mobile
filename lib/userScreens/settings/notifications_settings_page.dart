import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:moovi/widgets/moovi_scaffold.dart';

import 'settings_widgets.dart';

/// Préférences de notifications, enregistrées dans
/// `users/{uid}.settings.notifications.{rides,promos}` (true par défaut).
class NotificationsSettingsPage extends StatelessWidget {
  const NotificationsSettingsPage({super.key});

  Future<void> _save(BuildContext context, String uid, String key, bool value) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'settings': {
          'notifications': {key: value},
        },
      }, SetOptions(merge: true));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text("Impossible d'enregistrer la préférence. Réessayez."),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return SettingsScaffold(
      title: 'Notifications',
      subtitle: 'Choisissez les notifications que vous souhaitez recevoir.',
      children: [
        if (uid == null)
          const Text('Vous devez être connecté.',
              style: TextStyle(color: Colors.white))
        else
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .snapshots(),
            builder: (context, snap) {
              final settings = snap.data?.data()?['settings'];
              final notif = settings is Map ? settings['notifications'] : null;
              bool read(String key) =>
                  notif is Map ? notif[key] != false : true;

              return SettingsCard(
                children: [
                  _SwitchTile(
                    icon: Icons.directions_car_rounded,
                    title: 'Courses',
                    subtitle: 'Offres des chauffeurs, arrivée, fin de course',
                    value: read('rides'),
                    onChanged: snap.hasData
                        ? (v) => _save(context, uid, 'rides', v)
                        : null,
                  ),
                  _SwitchTile(
                    icon: Icons.local_offer_rounded,
                    title: 'Promotions',
                    subtitle: 'Bons plans et nouveautés Moovi',
                    value: read('promos'),
                    onChanged: snap.hasData
                        ? (v) => _save(context, uid, 'promos', v)
                        : null,
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: MooviGradient.end,
      ),
    );
  }
}
