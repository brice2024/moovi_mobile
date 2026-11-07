import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'driver_theme.dart';
import 'ride_offer.dart';

class NegotiatePriceSheet extends StatefulWidget {
  final RideOffer offer;

  const NegotiatePriceSheet({
    super.key,
    required this.offer,
  });

  @override
  State<NegotiatePriceSheet> createState() => _NegotiatePriceSheetState();
}

class _NegotiatePriceSheetState extends State<NegotiatePriceSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: '${widget.offer.price}',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add(int v) {
    final cur = int.tryParse(_ctrl.text) ?? widget.offer.price;
    final newPrice = cur + v;

    _ctrl.value = TextEditingValue(
      text: '$newPrice',
      selection: TextSelection.collapsed(
        offset: '$newPrice'.length,
      ),
    );
  }

  void _submitPrice() {
    final price = int.tryParse(_ctrl.text);

    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez entrer un prix valide en FCFA'),
        ),
      );
      return;
    }

    Navigator.pop(context, price);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(22),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // EN-TÊTE
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.arrow_back,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Négocier le prix de la course',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IdTag(widget.offer.id.substring(0, widget.offer.id.length.clamp(0, 6))),
                ],
              ),

              const SizedBox(height: 14),

              // OFFRE CLIENT ET ESTIMATION MOOVI
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'OFFRE CLIENT',
                        style: TextStyle(
                          fontSize: 10,
                          color: MooviColors.orange,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.offer.price} FCFA',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'ESTIMATION MOOVI',
                        style: TextStyle(
                          fontSize: 10,
                          color: MooviColors.grey,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: MooviColors.orangeSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${widget.offer.mooviPrice} FCFA',
                          style: const TextStyle(
                            fontSize: 11,
                            color: MooviColors.orange,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // CHAMP DE SAISIE DU PRIX
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: MooviColors.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Text(
                      'FCFA',
                      style: TextStyle(
                        fontSize: 16,
                        color: MooviColors.orange,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          TextField(
                            controller: _ctrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const Text(
                            'VOTRE CONTRE-PROPOSITION',
                            style: TextStyle(
                              fontSize: 9,
                              color: MooviColors.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 32),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // BOUTONS D'AUGMENTATION RAPIDE EN FCFA (+500, +1000, +2000)
              Row(
                children: [
                  for (final v in [500, 1000, 2000]) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _add(v),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: MooviColors.orangeSoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '+$v F',
                            style: const TextStyle(
                              fontSize: 12,
                              color: MooviColors.orange,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (v != 2000) const SizedBox(width: 8),
                  ],
                ],
              ),

              const SizedBox(height: 16),

              // ENVOYER LA PROPOSITION
              OrangeButton(
                label: 'Envoyer la contre-proposition',
                icon: Icons.send_rounded,
                onPressed: _submitPrice,
              ),

              const SizedBox(height: 8),

              // ANNULER
              OutlineBtn(
                label: 'Annuler',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
