import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/utils/money.dart';
import '../../catalog/domain/catalog.dart';
import '../domain/cart.dart';

/// Personalizar un producto antes de agregarlo: extras (0 a 5 de cada uno) y nota para la cocina.
/// Devuelve la línea lista para el carrito, o null si se cierra.
Future<CartLine?> showCustomizeSheet(
  BuildContext context, {
  required Product product,
  required List<MenuExtra> extras,
  Set<int> rejectedExtras = const {},
}) {
  return showModalBottomSheet<CartLine>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => CustomizeSheet(product: product, extras: extras, rejectedExtras: rejectedExtras),
  );
}

class CustomizeSheet extends StatefulWidget {
  const CustomizeSheet({super.key, required this.product, required this.extras, this.rejectedExtras = const {}});

  final Product product;
  final List<MenuExtra> extras;
  final Set<int> rejectedExtras;

  @override
  State<CustomizeSheet> createState() => _CustomizeSheetState();
}

class _CustomizeSheetState extends State<CustomizeSheet> {
  final _quantities = <int, int>{};
  final _notes = TextEditingController();
  int _quantity = 1;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  bool _available(MenuExtra e) => e.isAvailable && !widget.rejectedExtras.contains(e.id);

  CartLine get _line => CartLine(
        productId: widget.product.id,
        name: widget.product.name,
        unitCents: widget.product.priceCents,
        quantity: _quantity,
        notes: _notes.text.trim(),
        extras: [
          for (final e in widget.extras)
            if ((_quantities[e.id] ?? 0) > 0)
              CartExtra(extraId: e.id, name: e.name, priceCents: e.priceCents, quantity: _quantities[e.id]!),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final line = _line;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.product.name, style: Theme.of(context).textTheme.titleLarge),
          Text(Money.bob(widget.product.priceCents), style: const TextStyle(color: AppColors.grey)),
          const SizedBox(height: 12),
          Text('Extras', style: Theme.of(context).textTheme.titleMedium),
          for (final e in widget.extras) _extraRow(e),
          const SizedBox(height: 8),
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
            onPressed: () => Navigator.pop(context, line),
            child: Text('Agregar · ${Money.bob(line.lineCents)}'),
          ),
        ]),
      ),
    );
  }

  Widget _extraRow(MenuExtra e) {
    final available = _available(e);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(e.name, style: TextStyle(color: available ? null : AppColors.grey)),
      subtitle: Text(available ? '+ ${Money.bob(e.priceCents)}' : 'Agotado'),
      trailing: available
          ? _Stepper(
              value: _quantities[e.id] ?? 0,
              min: 0,
              max: CartExtra.maxQuantity,
              onChanged: (v) => setState(() => _quantities[e.id] = v),
              keyPrefix: 'customize.extra.${e.id}',
            )
          : null,
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
