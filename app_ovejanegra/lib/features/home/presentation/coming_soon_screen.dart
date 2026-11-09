import 'package:flutter/material.dart';

import '../../../app/destinations.dart';
import '../../../app/theme.dart';

/// Lugar de las secciones que llegan en las siguientes partes de la Fase 8.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.destination});

  final Destination destination;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(destination.icon, size: 56, color: AppColors.orange),
            const SizedBox(height: 16),
            Text(destination.label, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Disponible en la parte ${destination.part} de la Fase 8.',
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.grey)),
          ],
        ),
      ),
    );
  }
}
