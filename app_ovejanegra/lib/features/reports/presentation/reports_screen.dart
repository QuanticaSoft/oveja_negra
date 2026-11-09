import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/presentation/session_controller.dart';
import '../domain/reports.dart';
import 'report_widgets.dart';
import 'reports_providers.dart';

/// (ruta, título, descripción, ícono, permiso)
const _reports = [
  ('sales-daily', 'Ventas diarias', 'Vendido y cobrado por día, efectivo y QR', Icons.calendar_view_day, 'reports.read'),
  ('sales-monthly', 'Ventas mensuales', 'Los 12 meses del año', Icons.calendar_month, 'reports.read'),
  ('purchases', 'Compras', 'Por proveedor y por insumo', Icons.shopping_cart_outlined, 'reports.read'),
  ('expenses', 'Gastos por categoría', 'Gastos confirmados del período', Icons.payments_outlined, 'reports.read'),
  ('products', 'Productos más vendidos', 'Por cantidad, de pedidos no cancelados', Icons.emoji_events_outlined, 'reports.read'),
  ('flow', 'Flujo financiero', 'Ingresos, egresos y acumulado por día', Icons.show_chart, 'reports.read'),
  ('ledger', 'Movimientos financieros', 'El libro, con reversos', Icons.receipt_long_outlined, 'finance.read'),
];

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).value!;
    return ListView(padding: const EdgeInsets.all(12), children: [
      for (final (path, title, subtitle, icon, permission) in _reports)
        if (user.can(permission))
          Card(
            child: ListTile(
              key: Key('report.$path'),
              leading: Icon(icon, color: AppColors.orange),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/reports/$path'),
            ),
          ),
    ]);
  }
}

/// Reporte con filtro de fechas (por defecto, los últimos 7 días).
class RangeReport extends ConsumerStatefulWidget {
  const RangeReport({super.key, required this.report});

  final String report;

  @override
  ConsumerState<RangeReport> createState() => _RangeReportState();
}

class _RangeReportState extends ConsumerState<RangeReport> {
  DayRange _range = DayRange.presets()[2];

  @override
  Widget build(BuildContext context) {
    final title = _reports.where((r) => r.$1 == widget.report).firstOrNull?.$2;
    if (title == null) {
      return const Center(child: Text('Reporte no encontrado.'));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Align(alignment: Alignment.centerLeft, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
      ),
      DateRangeBar(value: _range, onChanged: (r) => setState(() => _range = r)),
      Expanded(child: _body()),
    ]);
  }

  Widget _body() => switch (widget.report) {
        'sales-daily' => AsyncView(
            value: ref.watch(salesDailyProvider(_range)),
            onRetry: () => ref.invalidate(salesDailyProvider(_range)),
            builder: (rows) => _SalesView(rows: rows, labelOf: (p) => p.substring(8)),
          ),
        'purchases' => AsyncView(
            value: ref.watch(purchasesReportProvider(_range)),
            onRetry: () => ref.invalidate(purchasesReportProvider(_range)),
            builder: (r) => ListView(padding: const EdgeInsets.all(12), children: [
              Wrap(children: [
                KpiTile(label: 'Compras', value: '${r.count}'),
                KpiTile(label: 'Total', value: Money.bob(r.total)),
              ]),
              const SectionTitle('Por proveedor'),
              ProportionBars(rows: [for (final (name, n, total) in r.bySupplier) ('$name ($n)', total, Money.bob(total))]),
              const SectionTitle('Por insumo'),
              for (final (name, quantity, total, avg) in r.byIngredient)
                ListTile(
                  dense: true,
                  title: Text(name),
                  subtitle: Text('$quantity · promedio ${Money.bob(avg)}'),
                  trailing: Text(Money.bob(total), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              if (r.count == 0) const Text('Sin compras en el período.', style: TextStyle(color: AppColors.grey)),
            ]),
          ),
        'expenses' => AsyncView(
            value: ref.watch(expensesReportProvider(_range)),
            onRetry: () => ref.invalidate(expensesReportProvider(_range)),
            builder: (r) => ListView(padding: const EdgeInsets.all(12), children: [
              KpiTile(label: 'Total de gastos', value: Money.bob(r.$1), width: 220),
              const SizedBox(height: 8),
              ProportionBars(rows: [for (final (name, n, total) in r.$2) ('$name ($n)', total, Money.bob(total))]),
              if (r.$2.isEmpty) const Text('Sin gastos en el período.', style: TextStyle(color: AppColors.grey)),
            ]),
          ),
        'products' => AsyncView(
            value: ref.watch(topProductsProvider(_range)),
            onRetry: () => ref.invalidate(topProductsProvider(_range)),
            builder: (list) => ListView(padding: const EdgeInsets.all(12), children: [
              if (list.isEmpty) const Text('Sin ventas en el período.', style: TextStyle(color: AppColors.grey)),
              ProportionBars(rows: [
                for (final (i, p) in list.indexed) ('${i + 1}. ${p.name}', p.quantity, '${p.quantity} u · ${Money.bob(p.totalCents)}'),
              ]),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Montos antes del descuento de cada pedido.', style: TextStyle(color: AppColors.grey, fontSize: 12)),
              ),
            ]),
          ),
        'flow' => AsyncView(
            value: ref.watch(flowProvider(_range)),
            onRetry: () => ref.invalidate(flowProvider(_range)),
            builder: (days) => ListView(padding: const EdgeInsets.all(12), children: [
              if (days.length > 1) CumulativeLineChart(values: [for (final d in days) d.cumulative]),
              for (final d in days.reversed)
                ListTile(
                  key: Key('flow.${d.date}'),
                  dense: true,
                  title: Text(LaPaz.date(d.date)),
                  subtitle: Text('Ingresos ${Money.bob(d.income)} · Egresos ${Money.bob(d.outcome)} · Acumulado ${Money.bob(d.cumulative)}'),
                  trailing: Text(Money.bob(d.net),
                      style: TextStyle(fontWeight: FontWeight.w800, color: d.net < 0 ? Theme.of(context).colorScheme.error : null)),
                ),
            ]),
          ),
        _ => AsyncView(
            value: ref.watch(ledgerProvider(_range)),
            onRetry: () => ref.invalidate(ledgerProvider(_range)),
            builder: (entries) => entries.isEmpty
                ? const Center(child: Text('Sin movimientos en el período.'))
                : ListView(padding: const EdgeInsets.all(12), children: [
                    for (final e in entries)
                      ListTile(
                        dense: true,
                        leading: Icon(e.isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                            color: e.isIncome ? Colors.green.shade700 : Theme.of(context).colorScheme.error),
                        title: Text(e.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${LaPaz.date(e.businessDate)} · ${e.category}${e.isReversal ? ' · reverso' : ''}'),
                        trailing: Text('${e.isIncome ? '+' : '−'}${Money.bob(e.amountCents)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                  ]),
          ),
      };
}

/// Ventas por período: barras de vendido (negro) y cobrado (naranja) y la tabla.
class _SalesView extends StatelessWidget {
  const _SalesView({required this.rows, required this.labelOf});

  final List<SalesRow> rows;
  final String Function(String period) labelOf;

  @override
  Widget build(BuildContext context) {
    final sold = [for (final r in rows) r.sold];
    final collected = [for (final r in rows) r.collected];
    final total = (sold.fold<int>(0, (a, b) => a + b), collected.fold<int>(0, (a, b) => a + b));
    return ListView(padding: const EdgeInsets.all(12), children: [
      Wrap(children: [
        KpiTile(label: 'Vendido', value: Money.bob(total.$1)),
        KpiTile(label: 'Cobrado', value: Money.bob(total.$2)),
      ]),
      AmountBarChart(labels: [for (final r in rows) labelOf(r.period)], series: [(sold, AppColors.black), (collected, AppColors.orange)]),
      const Row(children: [
        Icon(Icons.square, size: 12, color: AppColors.black),
        Text(' Vendido   '),
        Icon(Icons.square, size: 12, color: AppColors.orange),
        Text(' Cobrado'),
      ]),
      const SizedBox(height: 8),
      for (final r in rows.reversed)
        ListTile(
          key: Key('sales.${r.period}'),
          dense: true,
          title: Text(r.period.length == 10 ? LaPaz.date(r.period) : r.period),
          subtitle: Text('${r.orders} pedidos${r.cancelled > 0 ? ' · ${r.cancelled} cancelados' : ''} · '
              'efectivo ${Money.bob(r.cash)} · QR ${Money.bob(r.qr)}'),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(Money.bob(r.sold), style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(Money.bob(r.collected), style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700)),
          ]),
        ),
    ]);
  }
}

/// Ventas mensuales con selector de año.
class MonthlySalesReport extends ConsumerStatefulWidget {
  const MonthlySalesReport({super.key});

  @override
  ConsumerState<MonthlySalesReport> createState() => _MonthlySalesReportState();
}

class _MonthlySalesReportState extends ConsumerState<MonthlySalesReport> {
  int _year = DayRange.today().year;

  static const _months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
        child: Row(children: [
          Expanded(child: Text('Ventas mensuales', style: Theme.of(context).textTheme.titleLarge)),
          IconButton(onPressed: _year > 2026 ? () => setState(() => _year--) : null, icon: const Icon(Icons.chevron_left)),
          Text('$_year', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          IconButton(onPressed: _year < DayRange.today().year ? () => setState(() => _year++) : null, icon: const Icon(Icons.chevron_right)),
        ]),
      ),
      Expanded(
        child: AsyncView(
          value: ref.watch(salesMonthlyProvider(_year)),
          onRetry: () => ref.invalidate(salesMonthlyProvider(_year)),
          builder: (rows) => _SalesView(rows: rows, labelOf: (p) => _months[int.parse(p.substring(5, 7)) - 1]),
        ),
      ),
    ]);
  }
}
