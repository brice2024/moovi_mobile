import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

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
    DriverLevel lvl = DriverLevel.or;
    final lvlStr = data['level']?.toString().toLowerCase();
    if (lvlStr == 'diamant') lvl = DriverLevel.diamant;
    if (lvlStr == 'platine') lvl = DriverLevel.platine;

    return DriverOffer(
      id: id,
      name: data['driverName']?.toString() ?? 'Chauffeur',
      rating: (data['rating'] as num?)?.toDouble() ?? 4.8,
      level: lvl,
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
// Bottom sheet
// -----------------------------------------------------------------------------

/// À placer dans un Stack au-dessus de la carte :
///
/// ```dart
/// Stack(children: [
///   GoogleMap(...),
///   DriverOffersSheet(offers: offers, onSelect: (o) {}, onBack: () {}),
/// ])
/// ```
class DriverOffersSheet extends StatefulWidget {
  const DriverOffersSheet({
    super.key,
    required this.offers,
    required this.onSelect,
    this.onBack,
  });

  final List<DriverOffer> offers;
  final ValueChanged<DriverOffer> onSelect;
  final VoidCallback? onBack;

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

  @override
  Widget build(BuildContext context) {
    final offers = _sorted;

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.48,
      maxChildSize: 0.75,
      builder: (context, scrollController) {
        return Stack(
          children: [
            // Fond blanc arrondi (décalé pour laisser dépasser le bouton retour)
            Positioned.fill(
              top: 22,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverToBoxAdapter(child: _buildChips()),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      sliver: SliverList.separated(
                        itemCount: offers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (_, i) => _OfferCard(
                          offer: offers[i],
                          recommended: i == 0,
                          onSelect: () => widget.onSelect(offers[i]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Bouton retour
            Positioned(
              top: 0,
              left: 20,
              child: _BackButton(onTap: widget.onBack),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChips() {
    return Padding(
      padding: const EdgeInsets.only(top: 30, bottom: 18),
      child: SizedBox(
        height: 30,
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
}

// -----------------------------------------------------------------------------
// Widgets
// -----------------------------------------------------------------------------

class _BackButton extends StatelessWidget {
  const _BackButton({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: AppColors.primary.withOpacity(0.5),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap ?? () => Navigator.maybePop(context),
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

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
        padding: const EdgeInsets.symmetric(horizontal: 22),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.cream.withOpacity(0.6),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(
          label,
          style: TextStyle(
            //fontSize: 15,
            //fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.darkBrown,
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
  });

  final DriverOffer offer;
  final bool recommended;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: recommended ? AppColors.darkBlue : AppColors.darkBlue.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: recommended
            ? Border.all(color: AppColors.white, width: 1)
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(offer: offer),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              children: [
                // Ligne 1 : nom / note  —  prix / arrivée
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
                              color: AppColors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded,
                                  size: 16, color: Color(0xFFFFB800)),
                              const SizedBox(width: 3),
                              Text(
                                offer.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  offer.level.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${offer.price}',
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const TextSpan(
                                text: ' FCFA',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          style: const TextStyle(color: AppColors.white),
                        ),
                        Text(
                          'Arrivée: ${offer.arrivalMinutes} min',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Ligne 2 : voiture  —  bouton
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(Icons.directions_car_outlined,
                        size: 18, color: AppColors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${offer.car} •\n${offer.plate}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.25,
                          fontWeight: FontWeight.w400,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ChooseButton(filled: recommended, onPressed: onSelect),
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
            left: 22,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'RECOMMANDÉ',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.offer});
  final DriverOffer offer;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 80,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: offer.photoUrl != null
                  ? Image.network(
                offer.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _AvatarPlaceholder(),
              )
                  : const _AvatarPlaceholder(),
            ),
          ),
          Positioned(
            left: 45,
            top: 45,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: offer.level.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(offer.level.icon, size: 15, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.cream,
      child: const Icon(Icons.person_rounded, size: 30, color: AppColors.primary),
    );
  }
}

class _ChooseButton extends StatelessWidget {
  const _ChooseButton({required this.filled, required this.onPressed});

  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    //const shape = StadiumBorder();
    const size = Size(80, 30);
    const textStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);

    if (filled) {
      return InkWell(
        onTap: onPressed,
        child: Container(
          height: 30,
          padding: EdgeInsets.symmetric(horizontal: 25),
          decoration: BoxDecoration(
            color: AppColors.primary,
                borderRadius: BorderRadius.circular(14)
          ),
          child: Center(child: Text("Accepter", style: TextStyle(color: Colors.white),)),
        ),
      );
    }

    return InkWell(
      onTap: onPressed,
      child: Container(
        height: 30,
        padding: EdgeInsets.symmetric(horizontal: 25),
        decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14)
        ),
        child: Center(child: Text("Accepter", style: TextStyle(color: Colors.white),)),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Données de démo (à retirer)
// -----------------------------------------------------------------------------

const demoOffers = [
  DriverOffer(
    id: '1',
    name: 'Ahmed B.',
    rating: 4.9,
    level: DriverLevel.diamant,
    price: 30,
    arrivalMinutes: 10,
    car: 'Dacia Logan',
    plate: '12345-A-6',
  ),
  DriverOffer(
    id: '2',
    name: 'Yassine K.',
    rating: 4.7,
    level: DriverLevel.or,
    price: 20,
    arrivalMinutes: 15,
    car: 'Renault Clio',
    plate: '67890-B-2',
  ),
  DriverOffer(
    id: '3',
    name: 'Omar LAMINE Targa.',
    rating: 4.8,
    level: DriverLevel.platine,
    price: 18,
    arrivalMinutes: 27,
    car: 'Peugeot 208',
    plate: '24680-D-1',
  ),
  DriverOffer(
    id: '3',
    name: 'Omar LAMINE Targa.',
    rating: 4.8,
    level: DriverLevel.platine,
    price: 18,
    arrivalMinutes: 27,
    car: 'Peugeot 208',
    plate: '24680-D-1',
  ),  DriverOffer(
    id: '3',
    name: 'Omar LAMINE Targa.',
    rating: 4.8,
    level: DriverLevel.platine,
    price: 18,
    arrivalMinutes: 27,
    car: 'Peugeot 208',
    plate: '24680-D-1',
  ),
  DriverOffer(
    id: '3',
    name: 'Omar LAMINE Targa.',
    rating: 4.8,
    level: DriverLevel.platine,
    price: 8,
    arrivalMinutes: 27,
    car: 'Peugeot 208',
    plate: '24680-D-1',
  ),

];