import 'package:flutter/material.dart';
import 'driver_theme.dart';

/// iPhone 16 Pro - 96 : profil chauffeur
class DriverProfilePage extends StatelessWidget {
  const DriverProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String)>[
      (Icons.settings_outlined, 'Paramètres'),
      (Icons.directions_car_outlined, 'Informations du véhicule'),
      (Icons.notifications_none, 'Notifications'),
      (Icons.help_outline, 'Assistance'),
    ];
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            Align(
              alignment: Alignment.centerLeft,
              child: RoundOrangeButton(icon: Icons.arrow_back, onTap: () => Navigator.maybePop(context)),
            ),
            Transform.translate(
              offset: const Offset(0, -10),
              child: Column(children: [
                Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: MooviColors.orange, shape: BoxShape.circle),
                    child: const CircleAvatar(
                      radius: 36,
                      backgroundColor: MooviColors.bg,
                      // backgroundImage: NetworkImage(photoUrl),
                      child: Icon(Icons.person, size: 36),
                    ),
                  ),
                  Positioned(
                    bottom: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: MooviColors.orange, borderRadius: BorderRadius.circular(10)),
                      child: const Text('★ 4.78',
                          style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                const Text('Ahmed B.', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                const Text('Dacia Logan • ABC-123',
                    style: TextStyle(fontSize: 11, color: MooviColors.grey)),
                const SizedBox(height: 10),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const OnlineChip(),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: MooviColors.orange, borderRadius: BorderRadius.circular(20)),
                    child: const Text('PARTENAIRE GOLD',
                        style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 20),
            for (final it in items) ...[
              _MenuTile(icon: it.$1, label: it.$2, onTap: () {}),
              const SizedBox(height: 10),
            ],
            const Spacer(),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 10)],
              ),
              child: ListTile(
                onTap: () {},
                leading: const Icon(Icons.logout, color: Colors.red, size: 20),
                title: const Text('Déconnexion',
                    style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w600)),
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
  const _MenuTile({required this.icon, required this.label, required this.onTap});

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
                    color: Colors.white.withOpacity(.2), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: Colors.white, size: 15),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              const Icon(Icons.chevron_right, color: Colors.white, size: 18),
            ]),
          ),
        ),
      );
}
