import 'package:dotted_line/dotted_line.dart';
import 'package:flutter/material.dart';

import '../../functions.dart';
import '../ride/ride_cards.dart';
import '../ride/ride_style.dart';

/// ─────────────────────────────────────────────
/// COULEURS (maquette 11 « Votre offre »)
/// ─────────────────────────────────────────────
class RideSheetColors {
  RideSheetColors._();

  static const Color sheetBackground = Colors.white;
  static const Color card = RideColors.cream;
  static const Color cardBorder = Color(0xFFFFD9B8);
  static const Color label = Color(0xFFB07A45);
  static const Color text = RideColors.brown;
  static const Color accent = RideColors.orange;
  static const Color priceBox = RideColors.priceBox;
  static const Color primaryButton = RideColors.orange;
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

  /// Prix suggéré (FCFA).
  final double price;

  const RideOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.price,
  });

  /// Prix minimum accepté : 75 % du prix suggéré, arrondi à 50 FCFA.
  double get minPrice => _round50(price * 0.75).clamp(500, price).toDouble();

  /// Plafond du curseur de prix : 3 × le prix suggéré (max 50 000 FCFA).
  double get maxPrice => (price * 3).clamp(price, 50000).toDouble();

  static double _round50(double v) => (v / 50).round() * 50.0;
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
/// APPEL EN BOTTOM SHEET (conservé pour compatibilité)
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
  DateTime? scheduledAt,
  required void Function(RideOption option, double price, String? rideId) onConfirm,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
        ),
        child: RideSelectionSheet(
          onConfirm: (option, price, rideId) {
            Navigator.pop(sheetContext);
            onConfirm(option, price, rideId);
          },
          onBack: () => Navigator.pop(sheetContext),
          departureLat: departureLat,
          departureLng: departureLng,
          destinationLat: destinationLat,
          destinationLng: destinationLng,
          departureAddress: departureAddress,
          destinationAddress: destinationAddress,
          distanceText: distanceText,
          durationText: durationText,
          scheduledAt: scheduledAt,
        ),
      ),
    ),
  );
}

/// ─────────────────────────────────────────────
/// CARTE « VOTRE OFFRE » (maquette 11)
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
  final DateTime? scheduledAt;
  final VoidCallback? onBack;
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
    this.scheduledAt,
    this.onBack,
  });

  @override
  State<RideSelectionSheet> createState() => _RideSelectionSheetState();
}

class _RideSelectionSheetState extends State<RideSelectionSheet> {
  static const double _priceStep = 50.0;

  late RideOption _selected;
  late double _price;
  bool _submitting = false;

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

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    String? rideId;
    try {
      rideId = await addRide(
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
        scheduledAt: widget.scheduledAt,
      );
    } catch (e) {
      debugPrint('Erreur création course : $e');
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    if (rideId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Impossible de créer la course. Vérifiez votre connexion.'),
      ));
      return;
    }
    widget.onConfirm(_selected, _price, rideId);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RideSheetColors.sheetBackground,
      borderRadius: BorderRadius.circular(28),
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: DestinationHeader(onBack: widget.onBack),
            ),
            const SizedBox(height: 14),
            _RouteRecap(
              from: widget.departureAddress,
              to: widget.destinationAddress,
              distance: widget.distanceText,
              duration: widget.durationText,
              scheduledAt: widget.scheduledAt,
            ),
            const SizedBox(height: 12),
            _VehicleSelector(selected: _selected, onSelect: _select),
            const SizedBox(height: 16),
            _buildOfferTitle(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _PriceInfoCard(
                    label: 'PRIX SUGGÉRÉ',
                    value: formatFcfa(_selected.price),
                    onTap: () => setState(() => _price = _selected.price),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PriceInfoCard(
                    label: 'PRIX MINIMUM',
                    value: formatFcfa(_selected.minPrice),
                    onTap: () => setState(() => _price = _selected.minPrice),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(child: _PriceDisplay(price: _price)),
            const SizedBox(height: 10),
            _PriceSlider(
              value: _price,
              min: _selected.minPrice,
              max: _selected.maxPrice,
              step: _priceStep,
              onChanged: (v) => setState(() => _price = v),
            ),
            const SizedBox(height: 16),
            _PrimaryButton(
              label: 'Trouver un chauffeur',
              loading: _submitting,
              onTap: _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfferTitle() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Votre offre',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: RideSheetColors.text,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFFFD2A8),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'DEVISE : FCFA',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: RideSheetColors.text,
            ),
          ),
        ),
      ],
    );
  }
}

/// Récapitulatif départ / destination + distance / durée.
class _RouteRecap extends StatelessWidget {
  const _RouteRecap({
    required this.from,
    required this.to,
    required this.distance,
    required this.duration,
    this.scheduledAt,
  });

  final String from;
  final String to;
  final String distance;
  final String duration;
  final DateTime? scheduledAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: RideSheetColors.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 18, bottom: 6),
                  child: Column(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: RideColors.brownMid,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE9C9A6), width: 2),
                        ),
                      ),
                      const Expanded(
                        child: DottedLine(
                          direction: Axis.vertical,
                          lineThickness: 1.5,
                          dashLength: 2,
                          dashGapLength: 3,
                          dashColor: RideColors.brownMid,
                        ),
                      ),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: RideColors.brownMid,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SmallLabel('DÉPART'),
                      _place(from),
                      const SizedBox(height: 12),
                      const _SmallLabel('DESTINATION'),
                      _place(to),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (scheduledAt != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.event_rounded, size: 18, color: RideColors.brownMid),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Course prévue ${formatScheduleLong(scheduledAt!)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: RideColors.brownMid,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.8)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  icon: Icons.route_rounded,
                  label: 'DISTANCE',
                  value: distance.isEmpty ? '—' : distance,
                ),
              ),
              Expanded(
                child: _Metric(
                  icon: Icons.schedule_rounded,
                  label: 'DURÉE',
                  value: duration.isEmpty ? '—' : duration,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _place(String text) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: RideSheetColors.text,
        ),
      );
}

class _SmallLabel extends StatelessWidget {
  const _SmallLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
          color: RideSheetColors.label,
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFFFD2A8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: RideColors.brownMid),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SmallLabel(label),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: RideSheetColors.text,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Choix du type de véhicule (le prix en dépend).
class _VehicleSelector extends StatelessWidget {
  const _VehicleSelector({required this.selected, required this.onSelect});

  final RideOption selected;
  final ValueChanged<RideOption> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < kRideOptions.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _vehicleChip(kRideOptions[i])),
        ],
      ],
    );
  }

  Widget _vehicleChip(RideOption option) {
    final isSelected = option.id == selected.id;
    return GestureDetector(
      onTap: () => onSelect(option),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? RideColors.orange : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? RideColors.orange : RideSheetColors.cardBorder,
            width: 1.2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              option.icon,
              size: 22,
              color: isSelected ? Colors.white : RideColors.brownMid,
            ),
            const SizedBox(height: 2),
            Text(
              option.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : RideSheetColors.text,
              ),
            ),
            Text(
              '${formatFcfa(option.price)} F',
              style: TextStyle(
                fontSize: 11,
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.9)
                    : RideSheetColors.label,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceInfoCard extends StatelessWidget {
  const _PriceInfoCard({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: RideColors.creamLight,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: RideSheetColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: RideColors.orange,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: RideSheetColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceDisplay extends StatelessWidget {
  const _PriceDisplay({required this.price});
  final double price;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 6, 16, 6),
      decoration: BoxDecoration(
        color: RideSheetColors.priceBox,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: RideColors.orange.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            formatFcfa(price),
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'FCFA',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: RideSheetColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceSlider extends StatelessWidget {
  const _PriceSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final divisions = ((max - min) / step).round();
    final mid = ((min + max) / 2 / step).round() * step;
    const labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
      color: RideSheetColors.label,
    );
    return Column(
      children: [
        Container(
          height: 34,
          decoration: BoxDecoration(
            color: RideColors.cream,
            borderRadius: BorderRadius.circular(17),
          ),
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 22,
              activeTrackColor: RideColors.orange,
              inactiveTrackColor: RideColors.creamLight,
              thumbColor: RideColors.brownMid,
              overlayColor: RideColors.orange.withValues(alpha: 0.15),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 13),
              trackShape: const RoundedRectSliderTrackShape(),
              showValueIndicator: ShowValueIndicator.never,
              tickMarkShape: SliderTickMarkShape.noTickMark,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions > 0 ? divisions : null,
              onChanged: max > min ? onChanged : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${formatFcfa(min)} FCFA', style: labelStyle),
              Text('${formatFcfa(mid)} FCFA', style: labelStyle),
              Text('${formatFcfa(max)} FCFA', style: labelStyle),
            ],
          ),
        ),
      ],
    );
  }
}

/// ─────────────────────────────────────────────
/// BOUTON PRINCIPAL
/// ─────────────────────────────────────────────
class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: RideSheetColors.primaryButton,
          foregroundColor: RideSheetColors.primaryButtonText,
          disabledBackgroundColor: RideSheetColors.priceBox,
          shape: const StadiumBorder(),
          elevation: 6,
          shadowColor: RideColors.orange.withValues(alpha: 0.4),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
              )
            : Text(
                label,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}
