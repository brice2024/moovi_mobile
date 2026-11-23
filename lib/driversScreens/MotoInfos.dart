import 'package:flutter/material.dart';

import 'CarInfos.dart';

/// Informations de la moto (enregistrées sous `drivers/{uid}.moto`).
/// Les pièces justificatives sont envoyées sur l'écran « Vérification Chauffeur ».
class Motoinfos extends StatelessWidget {
  const Motoinfos({super.key});

  @override
  Widget build(BuildContext context) {
    return const VehicleInfoForm(
      vehicleKey: 'moto',
      title: 'Votre moto',
      subtitle:
          'Renseignez les informations de votre moto pour commencer à rouler.',
      icon: Icons.two_wheeler_rounded,
      brandHint: 'Ex : Yamaha',
      modelHint: 'Ex : MT-07',
    );
  }
}
