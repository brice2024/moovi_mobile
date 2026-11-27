import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Appel téléphonique et ouverture de liens externes (WhatsApp, e-mail).
class ContactService {
  ContactService._();

  /// Ouvre le composeur du téléphone. Affiche un message si impossible.
  static Future<void> call(BuildContext context, String? phone) async {
    final number = phone?.replaceAll(RegExp(r'[^0-9+]'), '') ?? '';
    final messenger = ScaffoldMessenger.of(context);
    if (number.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Numéro de téléphone indisponible')));
      return;
    }
    final ok = await launchUrl(Uri(scheme: 'tel', path: number));
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text('Appeler le $number')));
    }
  }

  /// Ouvre un lien dans l'application adaptée (navigateur, WhatsApp, e-mail).
  static Future<void> open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text('Impossible d\'ouvrir $url')));
    }
  }

  /// Temps d'arrivée estimé (minutes) en ville : ~25 km/h, détour compris.
  static int etaMinutes(double fromLat, double fromLng, double toLat, double toLng) {
    const r = 6371.0;
    final dLat = (toLat - fromLat) * math.pi / 180;
    final dLng = (toLng - fromLng) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(fromLat * math.pi / 180) *
            math.cos(toLat * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final km = 2 * r * math.asin(math.sqrt(a)) * 1.3;
    return math.max(1, (km / 25 * 60).round());
  }
}
