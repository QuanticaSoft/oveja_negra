import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/presentation/session_controller.dart';
import '../../orders/domain/order.dart';
import '../domain/reports.dart';
import 'report_widgets.dart';
import 'reports_providers.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DayRange _range = DayRange.todayRange();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      DateRangeBar(value: _range, onChanged: (r) => setState(() => _range = r)),
      Expanded(
        child: AsyncView(
          value: ref.watch(dashboardProvider(_range)),
          onRetry: () => ref.invalidate(dashboardProvider(_range)),
          builder: (d) => RefreshIndicator(
            onRefresh: () => ref.refresh(dashboardProvider(_range).future),
            child: _DashboardBody(dashboard: d),
          ),
        ),
      ),
    ]);
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.dashboard});

  final Dashboard dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = dashboard;
    final f = d.finance;
    final canInventory = ref.watch(sessionControllerProvider).value?.can('ingredients.read') ?? false;
    final negative = Theme.of(context).colorScheme.error;
    return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
      const SectionTitle('Caja'),
      Wrap(spacing: 4, runSpacing: 4, children: [
        KpiTile(key: const Key('kpi.collected'), label: 'Cobrado', value: Money.bob(f.collected), detail: 'Efectivo ${Money.bob(f.cash)} · QR ${Money.bob(f.qr)}'),
        KpiTile(label: 'Compras', value: Money.bob(f.purchases)),
        KpiTile(label: 'Gastos', value: Money.bob(f.expenses)),
        KpiTile(
          key: const Key('kpi.result'),
          label: 'Resultado operativo',
          value: Money.bob(f.result),
          color: f.result < 0 ? negative : Colors.green.shade800,
          detail: 'Cobrado − compras − gastos',
        ),
      ]),
      const SectionTitle('Pedidos'),
      Wrap(spacing: 4, runSpacing: 4, children: [
        KpiTile(label: 'Pedidos', value: '${d.orders}', detail: d.cancelled > 0 ? '${d.cancelled} cancelados' : null),
        KpiTile(label: 'Vendido', value: Money.bob(d.sold), detail: 'Total de los pedidos del período'),
        KpiTile(label: 'Ticket promedio', value: Money.bob(d.averageTicket)),
      ]),
      if (d.byChannel.isNotEmpty || d.byStatus.values.any((n) => n > 0))
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 16, runSpacing: 8, children: [
              for (final (channel, orders, sold) in d.byChannel)
                Text('${Channel.fromApi(channel).label}: $orders · ${Money.bob(sold)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              for (final status in OrderStatus.values)
                if ((d.byStatus[status.api] ?? 0) > 0) Text('${status.label}: ${d.byStatus[status.api]}'),
            ]),
          ),
        ),
      const SectionTitle('Productos más vendidos'),
      if (d.topProducts.isEmpty)
        const Text('Sin ventas en el período.', style: TextStyle(color: AppColors.grey))
      else
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ProportionBars(rows: [
              for (final p in d.topProducts) (p.name, p.quantity, '${p.quantity} u · ${Money.bob(p.totalCents)}'),
            ]),
          ),
        ),
      SectionTitle('Insumos con stock bajo (${d.lowStockCount})'),
      if (d.lowStock.isEmpty)
        const Text('Ningún insumo por debajo del mínimo.', style: TextStyle(color: AppColors.grey))
      else
        Card(
          child: Column(children: [
            for (final (id, name, detail) in d.lowStock)
              ListTile(
                dense: true,
                leading: const Icon(Icons.warning_amber_rounded, color: AppColors.orange),
                title: Text(name),
                trailing: Text(detail),
                onTap: canInventory ? () => context.go('/inventory/$id') : null,
              ),
          ]),
        ),
    ]);
  }
}
