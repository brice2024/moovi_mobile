import 'package:flutter/material.dart';

/// Couleurs du parcours « course client » (maquettes 9 à 16).
class RideColors {
  RideColors._();

  /// Orange vif de la pilule « Où allez-vous ? » et des boutons.
  static const Color orange = Color(0xFFFF8A00);

  /// Brun foncé des titres et des montants.
  static const Color brown = Color(0xFF452800);

  /// Brun moyen (boutons « Choisir », badge « RECOMMANDÉ »).
  static const Color brownMid = Color(0xFF8C4A00);

  /// Brun des petits libellés (PICKUP, DISTANCE…).
  static const Color brownLabel = Color(0xFF9A6A3A);

  /// Crème des cartes.
  static const Color cream = Color(0xFFFFE9D6);
  static const Color creamLight = Color(0xFFFFF4EA);

  /// Orange pâle du grand prix (maquette 11).
  static const Color priceBox = Color(0xFFF7B96B);

  /// Bouton sombre des maquettes 13-16.
  static const Color dark = Color(0xFF0E1824);

  /// Bandeau « chauffeur en route » (maquettes 13-15).
  static const Color bannerBg = Color(0xFFFFF6D9);
  static const Color bannerText = Color(0xFFE0A100);

  static const Color star = Color(0xFFFFB800);
  static const Color success = Color(0xFF2E9E4F);
}

/// Style sombre de la carte (maquettes 9 à 15).
const String kMooviDarkMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#242120"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#8F8A86"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#1E1B1A"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"featureType": "administrative", "elementType": "geometry", "stylers": [{"color": "#3A3533"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#B5AFAA"}]},
  {"featureType": "landscape.man_made", "elementType": "geometry", "stylers": [{"color": "#2B2726"}]},
  {"featureType": "poi", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"visibility": "on"}, {"color": "#262B24"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#3A3634"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#2A2625"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#8A8480"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#4A4442"}]},
  {"featureType": "road.arterial", "elementType": "geometry", "stylers": [{"color": "#423D3B"}]},
  {"featureType": "transit", "stylers": [{"visibility": "off"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#17191C"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#4E5356"}]}
]
''';

const _frDays = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _frDaysShort = ['Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.', 'Dim.'];
const _frMonthsShort = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

String _two(int v) => v.toString().padLeft(2, '0');

/// « 08:30 »
String formatHour(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// « 24/11 à 08:30 »
String formatDayMonthHour(DateTime d) =>
    '${_two(d.day)}/${_two(d.month)} à ${formatHour(d)}';

/// Libellé court d'un jour : « Aujourd'hui », « Demain », « Mer. 26 nov. ».
String formatDayLabel(DateTime d, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(d);
  final diff = day.difference(today).inDays;
  if (diff == 0) return "Aujourd'hui";
  if (diff == 1) return 'Demain';
  return '${_frDaysShort[d.weekday - 1]} ${d.day} ${_frMonthsShort[d.month - 1]}';
}

/// Libellé de la puce de planification : « Demain 08:30 ».
String formatScheduleChip(DateTime d) => '${formatDayLabel(d)} ${formatHour(d)}';

/// Libellé long : « mercredi 26 nov. à 08:30 ».
String formatScheduleLong(DateTime d) =>
    '${_frDays[d.weekday - 1]} ${d.day} ${_frMonthsShort[d.month - 1]} à ${formatHour(d)}';

/// « 12 500 » (séparateur de milliers).
String formatFcfa(num value) {
  final s = value.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Partie courte d'une adresse (avant la première virgule).
String shortAddress(String address) {
  final first = address.split(',').first.trim();
  return first.isEmpty ? address : first;
}
