import 'package:cloud_firestore/cloud_firestore.dart';

/// Petits utilitaires de mise en forme (FCFA, dates) sans dépendance à intl.

/// 12500 -> "12 500 FCFA".
String formatFcfa(num amount, {bool withSign = false}) {
  final value = amount.round();
  final digits = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  final sign = value < 0 ? '-' : (withSign && value > 0 ? '+' : '');
  return '$sign$buf FCFA';
}

/// Version compacte pour les axes de graphique : 12500 -> "12,5k".
String formatCompact(num value) {
  if (value.abs() >= 1000000) {
    return '${_trim(value / 1000000)}M';
  }
  if (value.abs() >= 1000) return '${_trim(value / 1000)}k';
  return value.round().toString();
}

String _trim(num v) {
  final s = v.toStringAsFixed(1);
  return (s.endsWith('.0') ? s.substring(0, s.length - 2) : s).replaceAll('.', ',');
}

const _monthsShort = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

DateTime? asDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "AUJOURD'HUI, 14:30" / "HIER, 09:05" / "12 NOV., 14:30".
String formatRelativeDate(DateTime? date, {bool upper = true}) {
  if (date == null) return upper ? 'À L\'INSTANT' : "À l'instant";
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = today.difference(day).inDays;
  String label;
  if (diff == 0) {
    label = "Aujourd'hui";
  } else if (diff == 1) {
    label = 'Hier';
  } else {
    label = '${date.day} ${_monthsShort[date.month - 1]}';
    if (date.year != now.year) label += ' ${date.year}';
  }
  final text = '$label, ${_hm(date)}';
  return upper ? text.toUpperCase() : text;
}
