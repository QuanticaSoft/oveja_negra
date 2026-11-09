import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_error_text.dart';

/// Carga, error (con reintento) o datos de un [AsyncValue], igual en todas las pantallas.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.onRetry, required this.builder});

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) {
      return builder(value.requireValue);
    }
    if (value.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ErrorBanner(messageFor(value.error!)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
          ]),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}
