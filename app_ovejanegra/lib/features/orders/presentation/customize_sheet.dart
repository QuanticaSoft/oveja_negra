import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/utils/money.dart';
import '../../catalog/domain/catalog.dart';
import '../domain/cart.dart';

/// Lo que devuelve Personalizar: la línea del producto y, si se eligió, la bebida como línea aparte.
typedef CustomizedLines = ({CartLine product, CartLine? drink});

/// Bebidas para ofrecer junto al producto: los productos de las categorías cuyo nombre contiene
/// "bebida" (p. ej. "Bebidas"), sin incluir al propio producto.
List<Product> drinksOf(List<MenuSection> sections, {required int excludeProductId}) => [
      for (final s in sections)
        if (s.name.toLowerCase().contains('bebida'))
          for (final p in s.products)
            if (p.id != excludeProductId) p,
    ];

/// Personalizar un producto antes de agregarlo: extras (desplegable + cantidad de 1 a 5), nota para
/// la cocina y bebida opcional (desplegable). Devuelve null si se cierra.
Future<CustomizedLines?> showCustomizeSheet(
  BuildContext context, {
  required Product product,
  required List<MenuExtra> extras,
  List<Product> drinks = const [],
  Set<int> rejectedExtras = const {},
}) {
  return showModalBottomSheet<CustomizedLines>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => CustomizeSheet(product: product, extras: extras, drinks: drinks, rejectedExtras: rejectedExtras),
  );
}

class _ExtraChoice {
  _ExtraChoice(this.extraId);

  int extraId;
  int quantity = 1;
}

class CustomizeSheet extends StatefulWidget {
  const CustomizeSheet({
    super.key,
    required this.product,
    required this.extras,
    this.drinks = const [],
    this.rejectedExtras = const {},
  });

  final Product product;
  final List<MenuExtra> extras;
  final List<Product> drinks;
  final Set<int> rejectedExtras;

  @override
  State<CustomizeSheet> createState() => _CustomizeSheetState();
}

class _CustomizeSheetState extends State<CustomizeSheet> {
  final _choices = <_ExtraChoice>[];
  final _notes = TextEditingController();
  int _quantity = 1;
  int? _drinkId;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  bool _available(MenuExtra e) => e.isAvailable && !widget.rejectedExtras.contains(e.id);

  MenuExtra _extra(int id) => widget.extras.firstWhere((e) => e.id == id);

  /// Extras disponibles que todavía no están elegidos en otra fila.
  List<MenuExtra> _unused({int? keep}) => [
        for (final e in widget.extras)
          if (_available(e) && (e.id == keep || !_choices.any((c) => c.extraId == e.id))) e,
      ];

  CartLine get _line => CartLine(
        productId: widget.product.id,
        name: widget.product.name,
        unitCents: widget.product.priceCents,
        quantity: _quantity,
        notes: _notes.text.trim(),
        extras: [
          for (final c in _choices)
            CartExtra(extraId: c.extraId, name: _extra(c.extraId).name, priceCents: _extra(c.extraId).priceCents, quantity: c.quantity),
        ],
      );

  /// La bebida va como línea aparte, con su precio de la cartilla y la misma cantidad que el producto.
  CartLine? get _drinkLine {
    final drink = widget.drinks.where((d) => d.id == _drinkId).firstOrNull;
    return drink == null
        ? null
        : CartLine(productId: drink.id, name: drink.name, unitCents: drink.priceCents, quantity: _quantity);
  }

  @override
  Widget build(BuildContext context) {
    final line = _line;
    final drink = _drinkLine;
    final total = line.lineCents + (drink?.lineCents ?? 0);
    final canAddExtra = _unused().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.product.name, style: Theme.of(context).textTheme.titleLarge),
          Text(Money.bob(widget.product.priceCents), style: const TextStyle(color: AppColors.grey)),
          const SizedBox(height: 12),
          Text('Extras', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final (index, choice) in _choices.indexed) _extraRow(index, choice),
          if (canAddExtra)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('customize.addExtra'),
                onPressed: () => setState(() => _choices.add(_ExtraChoice(_unused().first.id))),
                icon: const Icon(Icons.add),
                label: Text(_choices.isEmpty ? 'Agregar extra' : 'Agregar otro extra'),
              ),
            )
          else if (_choices.isEmpty)
            const Text('No hay extras disponibles ahora.', style: TextStyle(color: AppColors.grey)),
          if (widget.drinks.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              key: const Key('customize.drink'),
              initialValue: _drinkId,
              decoration: const InputDecoration(labelText: 'Bebida'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Sin bebida')),
                for (final d in widget.drinks)
                  DropdownMenuItem<int?>(
                    value: d.id,
                    enabled: d.isAvailable,
                    child: Text(d.isAvailable ? '${d.name} · ${Money.bob(d.priceCents)}' : '${d.name} (agotado)',
                        style: TextStyle(color: d.isAvailable ? null : AppColors.grey)),
                  ),
              ],
              onChanged: (v) => setState(() => _drinkId = v),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            key: const Key('customize.notes'),
            controller: _notes,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Nota para la cocina (sin cebolla, término medio…)'),
            onChanged: (_) => setState(() {}),
          ),
          Row(children: [
            const Text('Cantidad', style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            _Stepper(
              value: _quantity,
              min: 1,
              max: Cart.maxQuantity,
              onChanged: (v) => setState(() => _quantity = v),
              keyPrefix: 'customize.quantity',
            ),
          ]),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('customize.add'),
            onPressed: () => Navigator.pop(context, (product: line, drink: drink)),
            child: Text('Agregar · ${Money.bob(total)}'),
          ),
        ]),
      ),
    );
  }

  Widget _extraRow(int index, _ExtraChoice choice) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            key: Key('customize.extra.$index'),
            initialValue: choice.extraId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Extra', isDense: true),
            items: [
              for (final e in widget.extras)
                DropdownMenuItem(
                  value: e.id,
                  // Agotados o ya elegidos en otra fila: visibles pero no seleccionables.
                  enabled: _unused(keep: choice.extraId).contains(e),
                  child: Text(_available(e) ? '${e.name} +${Money.bob(e.priceCents)}' : '${e.name} (agotado)',
                      style: TextStyle(color: _available(e) ? null : AppColors.grey)),
                ),
            ],
            onChanged: (v) => setState(() => choice.extraId = v!),
          ),
        ),
        _Stepper(
          value: choice.quantity,
          min: 1,
          max: CartExtra.maxQuantity,
          onChanged: (v) => setState(() => choice.quantity = v),
          keyPrefix: 'customize.extra.$index',
        ),
        IconButton(
          key: Key('customize.extra.$index.remove'),
          tooltip: 'Quitar extra',
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _choices.removeAt(index)),
        ),
      ]),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.min, required this.max, required this.onChanged, required this.keyPrefix});

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: Key('$keyPrefix.minus'),
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(width: 24, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
        IconButton(
          key: Key('$keyPrefix.plus'),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ]);
}
