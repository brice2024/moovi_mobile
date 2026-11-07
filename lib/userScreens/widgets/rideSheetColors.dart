import 'package:flutter/material.dart';
import '../../functions.dart';

/// ─────────────────────────────────────────────
/// COULEURS
/// ─────────────────────────────────────────────
class RideSheetColors {
  RideSheetColors._();

  static const Color sheetBackground = Colors.white;

  // Carte sélectionnée (orange)
  static const Color selectedCard = Color(0xFFEF6C3A);
  static const Color selectedIconBg = Color(0xFFD9592A);
  static const Color selectedText = Colors.white;
  static const Color selectedSubtitle = Color(0xFFFFE0D3);
  static const Color selectedShadow = Color(0x55EF6C3A);

  // Cartes non sélectionnées (noir)
  static const Color unselectedCard = Color(0xFF161616);
  static const Color unselectedIconBg = Color(0xFF2A2A2A);
  static const Color unselectedIcon = Color(0xFFBDBDBD);
  static const Color unselectedText = Colors.white;
  static const Color unselectedSubtitle = Color(0xFFB5B5B5);

  // Sélecteur de prix
  static const Color priceBarBackground = Color(0xFF161616);
  static const Color priceText = Color(0xFFFFFFFF);
  static const Color priceCurrency = Color(0xFFEF6C3A);
  static const Color priceIcon = Color(0xFF8BC34A);
  static const Color priceButtonBg = Color(0xFF2A2A2A);
  static const Color priceButtonIcon = Colors.white;

  // Bouton principal
  static const Color primaryButton = Color(0xFFFF4D00);
  static const Color primaryButtonText = Colors.white;
}

/// ─────────────────────────────────────────────
/// MODÈLE
/// ─────────────────────────────────────────────
class RideOption {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final double price;

  const RideOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.price,
  });
}

const List<RideOption> kRideOptions = [
  RideOption(
    id: 'voiture',
    title: 'Voiture',
    subtitle: '4 places • Course standard',
    icon: Icons.local_taxi_rounded,
    price: 2000,
  ),
  RideOption(
    id: 'confort',
    title: 'Comfort',
    subtitle: 'Berline premium climatisée',
    icon: Icons.directions_car_filled_rounded,
    price: 3500,
  ),
  RideOption(
    id: 'moto',
    title: 'Moto',
    subtitle: 'Le plus rapide en circulation',
    icon: Icons.two_wheeler_rounded,
    price: 1000,
  ),
];

/// ─────────────────────────────────────────────
/// APPEL DU BOTTOM SHEET
/// ─────────────────────────────────────────────
Future<void> showRideSelectionSheet(
  BuildContext context, {
  required double departureLat,
  required double departureLng,
  required double destinationLat,
  required double destinationLng,
  String departureAddress = 'Point de départ',
  String destinationAddress = 'Destination',
  String distanceText = '',
  String durationText = '',
  required void Function(RideOption option, double price, String? rideId) onConfirm,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => RideSelectionSheet(
      onConfirm: onConfirm,
      departureLat: departureLat,
      departureLng: departureLng,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      departureAddress: departureAddress,
      destinationAddress: destinationAddress,
      distanceText: distanceText,
      durationText: durationText,
    ),
  );
}

/// ─────────────────────────────────────────────
/// BOTTOM SHEET
/// ─────────────────────────────────────────────
class RideSelectionSheet extends StatefulWidget {
  final double departureLat;
  final double departureLng;
  final double destinationLat;
  final double destinationLng;
  final String departureAddress;
  final String destinationAddress;
  final String distanceText;
  final String durationText;
  final void Function(RideOption option, double price, String? rideId) onConfirm;

  const RideSelectionSheet({
    super.key,
    required this.onConfirm,
    required this.departureLat,
    required this.departureLng,
    required this.destinationLat,
    required this.destinationLng,
    this.departureAddress = 'Point de départ',
    this.destinationAddress = 'Destination',
    this.distanceText = '',
    this.durationText = '',
  });

  @override
  State<RideSelectionSheet> createState() => _RideSelectionSheetState();
}

class _RideSelectionSheetState extends State<RideSelectionSheet> {
  static const double _priceStep = 250.0;

  late RideOption _selected;
  late double _price;

  @override
  void initState() {
    super.initState();
    _selected = kRideOptions.first;
    _price = _selected.price;
  }

  void _select(RideOption option) {
    setState(() {
      _selected = option;
      _price = option.price;
    });
  }

  void _changePrice(double delta) {
    setState(() {
      _price = (_price + delta).clamp(500, 50000).toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: RideSheetColors.sheetBackground,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in kRideOptions) ...[
              _RideOptionCard(
                option: option,
                selected: option.id == _selected.id,
                onTap: () => _select(option),
              ),
              const SizedBox(height: 12),
            ],
            _PriceSelector(
              price: _price,
              onMinus: () => _changePrice(-_priceStep),
              onPlus: () => _changePrice(_priceStep),
            ),
            const SizedBox(height: 14),
            _PrimaryButton(
              label: 'TROUVER UN CHAUFFEUR',
              onTap: () async {
                Navigator.pop(context);
                final rideId = await addRide(
                  departureLat: widget.departureLat,
                  departureLng: widget.departureLng,
                  destinationLat: widget.destinationLat,
                  destinationLng: widget.destinationLng,
                  price: _price.toInt(),
                  departureAddress: widget.departureAddress,
                  destinationAddress: widget.destinationAddress,
                  rideType: _selected.id,
                  distanceText: widget.distanceText,
                  durationText: widget.durationText,
                );
                widget.onConfirm(_selected, _price, rideId);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────
/// CARTE D'UNE OPTION
/// ─────────────────────────────────────────────
class _RideOptionCard extends StatelessWidget {
  final RideOption option;
  final bool selected;
  final VoidCallback onTap;

  const _RideOptionCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? RideSheetColors.selectedCard
        : RideSheetColors.unselectedCard;
    final iconBg = selected
        ? RideSheetColors.selectedIconBg
        : RideSheetColors.unselectedIconBg;
    final iconColor = selected
        ? RideSheetColors.selectedText
        : RideSheetColors.unselectedIcon;
    final titleColor = selected
        ? RideSheetColors.selectedText
        : RideSheetColors.unselectedText;
    final subtitleColor = selected
        ? RideSheetColors.selectedSubtitle
        : RideSheetColors.unselectedSubtitle;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
          boxShadow: selected
              ? [
                  const BoxShadow(
                    color: RideSheetColors.selectedShadow,
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(option.icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.title,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    option.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${option.price.toInt()} FCFA',
              style: TextStyle(
                color: titleColor,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────
/// SÉLECTEUR DE PRIX (- 2000 FCFA +)
/// ─────────────────────────────────────────────
class _PriceSelector extends StatelessWidget {
  final double price;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _PriceSelector({
    required this.price,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: RideSheetColors.priceBarBackground,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          _RoundIconButton(icon: Icons.remove, onTap: onMinus),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${price.toInt()}',
                  style: const TextStyle(
                    color: RideSheetColors.priceText,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'FCFA',
                  style: TextStyle(
                    color: RideSheetColors.priceCurrency,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.payments_rounded,
                  color: RideSheetColors.priceIcon,
                  size: 16,
                ),
              ],
            ),
          ),
          _RoundIconButton(icon: Icons.add, onTap: onPlus),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          color: RideSheetColors.priceButtonBg,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: RideSheetColors.priceButtonIcon, size: 18),
      ),
    );
  }
}

/// ─────────────────────────────────────────────
/// BOUTON PRINCIPAL
/// ─────────────────────────────────────────────
class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: RideSheetColors.primaryButton,
          borderRadius: BorderRadius.circular(31),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: RideSheetColors.primaryButtonText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.arrow_forward_rounded,
              color: RideSheetColors.primaryButtonText,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
