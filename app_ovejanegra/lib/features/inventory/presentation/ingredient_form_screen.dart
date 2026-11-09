import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/quantity.dart';
import '../../../core/widgets/api_error_text.dart';
import '../../../core/widgets/async_view.dart';
import '../domain/inventory.dart';
import 'inventory_providers.dart';

/// Alta (`ingredientId` null) o edición de un insumo. El stock y el costo no se editan: salen de los movimientos.
class IngredientFormScreen extends ConsumerWidget {
  const IngredientFormScreen({super.key, this.ingredientId});

  final int? ingredientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget form(Ingredient? ingredient) => AsyncView(
          value: ref.watch(unitsProvider),
          onRetry: () => ref.invalidate(unitsProvider),
          builder: (units) => AsyncView(
            value: ref.watch(ingredientCategoriesProvider),
            onRetry: () => ref.invalidate(ingredientCategoriesProvider),
            builder: (categories) => _IngredientForm(units: units, categories: categories, ingredient: ingredient),
          ),
        );
    if (ingredientId == null) {
      return form(null);
    }
    return AsyncView(
      value: ref.watch(ingredientProvider(ingredientId!)),
      onRetry: () => ref.invalidate(ingredientProvider(ingredientId!)),
      builder: form,
    );
  }
}

class _IngredientForm extends ConsumerStatefulWidget {
  const _IngredientForm({required this.units, required this.categories, this.ingredient});

  final List<Unit> units;
  final List<IngredientCategory> categories;
  final Ingredient? ingredient;

  @override
  ConsumerState<_IngredientForm> createState() => _IngredientFormState();
}

class _IngredientFormState extends ConsumerState<_IngredientForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.ingredient?.name);
  late final _minStock = TextEditingController(
      text: widget.ingredient == null ? '0' : Quantity.format(widget.ingredient!.minStockMilli).replaceAll('.', ''));
  late int? _categoryId = widget.ingredient?.categoryId;
  late int? _unitId = widget.ingredient?.unit.id;
  bool _saving = false;
  ApiException? _error;

  @override
  void dispose() {
    _name.dispose();
    _minStock.dispose();
    super.dispose();
  }

  Future<void> _newCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva categoría de insumo'),
        content: TextField(controller: controller, autofocus: true, maxLength: 60, decoration: const InputDecoration(labelText: 'Nombre')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) {
      return;
    }
    try {
      final category = await ref.read(inventoryApiProvider).createCategory(name);
      ref.invalidate(ingredientCategoriesProvider);
      setState(() => _categoryId = category.id);
    } on ApiException catch (e) {
      setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final fields = {
      'name': _name.text.trim(),
      'category_id': _categoryId,
      'unit_id': _unitId,
      'min_stock': Quantity.toApi(Quantity.parseInput(_minStock.text) ?? 0),
    };
    final api = ref.read(inventoryApiProvider);
    try {
      final saved = widget.ingredient == null
          ? await api.createIngredient(fields)
          : await api.updateIngredient(widget.ingredient!.id, fields);
      refreshInventory(ref);
      if (mounted) {
        context.go('/inventory/${saved.id}');
      }
    } on ApiException catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.ingredient == null ? 'Nuevo insumo' : 'Editar ${widget.ingredient!.name}',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        if (error != null) ...[
          ErrorBanner(error.code == 'UNIT_LOCKED' ? 'Este insumo ya tiene movimientos: su unidad no se puede cambiar.' : error.message),
          const SizedBox(height: 12),
        ],
        TextFormField(
          key: const Key('ingredient.name'),
          controller: _name,
          maxLength: 80,
          decoration: InputDecoration(labelText: 'Nombre', errorText: error?.fieldError('name')),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido.' : null,
        ),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [for (final c in widget.categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => setState(() => _categoryId = v),
              validator: (v) => v == null ? 'Elige una categoría.' : null,
            ),
          ),
          IconButton(tooltip: 'Nueva categoría', onPressed: _newCategory, icon: const Icon(Icons.add_circle_outline)),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _unitId,
          decoration: const InputDecoration(
            labelText: 'Unidad',
            helperText: 'Las compras y el stock se registran en esta unidad.',
          ),
          items: [for (final u in widget.units) DropdownMenuItem(value: u.id, child: Text('${u.name} (${u.code})'))],
          onChanged: (v) => setState(() => _unitId = v),
          validator: (v) => v == null ? 'Elige una unidad.' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _minStock,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Stock mínimo', helperText: 'Por debajo de esto, el insumo se marca con stock bajo.'),
          validator: (v) => Quantity.parseInput(v ?? '') == null ? 'Cantidad con hasta 3 decimales.' : null,
        ),
        const SizedBox(height: 20),
        FilledButton(key: const Key('ingredient.save'), onPressed: _saving ? null : _save, child: const Text('Guardar')),
      ]),
    );
  }
}
