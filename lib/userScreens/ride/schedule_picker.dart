import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'ride_style.dart';

/// Résultat du sélecteur : [at] == null signifie « Maintenant ».
class ScheduleChoice {
  const ScheduleChoice(this.at);
  final DateTime? at;
}

/// Délai minimum entre maintenant et une course planifiée.
const kScheduleMinDelay = Duration(minutes: 15);

/// Horizon maximum de planification.
const kScheduleMaxDelay = Duration(days: 7);

/// Ouvre le choix du jour et de l'heure (libellés en français, sans
/// dépendre des localisations Material). Renvoie null si l'utilisateur ferme.
Future<ScheduleChoice?> showSchedulePicker(
  BuildContext context, {
  DateTime? initial,
}) {
  return showModalBottomSheet<ScheduleChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SchedulePickerSheet(initial: initial),
  );
}

class _SchedulePickerSheet extends StatefulWidget {
  const _SchedulePickerSheet({this.initial});
  final DateTime? initial;

  @override
  State<_SchedulePickerSheet> createState() => _SchedulePickerSheetState();
}

class _SchedulePickerSheetState extends State<_SchedulePickerSheet> {
  static const _minuteStep = 5;

  late final DateTime _min;
  late final DateTime _max;
  late final List<DateTime> _days;
  late DateTime _day;
  late int _hour;
  late int _minute;
  late final FixedExtentScrollController _hourCtrl;
  late final FixedExtentScrollController _minuteCtrl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _min = now.add(kScheduleMinDelay);
    _max = now.add(kScheduleMaxDelay);

    final today = DateUtils.dateOnly(now);
    _days = [
      for (var i = 0; i <= 7; i++) today.add(Duration(days: i)),
    ].where((d) {
      final end = d.add(const Duration(days: 1));
      return end.isAfter(_min) && !d.isAfter(_max);
    }).toList();

    var start = widget.initial;
    if (start == null || start.isBefore(_min) || start.isAfter(_max)) {
      // Prochain créneau de 5 min après le minimum.
      final extra = (_minuteStep - _min.minute % _minuteStep) % _minuteStep;
      start = DateTime(_min.year, _min.month, _min.day, _min.hour, _min.minute + extra);
    }
    _day = DateUtils.dateOnly(start);
    if (!_days.contains(_day)) _day = _days.first;
    _hour = start.hour;
    _minute = (start.minute ~/ _minuteStep) * _minuteStep;
    _hourCtrl = FixedExtentScrollController(initialItem: _hour);
    _minuteCtrl = FixedExtentScrollController(initialItem: _minute ~/ _minuteStep);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  DateTime get _candidate =>
      DateTime(_day.year, _day.month, _day.day, _hour, _minute);

  bool get _isValid =>
      !_candidate.isBefore(_min) && !_candidate.isAfter(_max);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final valid = _isValid;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Planifier la course',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: RideColors.brown,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Au moins 15 min à l\'avance, jusqu\'à 7 jours.',
            style: TextStyle(fontSize: 12.5, color: RideColors.brownLabel),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final d = _days[i];
                final selected = d == _day;
                return GestureDetector(
                  onTap: () => setState(() => _day = d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? RideColors.orange : RideColors.cream,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      formatDayLabel(d),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : RideColors.brown,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: Row(
              children: [
                Expanded(
                  child: CupertinoPicker(
                    scrollController: _hourCtrl,
                    itemExtent: 40,
                    selectionOverlay: const _PickerOverlay(),
                    onSelectedItemChanged: (i) => setState(() => _hour = i),
                    children: [
                      for (var h = 0; h < 24; h++)
                        Center(child: Text(h.toString().padLeft(2, '0'), style: _wheelStyle)),
                    ],
                  ),
                ),
                const Text(':', style: _wheelStyle),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: _minuteCtrl,
                    itemExtent: 40,
                    selectionOverlay: const _PickerOverlay(),
                    onSelectedItemChanged: (i) =>
                        setState(() => _minute = i * _minuteStep),
                    children: [
                      for (var m = 0; m < 60; m += _minuteStep)
                        Center(child: Text(m.toString().padLeft(2, '0'), style: _wheelStyle)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            valid
                ? 'Prise en charge : ${formatScheduleLong(_candidate)}'
                : _candidate.isBefore(_min)
                    ? 'Choisissez une heure au moins 15 min après maintenant.'
                    : 'Une course se planifie au maximum 7 jours à l\'avance.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valid ? RideColors.brown : Colors.red.shade700,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, const ScheduleChoice(null)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: RideColors.brownMid,
                    side: const BorderSide(color: RideColors.brownMid),
                    minimumSize: const Size.fromHeight(50),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Maintenant',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: valid
                      ? () => Navigator.pop(context, ScheduleChoice(_candidate))
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: RideColors.orange,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: RideColors.cream,
                    minimumSize: const Size.fromHeight(50),
                    shape: const StadiumBorder(),
                    elevation: 0,
                  ),
                  child: const Text('Confirmer',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _wheelStyle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: RideColors.brown,
  );
}

class _PickerOverlay extends StatelessWidget {
  const _PickerOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: RideColors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
