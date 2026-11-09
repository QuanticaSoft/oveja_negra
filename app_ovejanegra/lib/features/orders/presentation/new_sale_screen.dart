import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/api_error_text.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/presentation/session_controller.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../domain/cart.dart';
import '../domain/order.dart';
import 'cart_lines.dart';
import 'orders_providers.dart';
import 'payment_sheet.dart';
import 'product_grid.dart';

/// Nueva venta: cartilla a la izquierda y pedido a la derecha (tablet), o pedido en una barra
/// inferior desplegable (teléfono).
class NewSaleScreen extends ConsumerWidget {
  const NewSaleScreen({super.key});

  static const twoPaneWidth = 720.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = ref.watch(menuProvider);
    final cart = ref.watch(cartControllerProvider);
    final controller = ref.read(cartControllerProvider.notifier);

    final grid = AsyncView(
      value: menu,
      onRetry: () => ref.invalidate(menuProvider),
      builder: (sections) => RefreshIndicator(
        onRefresh: () => ref.refresh(menuProvider.future),
        child: ProductGrid(
          sections: sections,
          quantityOf: cart.quantityOf,
          onAdd: controller.add,
          rejected: controller.unavailable,
        ),
      ),
    );

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= twoPaneWidth) {
        return Row(children: [
          Expanded(child: grid),
          const SizedBox(
            width: 380,
            child: Material(color: AppColors.white, child: CartPanel()),
          ),
        ]);
      }
      return Column(children: [
        Expanded(child: grid),
        if (!cart.isEmpty)
          Material(
            color: AppColors.black,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  key: const Key('sale.openCart'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => FractionallySizedBox(heightFactor: 0.9, child: CartPanel(onDone: () => Navigator.pop(context))),
                  ),
                  child: Text('Ver pedido (${cart.itemCount}) · ${Money.bob(cart.totalCents)}'),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

/// Pedido en armado: líneas, canal, cliente, descuento, total y botones para cobrar o guardar.
class CartPanel extends ConsumerStatefulWidget {
  const CartPanel({super.key, this.onDone});

  /// Se llama después de registrar el pedido (en teléfono, para cerrar la hoja).
  final VoidCallback? onDone;

  @override
  ConsumerState<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends ConsumerState<CartPanel> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _notes;
  late final TextEditingController _discount;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // El carrito sobrevive a esta hoja (teléfono): los campos arrancan con lo ya escrito.
    final cart = ref.read(cartControllerProvider);
    _name = TextEditingController(text: cart.customerName);
    _phone = TextEditingController(text: cart.customerPhone);
    _notes = TextEditingController(text: cart.notes);
    _discount = TextEditingController(text: cart.discountCents == 0 ? '' : Money.toApi(cart.discountCents));
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _notes, _discount]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit({required bool charge}) async {
    final cart = ref.read(cartControllerProvider);
    List<PaymentDraft> payments = const [];
    if (charge) {
      final picked = await showPaymentSheet(context, dueCents: cart.totalCents, title: 'Cobrar pedido');
      if (picked == null || !mounted) {
        return;
      }
      payments = picked;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final Order order;
    try {
      order = await ref.read(cartControllerProvider.notifier).submit(payments);
    } on ApiException catch (e) {
      if (e.code == 'PRODUCT_UNAVAILABLE') {
        ref.invalidate(menuProvider);
      }
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.fieldError('discount') ?? e.fieldError('customer_phone') ?? e.message;
        });
      }
      return;
    }
    for (final c in [_name, _phone, _notes, _discount]) {
      c.clear();
    }
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    await _showConfirmation(order, payments.fold<int>(0, (sum, p) => sum + (p.changeCents ?? 0)));
    widget.onDone?.call();
  }

  Future<void> _showConfirmation(Order order, int changeCents) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: AppColors.orange, size: 48),
          title: Text('Pedido #${order.number}', key: const Key('sale.confirmation'), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Total ${Money.bob(order.totalCents)} · ${_paymentLabel(order)}'),
            if (changeCents > 0) ...[
              const SizedBox(height: 12),
              Text('Vuelto: ${Money.bob(changeCents)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ],
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Nueva venta'))],
        ),
      );

  static String _paymentLabel(Order order) => switch (order.paymentStatus) {
        'PAGADO' => 'Pagado',
        'PARCIAL' => 'Saldo ${Money.bob(order.balanceCents)}',
        _ => 'Sin cobrar',
      };

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);
    final controller = ref.read(cartControllerProvider.notifier);
    final user = ref.watch(sessionControllerProvider).value;
    final canDiscount = user?.can('orders.discount') ?? false;
    final canCharge = user?.can('payments.create') ?? false;
    final blocked = cart.isEmpty || cart.discountExceedsSubtotal || cart.lines.any((l) => controller.unavailable.contains(l.productId));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Text('Pedido', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          if (!cart.isEmpty) TextButton(onPressed: controller.clear, child: const Text('Vaciar')),
        ]),
        SegmentedButton<Channel>(
          segments: [for (final c in Channel.values) ButtonSegment(value: c, label: Text(c.label))],
          selected: {cart.channel},
          onSelectionChanged: (s) => controller.setChannel(s.first),
        ),
        CartLines(cart: cart, onQuantity: controller.setQuantity, rejected: controller.unavailable),
        if (cart.channel == Channel.whatsapp) ...[
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Cliente (opcional)'),
            onChanged: (v) => controller.setCustomer(name: v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Celular (opcional)'),
            onChanged: (v) => controller.setCustomer(phone: v),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _notes,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Notas (sin cebolla, para llevar…)', counterText: ''),
          onChanged: controller.setNotes,
        ),
        if (canDiscount) ...[
          const SizedBox(height: 8),
          TextField(
            key: const Key('sale.discount'),
            controller: _discount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Descuento (opcional)',
              prefixText: 'Bs ',
              errorText: cart.discountExceedsSubtotal ? 'No puede superar el subtotal.' : null,
            ),
            onChanged: (v) => controller.setDiscount(Money.parseInput(v) ?? 0),
          ),
        ],
        const SizedBox(height: 12),
        CartTotals(cart: cart),
        const SizedBox(height: 12),
        if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
        if (canCharge)
          FilledButton(
            key: const Key('sale.charge'),
            onPressed: blocked || _submitting ? null : () => _submit(charge: true),
            child: _submitting ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Cobrar'),
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('sale.saveUnpaid'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: blocked || _submitting ? null : () => _submit(charge: false),
          child: Text(canCharge ? 'Guardar sin cobrar' : 'Guardar pedido'),
        ),
      ],
    );
  }
}
