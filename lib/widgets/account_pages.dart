import 'package:flutter/material.dart';

import '../services/Auth.dart';
import '../services/api_client.dart';
import '../services/contact_service.dart';
import '../services/driver_service.dart';
import '../services/local_notifications.dart';
import '../services/session.dart';
import 'notifications_page.dart';

const _orange = Color(0xFFFF7A00);

PreferredSizeWidget _appBar(String title) => AppBar(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0.5,
      title: Text(title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );

Widget _section(List<Widget> children) => Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(children: children),
    );

/// Retourne à l'écran racine puis ferme la session (l'AuthWrapper affiche
/// alors l'écran de connexion).
Future<void> _signOut(BuildContext context, Future<void> Function() action) async {
  final nav = Navigator.of(context);
  await action();
  nav.popUntil((r) => r.isFirst);
}

/// Choix de la langue : seul le français est disponible pour l'instant.
Future<void> showLanguageSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (_) => const SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              title: Text('Langue de l\'application',
                  style: TextStyle(fontWeight: FontWeight.w700))),
          ListTile(
            leading: Icon(Icons.check_circle, color: _orange),
            title: Text('Français'),
          ),
          ListTile(
            enabled: false,
            leading: Icon(Icons.circle_outlined),
            title: Text('English'),
            subtitle: Text('Bientôt disponible'),
          ),
          SizedBox(height: 8),
        ]),
      ),
    );

/// Sécurité du compte : session, déconnexion, suppression.
class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer mon compte ?'),
        content: const Text(
            'Votre compte sera désactivé et vos données personnelles anonymisées. '
            'Cette action est définitive.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await _signOut(context, AuthService.instance.deleteAccount);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage(e)), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AppSession.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F8),
      appBar: _appBar('Sécurité'),
      body: ListView(children: [
        _section([
          ListTile(
            leading: const Icon(Icons.phone_iphone),
            title: const Text('Numéro de connexion'),
            subtitle: Text(user?.phoneNumber ?? '—'),
          ),
          const ListTile(
            leading: Icon(Icons.verified_user_outlined),
            title: Text('Connexion par code WhatsApp'),
            subtitle: Text(
                'Aucun mot de passe : un code à usage unique est envoyé à chaque connexion.'),
          ),
        ]),
        _section([
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Se déconnecter de cet appareil'),
            onTap: () => _signOut(context, AuthService.instance.logout),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Supprimer mon compte',
                style: TextStyle(color: Colors.red)),
            onTap: () => _delete(context),
          ),
        ]),
      ]),
    );
  }
}

/// Paramètres généraux (notifications, langue, sécurité).
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F8),
      appBar: _appBar('Paramètres'),
      body: ListView(children: [
        _section([
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Autoriser les notifications'),
            subtitle: const Text('Courses et messages reçus en arrière-plan'),
            onTap: () async {
              await LocalNotifications.instance.requestPermission();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Préférence enregistrée dans les réglages du téléphone')));
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('Mes notifications'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const NotificationsPage())),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Langue'),
            trailing: const Text('Français'),
            onTap: () => showLanguageSheet(context),
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Sécurité'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SecurityPage())),
          ),
        ]),
      ]),
    );
  }
}

/// Assistance : FAQ et contacts du service client fournis par l'API.
class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  static const _faq = [
    ('Comment est fixé le prix ?',
        'Vous proposez un prix dans la fourchette indiquée ; les chauffeurs peuvent accepter ou faire une contre-offre.'),
    ('Comment payer ma course ?',
        'En espèces au chauffeur, ou par Airtel Money / Moov Money depuis l\'application à la fin de la course.'),
    ('Comment devenir chauffeur ?',
        'Depuis votre profil, « Passer en mode chauffeur », puis envoyez vos documents. Votre dossier est validé par l\'équipe Moovi.'),
    ('Pourquoi je ne peux pas me mettre en ligne ?',
        'Votre dossier doit être validé et votre portefeuille ne doit pas être bloqué (solde insuffisant pour la commission).'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F8),
      appBar: _appBar('Assistance'),
      body: ListView(children: [
        FutureBuilder<Map<String, dynamic>>(
          future: ApiClient.instance.request('GET', '/api/support', authenticated: false),
          builder: (context, snap) {
            final d = snap.data ?? const {};
            final phone = d['phone']?.toString();
            final whatsapp = d['whatsapp']?.toString();
            final email = d['email']?.toString();
            final tiles = <Widget>[
              if (whatsapp != null)
                ListTile(
                  leading: const Icon(Icons.chat, color: Color(0xFF25D366)),
                  title: const Text('WhatsApp'),
                  subtitle: Text(whatsapp),
                  onTap: () => ContactService.open(context,
                      'https://wa.me/${whatsapp.replaceAll(RegExp(r'[^0-9]'), '')}'),
                ),
              if (phone != null)
                ListTile(
                  leading: const Icon(Icons.call, color: _orange),
                  title: const Text('Appeler le service client'),
                  subtitle: Text(phone),
                  onTap: () => ContactService.call(context, phone),
                ),
              if (email != null)
                ListTile(
                  leading: const Icon(Icons.mail_outline, color: _orange),
                  title: const Text('E-mail'),
                  subtitle: Text(email),
                  onTap: () => ContactService.open(context, 'mailto:$email'),
                ),
            ];
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: _orange)),
              );
            }
            if (tiles.isEmpty) return const SizedBox.shrink();
            return _section(tiles);
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Text('Questions fréquentes',
              style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700)),
        ),
        _section([
          for (final (q, a) in _faq)
            ExpansionTile(
              title: Text(q, style: const TextStyle(fontSize: 14)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [Text(a, style: const TextStyle(color: Colors.black87))],
            ),
        ]),
        const SizedBox(height: 24),
      ]),
    );
  }
}

/// Véhicule du chauffeur et état de validation du dossier.
class VehicleInfoPage extends StatefulWidget {
  const VehicleInfoPage({super.key});

  @override
  State<VehicleInfoPage> createState() => _VehicleInfoPageState();
}

class _VehicleInfoPageState extends State<VehicleInfoPage> {
  // Créé une fois (et non à chaque reconstruction de l'écran).
  late final Future<Map<String, dynamic>?> _driver =
      DriverService.instance.getMyDriver();

  static const _status = {
    'approved': ('Validé', Color(0xFF2E7D32)),
    'pending': ('En attente de validation', Color(0xFFB26A00)),
    'rejected': ('Refusé', Colors.red),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F8),
      appBar: _appBar('Informations du véhicule'),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _driver,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: _orange));
          }
          final d = snap.data;
          if (d == null) {
            return const Center(child: Text('Profil chauffeur introuvable'));
          }
          final v = d['vehicle'] is Map
              ? Map<String, dynamic>.from(d['vehicle'] as Map)
              : <String, dynamic>{};
          final status = _status[d['verificationStatus']] ??
              (d['verificationStatus']?.toString() ?? '—', Colors.grey);
          final docs = d['documents'] is Map ? d['documents'] as Map : const {};
          String val(dynamic x) =>
              (x == null || x.toString().isEmpty) ? '—' : x.toString();
          return ListView(children: [
            _section([
              ListTile(
                leading: Icon(d['vehicleType'] == 'moto'
                    ? Icons.two_wheeler
                    : Icons.directions_car_filled_outlined),
                title: Text('${val(v['brand'])} ${v['model'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(val(d['vehicleType'])),
              ),
              ListTile(title: const Text('Couleur'), trailing: Text(val(v['color']))),
              ListTile(title: const Text('Plaque'), trailing: Text(val(d['plate']))),
            ]),
            _section([
              ListTile(
                title: const Text('Statut du dossier'),
                trailing: Text(status.$1,
                    style: TextStyle(color: status.$2, fontWeight: FontWeight.w700)),
              ),
              if (docs.isNotEmpty)
                ListTile(
                  title: const Text('Documents'),
                  trailing: Text(
                      '${docs['verified'] ?? 0} validés / ${docs['total'] ?? 0}'),
                ),
            ]),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Pour changer de véhicule, contactez l\'assistance : '
                'le nouveau véhicule doit être validé avant de reprendre des courses.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
