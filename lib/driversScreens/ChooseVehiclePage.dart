import 'package:flutter/material.dart';
import 'package:moovi/driversScreens/CarInfos.dart';
import 'package:moovi/driversScreens/MotoInfos.dart';
import 'package:moovi/widgets/moovi_scaffold.dart';

const _ink = Color(0xFF3A2208);

enum VehicleType { car, moto }

class ChooseVehiclePage extends StatefulWidget {
  const ChooseVehiclePage({super.key});

  @override
  State<ChooseVehiclePage> createState() => _ChooseVehiclePageState();
}

class _ChooseVehiclePageState extends State<ChooseVehiclePage> {
  VehicleType? _selected;

  void _onContinue() {
    final selected = _selected;
    if (selected == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            selected == VehicleType.moto ? const Motoinfos() : const Carinfos(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MooviGradient.start,
      body: MooviGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              const MooviHeader(title: 'Devenir chauffeur'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  children: [
                    const Text(
                      'Choisissez votre véhicule',
                      style: TextStyle(
                        fontSize: 26,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Sélectionnez le véhicule que vous utiliserez pour effectuer vos courses.',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    const SizedBox(height: 28),
                    _VehicleCard(
                      icon: Icons.directions_car_rounded,
                      title: 'Voiture',
                      subtitle: 'Transport de personnes',
                      selected: _selected == VehicleType.car,
                      onTap: () => setState(() => _selected = VehicleType.car),
                    ),
                    const SizedBox(height: 16),
                    _VehicleCard(
                      icon: Icons.two_wheeler_rounded,
                      title: 'Moto',
                      subtitle: 'Transport léger ou livraison',
                      selected: _selected == VehicleType.moto,
                      onTap: () => setState(() => _selected = VehicleType.moto),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 62,
                  child: ElevatedButton(
                    onPressed: _selected == null ? null : _onContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: MooviGradient.end,
                      disabledBackgroundColor: Colors.white.withValues(alpha: 0.35),
                      disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
                      elevation: _selected == null ? 0 : 6,
                      shadowColor: Colors.black26,
                      shape: const StadiumBorder(),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Continuer',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        SizedBox(width: 10),
                        Icon(Icons.arrow_forward_rounded, size: 22),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected ? Colors.white : MooviGradient.card,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: selected ? MooviGradient.brownCard : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: selected ? MooviGradient.end : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon,
                    size: 28, color: selected ? Colors.white : _ink),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: _ink.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 24,
                color: selected ? MooviGradient.end : _ink.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
