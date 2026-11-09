import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/quantity.dart';

/// Cantidad con hasta 3 decimales en la unidad del insumo. Acepta coma o punto.
class QuantityField extends StatelessWidget {
  const QuantityField({super.key, required this.controller, required this.label, this.unit, this.onChanged, this.helperText});

  final TextEditingController controller;
  final String label;
  final String? unit;
  final ValueChanged<int?>? onChanged;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(labelText: label, suffixText: unit, helperText: helperText),
      onChanged: (text) => onChanged?.call(Quantity.parseInput(text)),
      validator: (text) {
        final milli = Quantity.parseInput(text ?? '');
        if (milli == null) {
          return 'Cantidad con hasta 3 decimales.';
        }
        return milli == 0 ? 'Debe ser mayor que 0.' : null;
      },
    );
  }
}
