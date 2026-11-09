import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/quantity.dart';
import '../domain/inventory.dart';
import 'inventory_providers.dart';

class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.movement, this.showIngredient = false});

  final Movement movement;
  final bool showIngredient;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final positive = m.quantityMilli > 0;
    final sign = positive ? '+' : '';
    return ListTile(
      leading: Icon(
        switch (m.type) {
          MovementType.entradaCompra => Icons.shopping_cart_outlined,
          MovementType.salidaConsumo => Icons.restaurant_outlined,
          MovementType.ajuste => Icons.tune,
          MovementType.reverso => Icons.undo,
        },
        color: positive ? Colors.green.shade700 : Theme.of(context).colorScheme.error,
      ),
      title: Text('${showIngredient ? '${m.ingredientName} · ' : ''}${m.type.label} $sign${Quantity.format(m.quantityMilli, m.unit)}'),
      subtitle: Text([
        'Queda ${Quantity.format(m.stockAfterMilli, m.unit)}',
        LaPaz.dateTime(m.createdAt),
        m.createdBy,
        if (m.reason != null) m.reason!,
      ].join(' · ')),
    );
  }
}

/// Elige un insumo activo con búsqueda. Devuelve null si se cierra.
Future<Ingredient?> pickIngredient(BuildContext context, {Set<int> exclude = const {}}) => showDialog<Ingredient>(
      context: context,
      builder: (_) => _IngredientPicker(exclude: exclude),
    );

class _IngredientPicker extends ConsumerStatefulWidget {
  const _IngredientPicker({required this.exclude});

  final Set<int> exclude;

  @override
  ConsumerState<_IngredientPicker> createState() => _IngredientPickerState();
}

class _IngredientPickerState extends ConsumerState<_IngredientPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final ingredients = ref.watch(ingredientsProvider((query: '', lowStockOnly: false)));
    return AlertDialog(
      title: const Text('Elegir insumo'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(children: [
          TextField(
            key: const Key('picker.search'),
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar'),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ingredients.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) {
                final visible = [
                  for (final i in list)
                    if (i.isActive && !widget.exclude.contains(i.id) && i.name.toLowerCase().contains(_query)) i,
                ];
                return ListView(children: [
                  for (final i in visible)
                    ListTile(
                      key: Key('picker.${i.id}'),
                      title: Text(i.name),
                      subtitle: Text('${i.categoryName} · stock ${i.stockLabel}'),
                      onTap: () => Navigator.pop(context, i),
                    ),
                ]);
              },
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}

class LowStockBadge extends StatelessWidget {
  const LowStockBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(12)),
        child: const Text('Stock bajo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
      );
}
