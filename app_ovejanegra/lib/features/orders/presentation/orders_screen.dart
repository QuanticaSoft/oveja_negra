import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/async_view.dart';
import '../data/orders_api.dart';
import '../domain/order.dart';
import 'order_widgets.dart';
import 'orders_providers.dart';

/// Pedidos del día (por defecto los abiertos, como en la cocina). Se actualiza solo cada 20 s
/// mientras está a la vista: el backend PHP no tiene conexión en tiempo real.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  static const refreshEvery = Duration(seconds: 20);

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  Set<OrderStatus> _statuses = {...OrderStatus.open};
  Channel? _channel;
  DateTime? _date;
  Timer? _timer;

  OrdersQuery get _query => OrdersQuery(
        date: _date == null ? null : DateFormat('yyyy-MM-dd').format(_date!),
        statuses: _statuses,
        channel: _channel,
      );

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(OrdersScreen.refreshEvery, (_) => ref.invalidate(ordersProvider(_query)));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = LaPaz.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: DateTime(2026),
      lastDate: today,
    );
    if (picked != null) {
      setState(() => _date = DateUtils.isSameDay(picked, today) ? null : picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _query;
    final orders = ref.watch(ordersProvider(query));
    return Column(children: [
      SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            ActionChip(
              avatar: const Icon(Icons.calendar_today, size: 18),
              label: Text(_date == null ? 'Hoy' : DateFormat('dd/MM/yyyy').format(_date!)),
              onPressed: _pickDate,
            ),
            const SizedBox(width: 8),
            for (final s in OrderStatus.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(s.label),
                  selected: _statuses.contains(s),
                  onSelected: (on) => setState(() => _statuses = on ? {..._statuses, s} : ({..._statuses}..remove(s))),
                ),
              ),
            DropdownButton<Channel?>(
              value: _channel,
              underline: const SizedBox.shrink(),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos los canales')),
                for (final c in Channel.values) DropdownMenuItem(value: c, child: Text(c.label)),
              ],
              onChanged: (c) => setState(() => _channel = c),
            ),
          ],
        ),
      ),
      Expanded(
        child: AsyncView(
          value: orders,
          onRetry: () => ref.invalidate(ordersProvider(query)),
          builder: (list) => RefreshIndicator(
            onRefresh: () => ref.refresh(ordersProvider(query).future),
            child: list.isEmpty
                ? ListView(children: const [SizedBox(height: 120), Center(child: Text('No hay pedidos con estos filtros.'))])
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: list.length,
                    itemBuilder: (_, i) => OrderCard(order: list[i]),
                  ),
          ),
        ),
      ),
    ]);
  }
}

class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        key: Key('order.${order.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/orders/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('#${order.number}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(width: 10),
              Icon(order.channel == Channel.whatsapp ? Icons.chat_outlined : Icons.storefront_outlined, size: 18, color: AppColors.grey),
              const SizedBox(width: 4),
              Text(LaPaz.dateTime(order.createdAt).substring(11), style: const TextStyle(color: AppColors.grey)),
              const Spacer(),
              StatusPill.order(order.status),
            ]),
            const SizedBox(height: 6),
            Text(order.items.map((i) => '${i.quantity}× ${i.name}').join(', '), maxLines: 3, overflow: TextOverflow.ellipsis),
            if (order.notes != null) Text('Nota: ${order.notes}', style: const TextStyle(fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
            Row(children: [
              Text(Money.bob(order.totalCents), style: const TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              StatusPill.payment(order.paymentStatus),
            ]),
          ]),
        ),
      ),
    );
  }
}
