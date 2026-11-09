import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/quantity.dart';
import '../../../core/widgets/api_error_text.dart';
import '../../../core/widgets/quantity_field.dart';
import '../domain/inventory.dart';
import 'inventory_providers.dart';
import 'inventory_widgets.dart';

/// Salida manual por consumo de varios insumos con un motivo: se registran todos o ninguno.
/// (Con las recetas de la Etapa 2, el consumo saldrá solo de las ventas.)
class ConsumptionScreen extends ConsumerStatefulWidget {
  const ConsumptionScreen({super.key});

  @override
  ConsumerState<ConsumptionScreen> createState() => _ConsumptionScreenState();
}

class _ConsumptionScreenState extends ConsumerState<ConsumptionScreen> {
  final _form = GlobalKey<FormState>();
  final _lines = <(Ingredient, TextEditingController)>[];
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final (_, c) in _lines) {
      c.dispose();
    }
    _reason.dispose();
    super.dispose();
  }

  Future<void> _addLine() async {
    final picked = await pickIngredient(context, exclude: {for (final (i, _) in _lines) i.id});
    if (picked != null) {
      setState(() => _lines.add((picked, TextEditingController())));
    }
  }

  Future<void> _save() async {
    if (_lines.isEmpty || !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(inventoryApiProvider).consume(
        {for (final (i, c) in _lines) i.id: Quantity.parseInput(c.text)!},
        _reason.text.trim(),
      );
      refreshInventory(ref);
      if (mounted) {
        context.go('/inventory');
      }
    } on ApiException catch (e) {
      setState(() => _error = inventoryErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Registrar consumo', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
        for (final (index, (ingredient, controller)) in _lines.indexed)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: QuantityField(
                    key: Key('consume.quantity.$index'),
                    controller: controller,
                    label: ingredient.name,
                    unit: ingredient.unit.code,
                    helperText: 'Disponible: ${ingredient.stockLabel}',
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _lines.removeAt(index).$2.dispose()),
                ),
              ]),
            ),
          ),
        OutlinedButton.icon(
          key: const Key('consume.add'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _addLine,
          icon: const Icon(Icons.add),
          label: const Text('Agregar insumo'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('consume.reason'),
          controller: _reason,
          maxLength: 300,
          decoration: const InputDecoration(labelText: 'Motivo (turno, evento…)'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'El motivo es obligatorio.' : null,
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('consume.save'),
          onPressed: _saving || _lines.isEmpty ? null : _save,
          child: const Text('Registrar consumo'),
        ),
      ]),
    );
  }
}
