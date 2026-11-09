import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/money.dart';

/// Campo de importe en Bs. Acepta coma o punto decimal y entrega centavos.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.onChanged,
    this.allowZero = true,
    this.autofocus = false,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<int?>? onChanged;
  final bool allowZero;
  final bool autofocus;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(labelText: label, prefixText: 'Bs ', errorText: errorText),
      onChanged: (text) => onChanged?.call(Money.parseInput(text)),
      validator: (text) {
        final cents = Money.parseInput(text ?? '');
        if (cents == null) {
          return 'Importe con hasta 2 decimales.';
        }
        if (!allowZero && cents == 0) {
          return 'Debe ser mayor que 0.';
        }
        return null;
      },
    );
  }
}
