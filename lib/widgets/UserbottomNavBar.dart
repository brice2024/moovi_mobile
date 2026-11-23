import 'package:flutter/material.dart';
import 'package:moovi/widgets/moovi_scaffold.dart';

/// Hauteur de la barre (hors zone de sécurité du bas). Les pages affichées
/// derrière la barre ajoutent cette valeur à leur marge basse.
const double kMooviNavBarHeight = 84;

/// Marge à laisser en bas d'une page affichée sous la barre d'onglets.
double mooviNavBarInset(BuildContext context) =>
    MediaQuery.of(context).padding.bottom + kMooviNavBarHeight + 16;

/// Barre d'onglets du bas (maquette 17) : fond blanc, coins hauts arrondis,
/// onglet actif = pilule orange avec icône et libellé blancs.
class CustomNavbar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const CustomNavbar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  static const _items = [
    (Icons.directions_car_outlined, Icons.directions_car_rounded, 'COURSE'),
    (Icons.history_rounded, Icons.history_rounded, 'HISTORIQUE'),
    (Icons.payments_outlined, Icons.payments_rounded, 'WALLET'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'PROFIL'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      height: kMooviNavBarHeight + bottom,
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(child: _navItem(i)),
        ],
      ),
    );
  }

  Widget _navItem(int index) {
    final (icon, activeIcon, title) = _items[index];
    final isSelected = selectedIndex == index;
    final color = isSelected ? Colors.white : const Color(0xFF2B1A0A);

    return Semantics(
      button: true,
      selected: isSelected,
      label: title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onItemSelected(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: isSelected ? MooviGradient.end : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(isSelected ? activeIcon : icon, size: 22, color: color),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    letterSpacing: 0.3,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
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
