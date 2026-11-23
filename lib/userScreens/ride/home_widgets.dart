import 'package:flutter/material.dart';

import 'ride_style.dart';

/// Pilule « Où allez-vous ? » + puce « Maintenant » + bouton profil (maquette 9).
class HomeSearchBar extends StatelessWidget {
  const HomeSearchBar({
    super.key,
    required this.onSearchTap,
    required this.onScheduleTap,
    required this.scheduleLabel,
    this.onProfileTap,
  });

  final VoidCallback onSearchTap;
  final VoidCallback onScheduleTap;
  final String scheduleLabel;
  final VoidCallback? onProfileTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Material(
            color: RideColors.orange,
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(26),
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: onSearchTap,
              child: SizedBox(
                height: 54,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    const Icon(Icons.near_me_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Où allez-vous ?',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: Material(
                        color: const Color(0xFFEDEDED),
                        borderRadius: BorderRadius.circular(22),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: onScheduleTap,
                          child: Container(
                            height: 44,
                            constraints: const BoxConstraints(maxWidth: 170),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.access_time_filled_rounded,
                                    color: RideColors.orange, size: 18),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    scheduleLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: RideColors.orange,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(Icons.keyboard_arrow_down_rounded,
                                    color: RideColors.orange, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: RideColors.orange,
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onProfileTap,
            child: const SizedBox(
              width: 50,
              height: 50,
              child: Icon(Icons.person_outline_rounded, color: Colors.white, size: 28),
            ),
          ),
        ),
      ],
    );
  }
}

/// Mode « choisir un point sur la carte » : viseur central + confirmation.
class MapPickOverlay extends StatelessWidget {
  const MapPickOverlay({
    super.key,
    required this.title,
    required this.addressLabel,
    required this.loading,
    required this.onConfirm,
    required this.onCancel,
    this.bottomInset = 0,
  });

  final String title;
  final String addressLabel;
  final bool loading;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Stack(
      children: [
        // Viseur : la pointe de l'épingle est au centre exact de la carte.
        IgnorePointer(
          child: Center(
            child: Transform.translate(
              offset: const Offset(0, -22),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on, size: 46, color: RideColors.orange),
                ],
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: RideColors.orange, width: 2),
              ),
            ),
          ),
        ),
        Positioned(
          top: top + 12,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.white,
            elevation: 6,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onCancel,
                    icon: const Icon(Icons.arrow_back_rounded, color: RideColors.brown),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: RideColors.brownLabel,
                          ),
                        ),
                        const SizedBox(height: 2),
                        loading
                            ? const Text(
                                'Recherche de l\'adresse…',
                                style: TextStyle(fontSize: 14, color: Colors.grey),
                              )
                            : Text(
                                addressLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: RideColors.brown,
                                ),
                              ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: bottomInset + 16,
          child: SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: loading ? null : onConfirm,
              icon: const Icon(Icons.check_rounded),
              label: const Text(
                'Confirmer ce point',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: RideColors.orange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: RideColors.priceBox,
                disabledForegroundColor: Colors.white,
                shape: const StadiumBorder(),
                elevation: 4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
