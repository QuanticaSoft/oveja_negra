import 'package:flutter/material.dart';

import '../network/api_exception.dart';

/// Mensaje legible para un error capturado en una pantalla.
String messageFor(Object error) =>
    error is ApiException ? error.message : 'Ocurrió un error inesperado. Intenta de nuevo.';

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(Icons.error_outline, color: scheme.error),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: TextStyle(color: scheme.error))),
      ]),
    );
  }
}
