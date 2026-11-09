import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell.dart';
import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import 'session_controller.dart';

/// Mientras se restaura la sesión guardada. Si no hay red, lo dice y permite reintentar.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final error = session.error;
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(fontSize: 32),
              const SizedBox(height: 32),
              if (error == null)
                const CircularProgressIndicator(color: AppColors.orange)
              else ...[
                Text(
                  error is ApiException ? error.message : 'No se pudo iniciar la sesión.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.white),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 220,
                  child: FilledButton(
                    onPressed: () => ref.invalidate(sessionControllerProvider),
                    child: const Text('Reintentar'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
