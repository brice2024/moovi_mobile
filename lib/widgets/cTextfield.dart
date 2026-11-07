import 'package:flutter/material.dart';


class Ctextfield extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  const Ctextfield({super.key, required this.controller, required this.hintText});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        hintText: hintText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Colors.grey,
            width: 1,
          ),
        ),
      ),

      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Veuillez entrer votre numéro';
        }

        if (value.length < 8) {
          return 'Numéro de téléphone invalide';
        }

        return null;
      },
    );
  }
}
