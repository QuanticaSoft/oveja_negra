import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/quantity.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/quantity_field.dart';
import '../../auth/presentation/session_controller.dart';
import '../domain/inventory.dart';
import 'inventory_providers.dart';
import 'inventory_widgets.dart';

/// Datos del insumo, su kardex y las acciones de ajuste, edición y activación.
class IngredientDetailScreen extends ConsumerWidget {
  const IngredientDetailScreen({super.key, required this.ingredientId});

  final int ingredientId;

  Future<void> _adjust(BuildContext context, WidgetRef ref, Ingredient ingredient) async {
    final result = await showDialog<(int, String)>(context: context, builder: (_) => _AdjustDialog(ingredient: ingredient));
    if (result == null) {
      return;
    }
    try {
      await ref.read(inventoryApiProvider).adjust(ingredient.id, result.$1, result.$2);
      refreshInventory(ref);
      if (context.mounted) {
        showMessage(context, 'Ajuste registrado.');
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        showMessage(context, inventoryErrorMessage(e));
      }
    }
  }

  Future<void> _setActive(BuildContext context, WidgetRef ref, Ingredient ingredient, bool active) async {
    try {
      await ref.read(inventoryApiProvider).setActive(ingredient.id, active);
      refreshInventory(ref);
    } on ApiException catch (e) {
      if (context.mounted) {
        showMessage(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).value!;
    final movements = ref.watch(movementsProvider((ingredientId: ingredientId, type: null)));
    return AsyncView(
      value: ref.watch(ingredientProvider(ingredientId)),
      onRetry: () => ref.invalidate(ingredientProvider(ingredientId)),
      builder: (i) => ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: Text(i.name, style: Theme.of(context).textTheme.headlineSmall)),
          if (i.isLowStock) const LowStockBadge(),
        ]),
        Text('${i.categoryName} · unidad: ${i.unit.name}', style: const TextStyle(color: AppColors.grey)),
        const SizedBox(height: 12),
        Row(children: [
          _Metric('Stock', i.stockLabel, highlight: i.isLowStock),
          _Metric('Mínimo', Quantity.format(i.minStockMilli, i.unit.code)),
          _Metric('Costo prom.', i.avgCostLabel),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (user.can('inventory.adjust'))
            FilledButton.icon(
              key: const Key('ingredient.adjust'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => _adjust(context, ref, i),
              icon: const Icon(Icons.tune),
              label: const Text('Ajustar stock'),
            ),
          if (user.can('ingredients.manage'))
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => context.go('/inventory/${i.id}/edit'),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar'),
            ),
        ]),
        if (user.can('ingredients.manage'))
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Activo'),
            subtitle: const Text('Un insumo inactivo no se compra ni se consume. Nunca se borra.'),
            activeThumbColor: AppColors.orange,
            value: i.isActive,
            onChanged: (v) => _setActive(context, ref, i, v),
          ),
        const SizedBox(height: 8),
        Text('Kardex (últimos 30 días)', style: Theme.of(context).textTheme.titleMedium),
        AsyncView(
          value: movements,
          onRetry: () => ref.invalidate(movementsProvider((ingredientId: ingredientId, type: null))),
          builder: (list) => list.isEmpty
              ? const Padding(padding: EdgeInsets.all(8), child: Text('Sin movimientos. El stock nace de una compra.'))
              : Column(children: [for (final m in list) MovementTile(movement: m)]),
        ),
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, {this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: AppColors.grey, fontSize: 12)),
              Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: highlight ? AppColors.orange : null)),
            ]),
          ),
        ),
      );
}

/// Ajuste con signo: sumar (hallazgo, conteo mayor) o restar (merma, conteo menor). Motivo obligatorio.
class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.ingredient});

  final Ingredient ingredient;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  final _form = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _reason = TextEditingController();
  bool _subtract = true;

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.ingredient;
    return AlertDialog(
      title: Text('Ajustar ${i.name}'),
      content: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Stock actual: ${i.stockLabel}'),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: true, label: Text('Restar')), ButtonSegment(value: false, label: Text('Sumar'))],
            selected: {_subtract},
            onSelectionChanged: (s) => setState(() => _subtract = s.first),
          ),
          const SizedBox(height: 12),
          QuantityField(key: const Key('adjust.quantity'), controller: _quantity, label: 'Cantidad', unit: i.unit.code),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('adjust.reason'),
            controller: _reason,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Motivo (merma, conteo físico…)'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'El motivo es obligatorio.' : null,
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
        FilledButton(
          key: const Key('adjust.confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () {
            if (_form.currentState!.validate()) {
              final milli = Quantity.parseInput(_quantity.text)!;
              Navigator.pop(context, (_subtract ? -milli : milli, _reason.text.trim()));
            }
          },
          child: const Text('Registrar ajuste'),
        ),
      ],
    );
  }
}
