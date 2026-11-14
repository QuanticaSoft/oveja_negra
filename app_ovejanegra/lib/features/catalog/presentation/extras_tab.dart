import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/quantity.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/money_field.dart';
import '../../../core/widgets/quantity_field.dart';
import '../../inventory/domain/inventory.dart';
import '../../inventory/presentation/inventory_widgets.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';

/// Extras (huevo, queso…): precio, insumo que descuentan y estado. Qué categorías los aceptan se
/// elige en la pestaña Categorías.
class ExtrasTab extends ConsumerWidget {
  const ExtrasTab({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [Extra? extra]) async {
    final fields = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _ExtraDialog(extra: extra));
    if (fields == null || !context.mounted) {
      return;
    }
    await _call(context, ref, () => extra == null
        ? ref.read(catalogApiProvider).createExtra(fields)
        : ref.read(catalogApiProvider).updateExtra(extra.id, fields));
  }

  static Future<void> _call(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      refreshCatalog(ref);
    } on ApiException catch (e) {
      if (context.mounted) {
        showMessage(context, e.fieldError('ingredient_quantity') ?? e.fieldError('name') ?? e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('extras.new'),
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Extra'),
      ),
      body: AsyncView(
        value: ref.watch(extrasProvider),
        onRetry: () => ref.invalidate(extrasProvider),
        builder: (extras) => ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
          const Text('Asigna los extras a sus categorías en la pestaña Categorías.', style: TextStyle(color: AppColors.grey)),
          for (final e in extras)
            Card(
              child: ListTile(
                key: Key('extra.${e.id}'),
                title: Text(e.name, style: TextStyle(decoration: e.isActive ? null : TextDecoration.lineThrough)),
                subtitle: Text([
                  '+ ${Money.bob(e.priceCents)}',
                  if (e.ingredientName != null)
                    'descuenta ${Quantity.format(Quantity.toMilli(e.ingredientQuantity!), e.ingredientUnit)} de ${e.ingredientName}',
                  if (e.ingredientName != null && !e.inStock) 'sin stock',
                  if (e.categoryIds.isEmpty) 'sin categorías',
                ].join(' · ')),
                onTap: () => _edit(context, ref, e),
                trailing: Switch(
                  value: e.isActive,
                  activeThumbColor: AppColors.orange,
                  onChanged: (v) => _call(context, ref, () => ref.read(catalogApiProvider).updateExtra(e.id, {'is_active': v})),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _ExtraDialog extends StatefulWidget {
  const _ExtraDialog({this.extra});

  final Extra? extra;

  @override
  State<_ExtraDialog> createState() => _ExtraDialogState();
}

class _ExtraDialogState extends State<_ExtraDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.extra?.name);
  late final _price = TextEditingController(
      text: widget.extra == null ? '' : Money.toApi(widget.extra!.priceCents).replaceAll('.', ','));
  late final _quantity = TextEditingController(
      text: widget.extra?.ingredientQuantity == null ? '' : Quantity.format(Quantity.toMilli(widget.extra!.ingredientQuantity!)).replaceAll('.', ''));
  late int? _ingredientId = widget.extra?.ingredientId;
  late String? _ingredientLabel =
      widget.extra?.ingredientName == null ? null : '${widget.extra!.ingredientName} (${widget.extra!.ingredientUnit})';

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _pickIngredient() async {
    final Ingredient? picked = await pickIngredient(context);
    if (picked != null) {
      setState(() {
        _ingredientId = picked.id;
        _ingredientLabel = '${picked.name} (${picked.unit.code})';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.extra == null ? 'Nuevo extra' : 'Editar extra'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  key: const Key('extra.name'),
                  controller: _name,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'Nombre (Huevo, Queso…)'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido.' : null,
                ),
                MoneyField(key: const Key('extra.price'), controller: _price, label: 'Precio'),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_ingredientLabel ?? 'Sin insumo (no descuenta inventario)'),
                  subtitle: const Text('Insumo que descuenta al venderse'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_ingredientId != null)
                      IconButton(
                        tooltip: 'Quitar insumo',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _ingredientId = null;
                          _ingredientLabel = null;
                          _quantity.clear();
                        }),
                      ),
                    IconButton(tooltip: 'Elegir insumo', icon: const Icon(Icons.kitchen_outlined), onPressed: _pickIngredient),
                  ]),
                ),
                if (_ingredientId != null)
                  QuantityField(controller: _quantity, label: 'Cantidad por porción', helperText: 'P. ej. 1 huevo, 0,020 kg de queso'),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
          FilledButton(
            key: const Key('extra.save'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () {
              if (!_form.currentState!.validate()) {
                return;
              }
              Navigator.pop(context, {
                'name': _name.text.trim(),
                'price': Money.toApi(Money.parseInput(_price.text)!),
                'ingredient_id': _ingredientId,
                'ingredient_quantity': _ingredientId == null ? null : Quantity.toApi(Quantity.parseInput(_quantity.text)!),
              });
            },
            child: const Text('Guardar'),
          ),
        ],
      );
}

/// Elige qué extras acepta una categoría. Devuelve los ids elegidos o null si se cierra.
Future<List<int>?> pickCategoryExtras(BuildContext context, {required Category category, required List<Extra> extras}) {
  final selected = {for (final e in extras) if (e.categoryIds.contains(category.id)) e.id};
  return showDialog<List<int>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Extras de ${category.name}'),
        content: SizedBox(
          width: 400,
          child: extras.isEmpty
              ? const Text('Todavía no hay extras: créalos en la pestaña Extras.')
              : ListView(shrinkWrap: true, children: [
                  for (final e in extras.where((e) => e.isActive))
                    CheckboxListTile(
                      key: Key('categoryExtra.${e.id}'),
                      value: selected.contains(e.id),
                      title: Text(e.name),
                      subtitle: Text('+ ${Money.bob(e.priceCents)}'),
                      onChanged: (on) => setState(() => on! ? selected.add(e.id) : selected.remove(e.id)),
                    ),
                ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
          FilledButton(
            key: const Key('categoryExtras.save'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, selected.toList()..sort()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}
