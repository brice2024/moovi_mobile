import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'ride_style.dart';

enum VehicleKind { voiture, moto }

/// Déduit le type de véhicule d'un document chauffeur.
///
/// Ordre de lecture : `vehicleType` / `rideType` / `type` (« moto » ou
/// « voiture »), puis la présence d'une fiche `moto` sans `car`
/// (collection `drivers`). Les chauffeurs de test (`test_drivers`) n'ont
/// aucun de ces champs : on répartit alors de façon stable (1 sur 3 = moto)
/// à partir de l'identifiant, pour que la carte montre les deux types.
VehicleKind vehicleKindFromData(String id, Map<String, dynamic> data) {
  for (final key in const ['vehicleType', 'rideType', 'type']) {
    final v = data[key]?.toString().toLowerCase();
    if (v == null) continue;
    if (v.contains('moto')) return VehicleKind.moto;
    if (v.contains('voiture') || v.contains('car') || v.contains('confort')) {
      return VehicleKind.voiture;
    }
  }
  if (data['moto'] != null && data['car'] == null) return VehicleKind.moto;
  if (data['car'] != null) return VehicleKind.voiture;

  final digits = RegExp(r'\d+').allMatches(id).map((m) => m.group(0)).join();
  final n = int.tryParse(digits) ?? id.codeUnits.fold<int>(0, (a, b) => a + b);
  return n % 3 == 0 ? VehicleKind.moto : VehicleKind.voiture;
}

/// Icônes des véhicules sur la carte (voiture vue de dessus, moto orange).
class VehicleMarkerIcons {
  VehicleMarkerIcons._();

  static BitmapDescriptor car = BitmapDescriptor.defaultMarkerWithHue(
    BitmapDescriptor.hueOrange,
  );
  static BitmapDescriptor moto = BitmapDescriptor.defaultMarkerWithHue(
    BitmapDescriptor.hueOrange,
  );
  static BitmapDescriptor pickup = BitmapDescriptor.defaultMarkerWithHue(
    BitmapDescriptor.hueOrange,
  );
  static BitmapDescriptor destination = BitmapDescriptor.defaultMarker;

  static bool _loaded = false;

  static BitmapDescriptor forKind(VehicleKind kind) =>
      kind == VehicleKind.moto ? moto : car;

  /// Charge les icônes une seule fois pour toute l'app.
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      car = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(30, 30)),
        'assets/icon/car4.png',
        width: 30,
        height: 30,
      );
      moto = await _glyphMarker(Icons.two_wheeler_rounded, RideColors.orange);
      pickup = await _dotMarker(RideColors.orange, Colors.white);
      destination = await _dotMarker(Colors.white, RideColors.brown);
    } catch (e) {
      _loaded = false;
      debugPrint('Icônes véhicules indisponibles : $e');
    }
  }

  /// Pastille orange avec un pictogramme blanc, dessinée en mémoire.
  static Future<BitmapDescriptor> _glyphMarker(IconData icon, Color color) async {
    const logical = 30.0;
    const scale = 3.0;
    const size = logical * scale;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2 - 5,
      Paint()..color = color,
    );

    final painter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size * 0.58,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    painter.paint(
      canvas,
      Offset((size - painter.width) / 2, (size - painter.height) / 2),
    );

    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      width: logical,
      height: logical,
    );
  }

  /// Rond plein entouré d'un anneau (départ / destination).
  static Future<BitmapDescriptor> _dotMarker(Color fill, Color ring) async {
    const logical = 22.0;
    const scale = 3.0;
    const size = logical * scale;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2,
      Paint()..color = ring,
    );
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2 - 12,
      Paint()..color = fill,
    );
    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      width: logical,
      height: logical,
    );
  }
}
