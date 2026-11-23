import 'package:flutter/material.dart';

import 'ride_style.dart';

/// En-tête des cartes « Destination » (maquettes 11 et 12) :
/// filets orange, retour à gauche, titre centré, épingle à droite.
class DestinationHeader extends StatelessWidget {
  const DestinationHeader({
    super.key,
    this.title = 'Destination',
    this.onBack,
  });

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(height: 1, thickness: 1.5, color: RideColors.orange),
        SizedBox(
          height: 46,
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.black),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(
                width: 40,
                child: Icon(Icons.location_on, color: RideColors.brownMid, size: 24),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1.5, color: RideColors.orange),
      ],
    );
  }
}

/// Carte « ITINÉRAIRE » (maquettes 12 à 15).
class ItineraryCard extends StatelessWidget {
  const ItineraryCard({
    super.key,
    required this.from,
    required this.to,
    required this.minutesText,
    required this.distanceText,
    this.progress,
    this.indeterminate = false,
  });

  final String from;
  final String to;
  final String minutesText;
  final String distanceText;

  /// Avancement de 0 à 1 (barre masquée si null, sauf [indeterminate]).
  final double? progress;

  /// Barre animée (recherche en cours).
  final bool indeterminate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ITINÉRAIRE',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w500,
                        color: RideColors.brownLabel,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(child: _place(shortAddress(from))),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.arrow_forward_rounded,
                              size: 16, color: RideColors.brown),
                        ),
                        Flexible(child: _place(shortAddress(to))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    minutesText,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: RideColors.brownMid,
                    ),
                  ),
                  if (distanceText.isNotEmpty)
                    Text(
                      distanceText,
                      style: const TextStyle(fontSize: 11.5, color: RideColors.brownLabel),
                    ),
                ],
              ),
            ],
          ),
          if (progress != null || indeterminate) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: indeterminate ? null : progress!.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: RideColors.cream,
                valueColor: const AlwaysStoppedAnimation(RideColors.orange),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _place(String text) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: RideColors.brown,
        ),
      );
}

/// Photo du chauffeur avec le badge de niveau en bas à droite.
class DriverPhoto extends StatelessWidget {
  const DriverPhoto({
    super.key,
    required this.photoUrl,
    required this.badgeColor,
    required this.badgeIcon,
    this.size = 66,
  });

  final String? photoUrl;
  final Color badgeColor;
  final IconData badgeIcon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: RideColors.cream,
      child: Icon(Icons.person_rounded, size: size * 0.45, color: RideColors.orange),
    );
    return SizedBox(
      width: size + 8,
      height: size + 8,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.28),
              border: Border.all(color: RideColors.cream, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.25),
              child: photoUrl != null && photoUrl!.isNotEmpty
                  ? Image.network(
                      photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => placeholder,
                    )
                  : placeholder,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(badgeIcon, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
