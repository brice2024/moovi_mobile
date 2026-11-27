import 'package:flutter/material.dart';
import '../../services/Auth.dart';
import '../../services/api_client.dart';
import '../../services/driver_service.dart';
import 'driver_theme.dart';
import '../wallet/driver_wallet_page.dart';
import '../../widgets/notifications_page.dart';
import '../../widgets/account_pages.dart';

/// iPhone 16 Pro - 96 : profil chauffeur
class DriverProfilePage extends StatelessWidget {
  const DriverProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            Align(
              alignment: Alignment.centerLeft,
              child: RoundOrangeButton(
                  icon: Icons.arrow_back,
                  onTap: () => Navigator.maybePop(context)),
            ),
            FutureBuilder<Map<String, dynamic>?>(
              future: DriverService.instance.getMyDriver(),
              builder: (context, snap) {
                final d = snap.data ?? DriverService.instance.cachedDriver;
                return _DriverHeader(driver: d);
              },
            ),
            const SizedBox(height: 20),
            _MenuTile(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Mon Portefeuille & Commissions Moovi',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DriverWalletPage()),
                );
              },
            ),
            const SizedBox(height: 10),
            _MenuTile(
                icon: Icons.settings_outlined,
                label: 'Paramètres',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsPage()))),
            const SizedBox(height: 10),
            _MenuTile(
                icon: Icons.directions_car_outlined,
                label: 'Informations du véhicule',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const VehicleInfoPage()))),
            const SizedBox(height: 10),
            _MenuTile(
                icon: Icons.notifications_none,
                label: 'Notifications',
                onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const NotificationsPage()),
                    )),
            const SizedBox(height: 10),
            _MenuTile(
                icon: Icons.help_outline,
                label: 'Assistance',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SupportPage()))),
            const Spacer(),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(.06), blurRadius: 10)
                ],
              ),
              child: ListTile(
                onTap: () async {
                  final shouldLogout = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Déconnexion'),
                      content:
                          const Text('Voulez-vous vraiment vous déconnecter ?'),
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
                  if (shouldLogout == true && context.mounted) {
                    await AuthService.instance.logout();
                  }
                },
                leading: const Icon(Icons.logout, color: Colors.red, size: 20),
                title: const Text('Déconnexion',
                    style: TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuTile(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: MooviColors.orange,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Row(children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.2),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: Colors.white, size: 15),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
              const Icon(Icons.chevron_right, color: Colors.white, size: 18),
            ]),
          ),
        ),
      );
}


/// En-tête du profil alimenté par `GET /api/drivers/me`.
class _DriverHeader extends StatelessWidget {
  final Map<String, dynamic>? driver;
  const _DriverHeader({required this.driver});

  @override
  Widget build(BuildContext context) {
    final d = driver ?? const <String, dynamic>{};
    final name = (d['driverName'] ?? '').toString().trim();
    final vehicle = (d['vehicleLabel'] ?? '').toString().trim();
    final plate = (d['plate'] ?? '').toString().trim();
    final subtitle = [vehicle, plate].where((e) => e.isNotEmpty).join(' • ');
    final rating = asNum(d['rating'])?.toDouble() ?? 0;
    final level = (d['level'] ?? '').toString().trim();
    final photo = (d['photoUrl'] ?? '').toString();
    final online = d['isAvailable'] == true;

    return Transform.translate(
      offset: const Offset(0, -10),
      child: Column(children: [
        Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
                color: MooviColors.orange, shape: BoxShape.circle),
            child: CircleAvatar(
              radius: 36,
              backgroundColor: MooviColors.bg,
              backgroundImage: photo.isNotEmpty
                  ? NetworkImage(photo, headers: ApiClient.instance.authHeaders)
                  : null,
              child: photo.isEmpty ? const Icon(Icons.person, size: 36) : null,
            ),
          ),
          Positioned(
            bottom: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: MooviColors.orange,
                  borderRadius: BorderRadius.circular(10)),
              child: Text(rating > 0 ? '★ ${rating.toStringAsFixed(2)}' : '★ –',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Text(name.isNotEmpty ? name : 'Chauffeur Moovi',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        if (subtitle.isNotEmpty)
          Text(subtitle,
              style: const TextStyle(fontSize: 11, color: MooviColors.grey)),
        const SizedBox(height: 10),
        Row(mainAxisSize: MainAxisSize.min, children: [
          OnlineChip(online: online),
          if (level.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: MooviColors.orange,
                  borderRadius: BorderRadius.circular(20)),
              child: Text('PARTENAIRE ${level.toUpperCase()}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
      ]),
    );
  }
}
