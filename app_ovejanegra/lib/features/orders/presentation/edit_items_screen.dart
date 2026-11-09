import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/api_error_text.dart';
import '../../../core/widgets/async_view.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../domain/cart.dart';
import '../domain/order.dart';
import 'cart_lines.dart';
import 'orders_providers.dart';
import 'product_grid.dart';

/// Reemplaza los ítems de un pedido PENDIENTE y sin pagos (si no, el servidor responde ORDER_LOCKED).
class EditItemsScreen extends ConsumerWidget {
  const EditItemsScreen({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncView(
        value: ref.watch(orderProvider(orderId)),
        onRetry: () => ref.invalidate(orderProvider(orderId)),
        builder: (order) => order.itemsEditable
            ? _Editor(order: order)
            : const Center(child: Text('Este pedido ya no se puede editar: está en curso o tiene pagos.')),
      );
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.order});

  final Order order;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late Cart _cart = Cart.fromOrder(widget.order);
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(ordersApiProvider).replaceItems(widget.order.id, _cart.itemsToApi(), _cart.discountCents);
      ref
        ..invalidate(orderProvider(widget.order.id))
        ..invalidate(ordersProvider);
      if (mounted) {
        context.go('/orders/${widget.order.id}');
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final grid = AsyncView(
      value: ref.watch(menuProvider),
      onRetry: () => ref.invalidate(menuProvider),
      builder: (sections) => ProductGrid(
        sections: sections,
        quantityOf: _cart.quantityOf,
        onAdd: (p) => setState(() => _cart = _cart.add(p)),
      ),
    );
    final panel = ListView(padding: const EdgeInsets.all(16), children: [
      Text('Pedido #${widget.order.number}', style: Theme.of(context).textTheme.titleLarge),
      CartLines(cart: _cart, onQuantity: (id, q) => setState(() => _cart = _cart.setQuantity(id, q))),
      CartTotals(cart: _cart),
      if (_cart.discountExceedsSubtotal)
        Text('El descuento del pedido supera el nuevo subtotal.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
      const SizedBox(height: 12),
      if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
      FilledButton(
        key: const Key('editItems.save'),
        onPressed: _saving || _cart.isEmpty || _cart.discountExceedsSubtotal ? null : _save,
        child: const Text('Guardar cambios'),
      ),
    ]);
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= 720
          ? Row(children: [Expanded(child: grid), SizedBox(width: 380, child: Material(color: AppColors.white, child: panel))])
          : Column(children: [Expanded(flex: 3, child: grid), Expanded(flex: 2, child: Material(color: AppColors.white, child: panel))]),
    );
  }
}
