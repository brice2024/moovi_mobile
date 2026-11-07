import 'package:flutter/material.dart';

class MooviColors {
  static const orange = Color(0xFFFF7A00);
  static const orangeSoft = Color(0xFFFFF1E4);
  static const dark = Color(0xFF1B1B1F);
  static const grey = Color(0xFF8C8C94);
  static const border = Color(0xFFEAEAEE);
  static const bg = Color(0xFFF6F6F8);
  static const green = Color(0xFF22B573);
}

/// Pastille "EN LIGNE"
class OnlineChip extends StatelessWidget {
  final bool online;
  const OnlineChip({super.key, this.online = true});

  @override
  Widget build(BuildContext context) {
    final c = online ? MooviColors.green : MooviColors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.08), blurRadius: 8)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle, size: 14, color: c),
        const SizedBox(width: 6),
        Text(online ? 'EN LIGNE' : 'HORS LIGNE',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class RoundOrangeButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const RoundOrangeButton({super.key, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(color: MooviColors.orange, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      );
}

class OrangeButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  const OrangeButton({super.key, required this.label, this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: MooviColors.orange,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
        ),
      );
}

class OutlineBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const OutlineBtn({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 46,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: MooviColors.dark,
            side: const BorderSide(color: MooviColors.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      );
}

/// Pastille "ID: 4892A"
class IdTag extends StatelessWidget {
  final String id;
  const IdTag(this.id, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: MooviColors.bg, borderRadius: BorderRadius.circular(8)),
        child: Text('ID: $id',
            style: const TextStyle(fontSize: 10, color: MooviColors.grey, fontWeight: FontWeight.w600)),
      );
}

/// Départ (point orange) / Destination (point noir)
class RouteLine extends StatelessWidget {
  final String from, to;
  const RouteLine({super.key, required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    Widget row(Color dot, String label, String value) => Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(),
                  style: const TextStyle(fontSize: 8, color: MooviColors.grey, fontWeight: FontWeight.w600)),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]);
    return Column(children: [
      row(MooviColors.orange, 'Départ', from),
      const SizedBox(height: 10),
      row(MooviColors.dark, 'Destination', to),
    ]);
  }
}
