import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../auth/domain/auth_user.dart';
import '../../auth/presentation/session_controller.dart';
import '../domain/order.dart';
import 'order_widgets.dart';
import 'orders_providers.dart';
import 'payment_sheet.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderProvider(orderId));
    final user = ref.watch(sessionControllerProvider).value;
    return AsyncView(
      value: order,
      onRetry: () => ref.invalidate(orderProvider(orderId)),
      builder: (o) => RefreshIndicator(
        onRefresh: () => ref.refresh(orderProvider(orderId).future),
        child: _OrderDetail(order: o, user: user!),
      ),
    );
  }
}

class _OrderDetail extends ConsumerStatefulWidget {
  const _OrderDetail({required this.order, required this.user});

  final Order order;
  final AuthUser user;

  @override
  ConsumerState<_OrderDetail> createState() => _OrderDetailState();
}

class _OrderDetailState extends ConsumerState<_OrderDetail> {
  // Clave por pago (posición, método y monto) que se conserva hasta que TODOS los pagos del cobro
  // se registren: si en un cobro mixto falla el segundo, reintentar no duplica el primero.
  final _pendingKeys = <String, String>{};
  bool _busy = false;

  Order get order => widget.order;

  /// Ejecuta una acción, muestra el error del API si falla y recarga el pedido y la lista.
  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && success != null) {
        showMessage(context, success);
      }
    } on ApiException catch (e) {
      if (mounted) {
        showMessage(context, e.message);
      }
    } finally {
      ref
        ..invalidate(orderProvider(order.id))
        ..invalidate(ordersProvider);
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _charge() async {
    final payments = await showPaymentSheet(context, dueCents: order.balanceCents, title: 'Cobrar pedido #${order.number}');
    if (payments == null) {
      return;
    }
    final api = ref.read(ordersApiProvider);
    await _run(() async {
      for (final (i, p) in payments.indexed) {
        final key = _pendingKeys.putIfAbsent('${order.id}:$i:${p.method.api}:${p.amountCents}', IdempotencyKey.generate);
        await api.addPayment(order.id, p.method, p.amountCents, key);
      }
      _pendingKeys.clear();
    }, success: 'Pago registrado.');
  }

  Future<void> _cancel() async {
    final reason = await askReason(context, title: 'Cancelar pedido #${order.number}', action: 'Cancelar pedido');
    if (reason != null) {
      await _run(() => ref.read(ordersApiProvider).cancel(order.id, reason), success: 'Pedido cancelado; sus pagos se anularon.');
    }
  }

  Future<void> _voidPayment(Payment payment) async {
    final reason = await askReason(context, title: 'Anular pago de ${Money.bob(payment.amountCents)}', action: 'Anular pago');
    if (reason != null) {
      await _run(() => ref.read(ordersApiProvider).voidPayment(payment.id, reason), success: 'Pago anulado.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final cancelled = order.status == OrderStatus.cancelado;
    final canAdvance = user.can('orders.update_status') && !cancelled;
    final canCharge = user.can('payments.create') && !cancelled && order.balanceCents > 0;
    final canEdit = user.can('orders.create') && order.itemsEditable;
    final canCancel = user.can('orders.cancel') && !cancelled && order.status != OrderStatus.entregado;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Text('#${order.number}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
          const SizedBox(width: 12),
          StatusPill.order(order.status),
          const SizedBox(width: 8),
          StatusPill.payment(order.paymentStatus),
        ]),
        Text('${order.channel.label} · ${LaPaz.dateTime(order.createdAt)} · ${order.createdBy}', style: const TextStyle(color: AppColors.grey)),
        if (order.customerName != null || order.customerPhone != null)
          Text('Cliente: ${[order.customerName, order.customerPhone].whereType<String>().join(' · ')}'),
        if (order.notes != null) Text('Nota: ${order.notes}', style: const TextStyle(fontStyle: FontStyle.italic)),
        if (order.cancelReason != null) Text('Motivo de cancelación: ${order.cancelReason}', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              for (final i in order.items)
                _line('${i.quantity}× ${i.name}', Money.bob(i.lineCents)),
              const Divider(),
              if (order.discountCents > 0) ...[
                _line('Subtotal', Money.bob(order.subtotalCents)),
                _line('Descuento', '− ${Money.bob(order.discountCents)}'),
              ],
              _line('Total', Money.bob(order.totalCents), bold: true),
              _line('Pagado', Money.bob(order.paidCents)),
              if (order.balanceCents > 0) _line('Saldo', Money.bob(order.balanceCents), bold: true),
            ]),
          ),
        ),
        if (canAdvance && order.status.next.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Cambiar estado', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final next in order.status.next)
              FilledButton.tonal(
                key: Key('order.status.${next.api}'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                // El servidor exige el pago completo para entregar: el botón lo anticipa.
                onPressed: _busy || (next == OrderStatus.entregado && order.balanceCents > 0)
                    ? null
                    : () => _run(() => ref.read(ordersApiProvider).changeStatus(order.id, next)),
                child: Text(next.label),
              ),
          ]),
          if (order.balanceCents > 0 && order.status.next.contains(OrderStatus.entregado))
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Para entregarlo, primero cobra el saldo.', style: TextStyle(color: AppColors.grey)),
            ),
        ],
        const SizedBox(height: 16),
        if (canCharge)
          FilledButton(
            key: const Key('order.charge'),
            onPressed: _busy ? null : _charge,
            child: Text('Cobrar ${Money.bob(order.balanceCents)}'),
          ),
        if (canEdit) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('order.editItems'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : () => context.go('/orders/${order.id}/items'),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar ítems'),
          ),
        ],
        if (order.payments.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Pagos', style: Theme.of(context).textTheme.titleMedium),
          for (final p in order.payments)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(p.method == PaymentMethod.qr ? Icons.qr_code_2 : Icons.payments_outlined),
              title: Text('${p.method.label} ${Money.bob(p.amountCents)}',
                  style: TextStyle(decoration: p.isVoided ? TextDecoration.lineThrough : null)),
              subtitle: Text(p.isVoided ? 'Anulado: ${p.voidReason}' : '${LaPaz.dateTime(p.createdAt)} · ${p.receivedBy}'),
              trailing: !p.isVoided && user.can('payments.void')
                  ? TextButton(key: Key('payment.void.${p.id}'), onPressed: _busy ? null : () => _voidPayment(p), child: const Text('Anular'))
                  : null,
            ),
        ],
        if (canCancel) ...[
          const SizedBox(height: 24),
          TextButton.icon(
            key: const Key('order.cancel'),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: _busy ? null : _cancel,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancelar pedido'),
          ),
        ],
      ],
    );
  }

  Widget _line(String label, String value, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.normal, fontSize: bold ? 16 : 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(label, style: style)), Text(value, style: style)]),
    );
  }
}
