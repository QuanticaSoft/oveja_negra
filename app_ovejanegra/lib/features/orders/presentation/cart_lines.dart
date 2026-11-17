import 'package:flutter/material.dart';

import '../../../core/utils/money.dart';
import '../domain/cart.dart';

/// Líneas del carrito con + y −. Se usa al vender y al editar los ítems de un pedido.
class CartLines extends StatelessWidget {
  const CartLines({
    super.key,
    required this.cart,
    required this.onQuantity,
    this.rejected = const {},
    this.rejectedExtras = const {},
  });

  final Cart cart;
  final void Function(String lineKey, int quantity) onQuantity;
  final Set<int> rejected;
  final Set<int> rejectedExtras;

  @override
  Widget build(BuildContext context) {
    if (cart.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('Toca un producto para agregarlo.')),
      );
    }
    final error = Theme.of(context).colorScheme.error;
    return Column(children: [
      for (final line in cart.lines) _line(line, error),
    ]);
  }

  Widget _line(CartLine line, Color error) {
    final blocked = rejected.contains(line.productId) || line.extras.any((e) => rejectedExtras.contains(e.extraId));
    final unit = line.unitCents + line.extrasUnitCents;
    return ListTile(
      key: Key('cart.line.${line.key}'),
      contentPadding: EdgeInsets.zero,
      title: Text(line.name, style: TextStyle(color: blocked ? error : null)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (line.extras.isNotEmpty) Text(line.extrasLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (line.notes.isNotEmpty) Text(line.notes, style: const TextStyle(fontStyle: FontStyle.italic)),
        Text(blocked
            ? 'Agotado: quítalo o cámbialo para continuar'
            : '${Money.bob(unit)} × ${line.quantity} = ${Money.bob(line.lineCents)}'),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: Key('cart.minus.${line.productId}'),
          tooltip: 'Quitar uno',
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => onQuantity(line.key, line.quantity - 1),
        ),
        Text('${line.quantity}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        IconButton(
          key: Key('cart.plus.${line.productId}'),
          tooltip: 'Agregar uno',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: line.quantity >= Cart.maxQuantity ? null : () => onQuantity(line.key, line.quantity + 1),
        ),
      ]),
    );
  }
}

/// Subtotal, descuento y total.
class CartTotals extends StatelessWidget {
  const CartTotals({super.key, required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    return Column(children: [
      if (cart.discountCents > 0 || cart.effectiveDeliveryFeeCents > 0)
        _row('Subtotal', Money.bob(cart.subtotalCents), style.bodyMedium),
      if (cart.discountCents > 0) _row('Descuento', '− ${Money.bob(cart.discountCents)}', style.bodyMedium),
      if (cart.effectiveDeliveryFeeCents > 0) _row('Envío', Money.bob(cart.effectiveDeliveryFeeCents), style.bodyMedium),
      _row('Total', Money.bob(cart.totalCents), style.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
    ]);
  }

  Widget _row(String label, String value, TextStyle? style) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [Text(label, style: style), const Spacer(), Text(value, style: style)]),
      );
}
