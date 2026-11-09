import '../../../core/utils/money.dart';
import '../../../core/utils/quantity.dart';

int _c(Object? v) => Money.toCents(v as String);

/// Cuadre del período: cobrado − compras − gastos = resultado (todo neto de reversos).
class FinanceSummary {
  const FinanceSummary({
    required this.collected,
    required this.cash,
    required this.qr,
    required this.purchases,
    required this.expenses,
    required this.result,
    required this.expensesByCategory,
  });

  final int collected;
  final int cash;
  final int qr;
  final int purchases;
  final int expenses;
  final int result;
  final List<(String, int)> expensesByCategory;

  factory FinanceSummary.fromJson(Map<String, dynamic> j) {
    final sales = j['sales_collected'] as Map<String, dynamic>;
    final expenses = j['expenses'] as Map<String, dynamic>;
    return FinanceSummary(
      collected: _c(sales['total']),
      cash: _c(sales['cash']),
      qr: _c(sales['qr']),
      purchases: _c(j['purchases']),
      expenses: _c(expenses['total']),
      result: _c(j['operating_result']),
      expensesByCategory: [
        for (final row in (expenses['by_category'] as List).cast<Map>())
          ((row['category'] as Map)['name'] as String, _c(row['total'])),
      ],
    );
  }
}

class TopProduct {
  const TopProduct(this.name, this.quantity, this.totalCents);

  final String name;
  final int quantity;
  final int totalCents;

  factory TopProduct.fromJson(Map<String, dynamic> j) =>
      TopProduct((j['product'] as Map)['name'] as String, j['quantity'] as int, _c(j['total']));
}

class Dashboard {
  const Dashboard({
    required this.finance,
    required this.orders,
    required this.sold,
    required this.averageTicket,
    required this.cancelled,
    required this.byChannel,
    required this.byStatus,
    required this.topProducts,
    required this.lowStockCount,
    required this.lowStock,
  });

  final FinanceSummary finance;
  final int orders;
  final int sold;
  final int averageTicket;
  final int cancelled;
  final List<(String, int, int)> byChannel;
  final Map<String, int> byStatus;
  final List<TopProduct> topProducts;
  final int lowStockCount;

  /// (id, nombre, "stock / mínimo")
  final List<(int, String, String)> lowStock;

  factory Dashboard.fromJson(Map<String, dynamic> j) {
    final orders = j['orders'] as Map<String, dynamic>;
    final low = j['low_stock'] as Map<String, dynamic>;
    return Dashboard(
      finance: FinanceSummary.fromJson(j['finance'] as Map<String, dynamic>),
      orders: orders['count'] as int,
      sold: _c(orders['sold']),
      averageTicket: _c(orders['average_ticket']),
      cancelled: orders['cancelled'] as int,
      byChannel: [
        for (final c in (orders['by_channel'] as List).cast<Map>()) (c['channel'] as String, c['orders'] as int, _c(c['sold'])),
      ],
      byStatus: Map<String, int>.from(orders['by_status'] as Map),
      topProducts: [for (final p in j['top_products'] as List) TopProduct.fromJson(p as Map<String, dynamic>)],
      lowStockCount: low['count'] as int,
      lowStock: [
        for (final i in (low['ingredients'] as List).cast<Map>())
          (
            i['id'] as int,
            i['name'] as String,
            '${Quantity.format(Quantity.toMilli(i['current_stock'] as String), i['unit'] as String)} / '
                'mín. ${Quantity.format(Quantity.toMilli(i['min_stock'] as String))}',
          ),
      ],
    );
  }
}

/// Un día o un mes del reporte de ventas.
class SalesRow {
  const SalesRow(this.period, this.orders, this.sold, this.cancelled, this.collected, this.cash, this.qr);

  final String period;
  final int orders;
  final int sold;
  final int cancelled;
  final int collected;
  final int cash;
  final int qr;

  factory SalesRow.fromJson(Map<String, dynamic> j) => SalesRow(
        (j['date'] ?? j['month']) as String,
        j['orders'] as int,
        _c(j['sold']),
        j['cancelled'] as int,
        _c(j['collected']),
        _c(j['cash']),
        _c(j['qr']),
      );
}

class FlowDay {
  const FlowDay(this.date, this.income, this.outcome, this.net, this.cumulative);

  final String date;
  final int income;
  final int outcome;
  final int net;
  final int cumulative;

  factory FlowDay.fromJson(Map<String, dynamic> j) =>
      FlowDay(j['date'] as String, _c(j['income']), _c(j['outcome']), _c(j['net']), _c(j['cumulative']));
}

class PurchasesReport {
  const PurchasesReport(this.count, this.total, this.bySupplier, this.byIngredient);

  final int count;
  final int total;

  /// (proveedor, n.º de compras, total)
  final List<(String, int, int)> bySupplier;

  /// (insumo, cantidad con unidad, total, precio promedio)
  final List<(String, String, int, int)> byIngredient;

  factory PurchasesReport.fromJson(Map<String, dynamic> j) => PurchasesReport(
        j['purchases'] as int,
        _c(j['total']),
        [
          for (final s in (j['by_supplier'] as List).cast<Map>())
            (((s['supplier'] as Map?)?['name'] as String?) ?? 'Sin proveedor', s['purchases'] as int, _c(s['total'])),
        ],
        [
          for (final i in (j['by_ingredient'] as List).cast<Map>())
            (
              (i['ingredient'] as Map)['name'] as String,
              Quantity.format(Quantity.toMilli(i['quantity'] as String), (i['ingredient'] as Map)['unit'] as String),
              _c(i['total']),
              _c(i['average_unit_price']),
            ),
        ],
      );
}
