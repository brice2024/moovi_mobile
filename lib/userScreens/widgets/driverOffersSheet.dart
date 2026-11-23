import 'package:flutter/material.dart';

import '../ride/ride_cards.dart';
import '../ride/ride_style.dart';

// -----------------------------------------------------------------------------
// Modèles
// -----------------------------------------------------------------------------

enum DriverLevel {
  diamant('Diamant', Color(0xFFFFD60A), Icons.diamond_outlined),
  or('Or', Color(0xFF6B6A1B), Icons.workspace_premium_rounded),
  platine('Platine', Color(0xFF9AA5B1), Icons.military_tech_rounded);

  const DriverLevel(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;

  static DriverLevel fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'diamant':
        return DriverLevel.diamant;
      case 'platine':
        return DriverLevel.platine;
      default:
        return DriverLevel.or;
    }
  }
}

class DriverOffer {
  const DriverOffer({
    required this.id,
    required this.name,
    required this.rating,
    required this.level,
    required this.price,
    required this.arrivalMinutes,
    required this.car,
    required this.plate,
    this.photoUrl,
  });

  final String id;
  final String name;
  final double rating;
  final DriverLevel level;
  final int price; // en FCFA
  final int arrivalMinutes;
  final String car;
  final String plate;
  final String? photoUrl;

  factory DriverOffer.fromMap(String id, Map<String, dynamic> data) {
    return DriverOffer(
      id: id,
      name: data['driverName']?.toString() ?? 'Chauffeur',
      rating: (data['rating'] as num?)?.toDouble() ?? 4.8,
      level: DriverLevel.fromString(data['level']?.toString()),
      price: (data['price'] as num?)?.toInt() ?? 2000,
      arrivalMinutes: (data['arrivalMinutes'] as num?)?.toInt() ?? 5,
      car: data['car']?.toString() ?? 'Véhicule',
      plate: data['plate']?.toString() ?? '',
      photoUrl: data['photoUrl']?.toString(),
    );
  }
}

enum OfferSort { price, rating, fastest }

// -----------------------------------------------------------------------------
// Carte des offres (maquette 12)
// -----------------------------------------------------------------------------

/// Liste des propositions des chauffeurs : en-tête « Destination »,
/// carte ITINÉRAIRE, tri, cartes d'offres avec bouton « Choisir ».
/// À placer dans un Stack au-dessus de la carte ; occupe la place donnée.
class DriverOffersSheet extends StatefulWidget {
  const DriverOffersSheet({
    super.key,
    required this.offers,
    required this.onSelect,
    this.onBack,
    this.from = '',
    this.to = '',
    this.durationText = '',
    this.distanceText = '',
    this.scheduledLabel,
    this.selectingId,
    this.bottomPadding = 24,
  });

  final List<DriverOffer> offers;
  final ValueChanged<DriverOffer> onSelect;
  final VoidCallback? onBack;
  final String from;
  final String to;
  final String durationText;
  final String distanceText;

  /// Ex. « Prévue demain à 08:30 » pour une course planifiée.
  final String? scheduledLabel;

  /// Offre en cours d'acceptation (bouton en chargement, autres désactivés).
  final String? selectingId;

  /// Marge sous la liste (barre d'onglets).
  final double bottomPadding;

  @override
  State<DriverOffersSheet> createState() => _DriverOffersSheetState();
}

class _DriverOffersSheetState extends State<DriverOffersSheet> {
  OfferSort _sort = OfferSort.price;

  static const _chips = {
    OfferSort.price: 'Meilleur prix',
    OfferSort.rating: 'Meilleure note',
    OfferSort.fastest: 'Plus rapide',
  };

  List<DriverOffer> get _sorted {
    final list = [...widget.offers];
    switch (_sort) {
      case OfferSort.price:
        list.sort((a, b) => a.price.compareTo(b.price));
      case OfferSort.rating:
        list.sort((a, b) => b.rating.compareTo(a.rating));
      case OfferSort.fastest:
        list.sort((a, b) => a.arrivalMinutes.compareTo(b.arrivalMinutes));
    }
    return list;
  }

  void _choose(DriverOffer offer) {
    if (widget.selectingId != null) return;
    widget.onSelect(offer);
  }

  @override
  Widget build(BuildContext context) {
    final offers = _sorted;
    final searching = offers.isEmpty;

    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DestinationHeader(onBack: widget.onBack),
                  const SizedBox(height: 14),
                  ItineraryCard(
                    from: widget.from,
                    to: widget.to,
                    minutesText: widget.durationText.isEmpty ? '—' : widget.durationText,
                    distanceText: widget.distanceText,
                    indeterminate: searching,
                    progress: searching ? null : 1,
                  ),
                  if (widget.scheduledLabel != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.event_rounded, size: 18, color: RideColors.brownMid),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.scheduledLabel!,
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
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(child: _buildChips()),
          if (searching)
            SliverToBoxAdapter(child: _buildSearching())
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, widget.bottomPadding),
              sliver: SliverList.separated(
                itemCount: offers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (_, i) => _OfferCard(
                  offer: offers[i],
                  recommended: i == 0,
                  loading: widget.selectingId == offers[i].id,
                  onSelect: () => _choose(offers[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChips() {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            for (final entry in _chips.entries) ...[
              _SortChip(
                label: entry.value,
                selected: _sort == entry.key,
                onTap: () => setState(() => _sort = entry.key),
              ),
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearching() {
    return Padding(
      padding: EdgeInsets.fromLTRB(28, 24, 28, widget.bottomPadding),
      child: const Column(
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 2.6, color: RideColors.orange),
          ),
          SizedBox(height: 14),
          Text(
            'Recherche de chauffeurs à proximité…',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: RideColors.brown,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Les propositions des chauffeurs s\'afficheront ici.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: RideColors.brownLabel),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Widgets
// -----------------------------------------------------------------------------

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? RideColors.orange : RideColors.cream,
          borderRadius: BorderRadius.circular(20),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: RideColors.orange.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: selected ? RideColors.brown : RideColors.brownLabel,
          ),
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.recommended,
    required this.onSelect,
    this.loading = false,
  });

  final DriverOffer offer;
  final bool recommended;
  final bool loading;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      decoration: BoxDecoration(
        color: recommended ? Colors.white : RideColors.cream,
        borderRadius: BorderRadius.circular(22),
        border: recommended
            ? Border.all(color: RideColors.orange, width: 1.5)
            : null,
        boxShadow: recommended
            ? [
                BoxShadow(
                  color: RideColors.orange.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DriverPhoto(
            photoUrl: offer.photoUrl,
            badgeColor: offer.level.color,
            badgeIcon: offer.level.icon,
            size: 64,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            offer.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: RideColors.brown,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded, size: 17, color: RideColors.star),
                              const SizedBox(width: 3),
                              Text(
                                offer.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: RideColors.brown,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  offer.level.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: RideColors.brownLabel,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: formatFcfa(offer.price),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const TextSpan(
                                text: ' FCFA',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          style: const TextStyle(color: RideColors.brown),
                        ),
                        Text(
                          'Arrivée : ${offer.arrivalMinutes} min',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: RideColors.brownMid,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.directions_car_outlined,
                        size: 18, color: RideColors.brown),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        offer.plate.isEmpty
                            ? offer.car
                            : '${offer.car} •\n${offer.plate}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.25,
                          color: RideColors.brown,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ChooseButton(
                      filled: recommended,
                      loading: loading,
                      onPressed: onSelect,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        if (recommended)
          Positioned(
            top: 0,
            left: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF7A3E05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'RECOMMANDÉ',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChooseButton extends StatelessWidget {
  const _ChooseButton({
    required this.filled,
    required this.onPressed,
    this.loading = false,
  });

  final bool filled;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : RideColors.brownMid;
    return Material(
      color: filled ? RideColors.brownMid : Colors.white,
      elevation: filled ? 4 : 0,
      shadowColor: RideColors.brownMid.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: filled
            ? BorderSide.none
            : const BorderSide(color: RideColors.brownMid, width: 1.5),
      ),
      child: InkWell(
        onTap: loading ? null : onPressed,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 40,
          width: 92,
          child: Center(
            child: loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                : Text(
                    'Choisir',
                    style: TextStyle(
                      color: fg,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
