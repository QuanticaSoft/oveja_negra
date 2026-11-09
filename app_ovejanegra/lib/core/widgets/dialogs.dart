import 'package:flutter/material.dart';

/// Pide un motivo obligatorio (cancelaciones y anulaciones). Devuelve null si se cancela.
Future<String?> askReason(BuildContext context, {required String title, required String action}) {
  final controller = TextEditingController();
  final form = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Form(
        key: form,
        child: TextFormField(
          key: const Key('reason.field'),
          controller: controller,
          autofocus: true,
          maxLength: 300,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Motivo'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'El motivo es obligatorio.' : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
        FilledButton(
          key: const Key('reason.confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: Text(action),
        ),
      ],
    ),
  );
}

void showMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
