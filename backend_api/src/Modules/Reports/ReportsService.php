<?php

declare(strict_types=1);

/**
 * Dashboard y reportes, solo lectura. Dos cifras distintas, con nombre propio:
 * - "vendido" (sold): total de pedidos no cancelados, por el día operativo del pedido;
 * - "cobrado" (collected): dinero que entró según el libro, por el día en que se cobró.
 */
final class ReportsService
{
    private const TOP_PRODUCTS_DASHBOARD = 5;
    private const LOW_STOCK_DASHBOARD = 10;
    private const SIGNED = "CASE ft.type WHEN 'INGRESO' THEN ft.amount ELSE -ft.amount END";

    private readonly FinanceService $finance;

    public function __construct(private readonly PDO $db, string $dayCutoff = '04:00')
    {
        $this->finance = new FinanceService($db, $dayCutoff);
    }

    public function dashboard(array $query): array
    {
        $range = $this->range($query, defaultDays: 1);
        [$from, $to] = [$range->from, $range->to];

        $orders = $this->row(
            "SELECT count(*) FILTER (WHERE status <> 'CANCELADO')                                   AS orders,
                    COALESCE(sum(total) FILTER (WHERE status <> 'CANCELADO'), 0)::numeric(12,2)     AS sold,
                    COALESCE(round(avg(total) FILTER (WHERE status <> 'CANCELADO'), 2), 0)::numeric(12,2) AS average_ticket,
                    count(*) FILTER (WHERE status = 'CANCELADO')                                    AS cancelled
             FROM orders WHERE business_date BETWEEN ? AND ?", [$from, $to]);
        $byChannel = $this->rows(
            "SELECT channel, count(*) AS orders, sum(total)::numeric(12,2) AS sold
             FROM orders WHERE business_date BETWEEN ? AND ? AND status <> 'CANCELADO'
             GROUP BY channel ORDER BY channel", [$from, $to]);
        $byStatus = $this->rows(
            'SELECT status, count(*) AS orders FROM orders WHERE business_date BETWEEN ? AND ? GROUP BY status', [$from, $to]);
        $lowStock = $this->rows(
            'SELECT i.id, i.name, i.current_stock, i.min_stock, u.code AS unit, count(*) OVER () AS total
             FROM ingredients i JOIN units u ON u.id = i.unit_id
             WHERE i.is_active AND i.current_stock <= i.min_stock
             ORDER BY i.current_stock / NULLIF(i.min_stock, 0) NULLS FIRST, i.name LIMIT ' . self::LOW_STOCK_DASHBOARD);

        $statuses = array_fill_keys(['PENDIENTE', 'EN_PREPARACION', 'LISTO', 'ENTREGADO', 'CANCELADO'], 0);
        foreach ($byStatus as $row) {
            $statuses[$row['status']] = (int) $row['orders'];
        }
        return [
            'from' => $from,
            'to' => $to,
            'finance' => $this->finance->summary($from, $to),
            'orders' => [
                'count' => (int) $orders['orders'],
                'sold' => $orders['sold'],
                'average_ticket' => $orders['average_ticket'],
                'cancelled' => (int) $orders['cancelled'],
                'by_channel' => array_map(static fn (array $row): array => [
                    'channel' => $row['channel'], 'orders' => (int) $row['orders'], 'sold' => $row['sold'],
                ], $byChannel),
                'by_status' => $statuses,
            ],
            'top_products' => $this->topProducts($from, $to, self::TOP_PRODUCTS_DASHBOARD),
            'low_stock' => [
                'count' => (int) ($lowStock[0]['total'] ?? 0),
                'ingredients' => array_map(static fn (array $row): array => [
                    'id' => (int) $row['id'], 'name' => $row['name'], 'unit' => $row['unit'],
                    'current_stock' => $row['current_stock'], 'min_stock' => $row['min_stock'],
                ], $lowStock),
            ],
        ];
    }

    /** Un renglón por día del rango, también los días sin movimiento. */
    public function salesDaily(array $query): array
    {
        $range = $this->range($query);
        return array_map(static fn (array $row): array => ['date' => $row['period']] + self::salesRow($row),
            $this->rows($this->salesSql("generate_series(?::date, ?::date, interval '1 day')::date", 'business_date', 'ft.business_date'),
                [$range->from, $range->to, $range->from, $range->to, $range->from, $range->to]));
    }

    /** Los 12 meses del año, también los meses sin movimiento. */
    public function salesMonthly(array $query): array
    {
        $year = Validation::positiveInt($query['year'] ?? substr($this->finance->today(), 0, 4));
        if ($year === null || $year < 2000 || $year > 2100) {
            throw ApiException::validation(['year' => 'Año entre 2000 y 2100.']);
        }
        [$from, $to] = ["{$year}-01-01", "{$year}-12-31"];
        $rows = $this->rows(
            $this->salesSql("generate_series(?::date, ?::date, interval '1 month')::date",
                "date_trunc('month', business_date)::date", "date_trunc('month', ft.business_date)::date"),
            [$from, $to, $from, $to, $from, $to]);
        return ['year' => $year, 'months' => array_map(static fn (array $row): array => ['month' => substr($row['period'], 0, 7)] + self::salesRow($row), $rows)];
    }

    /** Compras confirmadas por proveedor y por insumo (las anuladas no cuentan). */
    public function purchases(array $query): array
    {
        $range = $this->range($query);
        $params = [$range->from, $range->to];
        $bySupplier = $this->rows(
            "SELECT s.id, s.name, count(*) AS purchases, sum(pu.total)::numeric(12,2) AS total
             FROM purchases pu LEFT JOIN suppliers s ON s.id = pu.supplier_id
             WHERE pu.status = 'CONFIRMADA' AND pu.purchase_date BETWEEN ? AND ?
             GROUP BY s.id, s.name ORDER BY total DESC, s.name NULLS LAST", $params);
        $byIngredient = $this->rows(
            "SELECT i.id, i.name, u.code AS unit, sum(pi.quantity)::numeric(12,3) AS quantity,
                    sum(pi.line_total)::numeric(12,2) AS total,
                    round(sum(pi.line_total) / sum(pi.quantity), 2)::numeric(12,2) AS average_unit_price
             FROM purchase_items pi
             JOIN purchases pu ON pu.id = pi.purchase_id
             JOIN ingredients i ON i.id = pi.ingredient_id
             JOIN units u ON u.id = i.unit_id
             WHERE pu.status = 'CONFIRMADA' AND pu.purchase_date BETWEEN ? AND ?
             GROUP BY i.id, i.name, u.code ORDER BY total DESC, i.name", $params);
        $total = $this->row(
            "SELECT count(*) AS purchases, COALESCE(sum(total), 0)::numeric(12,2) AS total
             FROM purchases WHERE status = 'CONFIRMADA' AND purchase_date BETWEEN ? AND ?", $params);

        return [
            'from' => $range->from,
            'to' => $range->to,
            'purchases' => (int) $total['purchases'],
            'total' => $total['total'],
            'by_supplier' => array_map(static fn (array $row): array => [
                'supplier' => $row['id'] === null ? null : ['id' => (int) $row['id'], 'name' => $row['name']],
                'purchases' => (int) $row['purchases'],
                'total' => $row['total'],
            ], $bySupplier),
            'by_ingredient' => array_map(static fn (array $row): array => [
                'ingredient' => ['id' => (int) $row['id'], 'name' => $row['name'], 'unit' => $row['unit']],
                'quantity' => $row['quantity'],
                'total' => $row['total'],
                'average_unit_price' => $row['average_unit_price'],
            ], $byIngredient),
        ];
    }

    public function expensesByCategory(array $query): array
    {
        $range = $this->range($query);
        $rows = $this->rows(
            "SELECT c.id, c.name, count(*) AS expenses, sum(e.amount)::numeric(12,2) AS total
             FROM expenses e JOIN expense_categories c ON c.id = e.category_id
             WHERE e.status = 'CONFIRMADO' AND e.expense_date BETWEEN ? AND ?
             GROUP BY c.id, c.name ORDER BY total DESC, c.name", [$range->from, $range->to]);
        $total = $this->row(
            "SELECT COALESCE(sum(amount), 0)::numeric(12,2) AS total FROM expenses
             WHERE status = 'CONFIRMADO' AND expense_date BETWEEN ? AND ?", [$range->from, $range->to]);
        return [
            'from' => $range->from,
            'to' => $range->to,
            'total' => $total['total'],
            'categories' => array_map(static fn (array $row): array => [
                'category' => ['id' => (int) $row['id'], 'name' => $row['name']],
                'expenses' => (int) $row['expenses'],
                'total' => $row['total'],
            ], $rows),
        ];
    }

    public function topProductsReport(array $query): array
    {
        $range = $this->range($query);
        $limit = Validation::positiveInt($query['limit'] ?? '10');
        if ($limit === null || $limit > 50) {
            throw ApiException::validation(['limit' => 'Entre 1 y 50.']);
        }
        return ['from' => $range->from, 'to' => $range->to, 'products' => $this->topProducts($range->from, $range->to, $limit)];
    }

    /** Flujo de caja diario: todo lo que entró y salió (reversos incluidos) y el acumulado del período. */
    public function financeMovements(array $query): array
    {
        $range = $this->range($query);
        $rows = $this->rows(
            "SELECT d.day::text AS date,
                    COALESCE(sum(ft.amount) FILTER (WHERE ft.type = 'INGRESO'), 0)::numeric(12,2) AS income,
                    COALESCE(sum(ft.amount) FILTER (WHERE ft.type = 'EGRESO'), 0)::numeric(12,2)  AS outcome,
                    COALESCE(sum(" . self::SIGNED . "), 0)::numeric(12,2)                          AS net,
                    sum(COALESCE(sum(" . self::SIGNED . "), 0)) OVER (ORDER BY d.day)::numeric(12,2) AS cumulative
             FROM (SELECT generate_series(?::date, ?::date, interval '1 day')::date AS day) d
             LEFT JOIN financial_transactions ft ON ft.business_date = d.day
             GROUP BY d.day ORDER BY d.day", [$range->from, $range->to]);
        return ['from' => $range->from, 'to' => $range->to, 'days' => $rows];
    }

    /** Por cantidad vendida en pedidos no cancelados; el monto es antes del descuento del pedido. */
    private function topProducts(string $from, string $to, int $limit): array
    {
        $rows = $this->rows(
            "SELECT oi.product_id, p.name, sum(oi.quantity) AS quantity, sum(oi.line_total)::numeric(12,2) AS total
             FROM order_items oi
             JOIN orders o ON o.id = oi.order_id
             JOIN products p ON p.id = oi.product_id
             WHERE o.status <> 'CANCELADO' AND o.business_date BETWEEN ? AND ?
             GROUP BY oi.product_id, p.name
             ORDER BY quantity DESC, total DESC, p.name LIMIT ?", [$from, $to, $limit]);
        return array_map(static fn (array $row): array => [
            'product' => ['id' => (int) $row['product_id'], 'name' => $row['name']],
            'quantity' => (int) $row['quantity'],
            'total' => $row['total'],
        ], $rows);
    }

    /**
     * Pedidos (vendido) por el período del pedido y cobros por el período del libro, unidos a una serie
     * de períodos para que aparezcan también los vacíos. $orderPeriod y $ledgerPeriod agrupan por día o por mes.
     */
    private function salesSql(string $series, string $orderPeriod, string $ledgerPeriod): string
    {
        $signed = self::SIGNED;
        return "WITH periods AS (SELECT {$series} AS period),
             o AS (
                 SELECT {$orderPeriod} AS period,
                        count(*) FILTER (WHERE status <> 'CANCELADO') AS orders,
                        sum(total) FILTER (WHERE status <> 'CANCELADO') AS sold,
                        count(*) FILTER (WHERE status = 'CANCELADO') AS cancelled
                 FROM orders WHERE business_date BETWEEN ? AND ? GROUP BY 1
             ),
             c AS (
                 SELECT {$ledgerPeriod} AS period,
                        sum({$signed}) AS collected,
                        sum({$signed}) FILTER (WHERE p.method = 'EFECTIVO') AS cash,
                        sum({$signed}) FILTER (WHERE p.method = 'QR') AS qr
                 FROM financial_transactions ft JOIN payments p ON p.id = ft.source_id
                 WHERE ft.source_type = 'PAYMENT' AND ft.business_date BETWEEN ? AND ? GROUP BY 1
             )
             SELECT periods.period::text AS period,
                    COALESCE(o.orders, 0) AS orders, COALESCE(o.sold, 0)::numeric(12,2) AS sold,
                    COALESCE(o.cancelled, 0) AS cancelled,
                    COALESCE(c.collected, 0)::numeric(12,2) AS collected,
                    COALESCE(c.cash, 0)::numeric(12,2) AS cash, COALESCE(c.qr, 0)::numeric(12,2) AS qr
             FROM periods LEFT JOIN o USING (period) LEFT JOIN c USING (period)
             ORDER BY periods.period";
    }

    private static function salesRow(array $row): array
    {
        return [
            'orders' => (int) $row['orders'],
            'sold' => $row['sold'],
            'cancelled' => (int) $row['cancelled'],
            'collected' => $row['collected'],
            'cash' => $row['cash'],
            'qr' => $row['qr'],
        ];
    }

    /** Rango por días operativos; por defecto los últimos $defaultDays días hasta hoy. */
    private function range(array $query, int $defaultDays = 30): DateRange
    {
        $today = $this->finance->today();
        $from = (new DateTimeImmutable($today))->modify('-' . ($defaultDays - 1) . ' days')->format('Y-m-d');
        return DateRange::fromQuery($query, $from, $today);
    }

    private function row(string $sql, array $params = []): array
    {
        return $this->rows($sql, $params)[0];
    }

    private function rows(string $sql, array $params = []): array
    {
        $stmt = $this->db->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll();
    }
}
