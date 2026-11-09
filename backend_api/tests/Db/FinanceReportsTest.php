<?php

declare(strict_types=1);

/**
 * Compras y gastos usan fechas de 2001 (aisladas de los datos reales de dev). Los pedidos y cobros
 * siempre caen en el día operativo de hoy, así que para ellos se comparan diferencias antes/después.
 */
final class FinanceReportsTest extends DbTestCase
{
    private AuthUser $admin;
    private AuthUser $manager;
    private AuthUser $cashier;
    private FinanceService $finance;
    private ReportsService $reports;
    private ExpensesService $expenses;
    private PurchasesService $purchases;
    private int $product;
    private int $ingredient;
    private int $expenseCategory;
    private string $today;

    public function setUp(): void
    {
        parent::setUp();
        $this->admin = $this->authUser($this->insertUser('ADMIN', 'admin.test'));
        $this->manager = $this->authUser($this->insertUser('ENCARGADO', 'encargado.test'));
        $this->cashier = $this->authUser($this->insertUser('CAJERO', 'cajero.test'));
        $this->finance = new FinanceService($this->db);
        $this->reports = new ReportsService($this->db);
        $this->expenses = new ExpensesService($this->db, $this->manager);
        $this->purchases = new PurchasesService($this->db, $this->manager);
        $this->today = $this->finance->today();

        $categoryId = (int) $this->scalar("INSERT INTO categories (name) VALUES ('Reportes Test') RETURNING id");
        $this->product = (int) $this->scalar("INSERT INTO products (category_id, name, price) VALUES (?, 'Doble Reporte Test', '25.50') RETURNING id", [$categoryId]);
        $ingredients = new IngredientsService($this->db, $this->manager);
        $ingredientCategory = $ingredients->createCategory(['name' => 'Reportes Test'])['id'];
        $this->ingredient = $ingredients->create(['name' => 'Carne Reporte Test', 'category_id' => $ingredientCategory,
            'unit_id' => array_column($ingredients->units(), 'id', 'code')['kg']])['id'];
        $this->expenseCategory = (new ExpenseCategoriesService($this->db, $this->admin))->create(['name' => 'Alquiler Test'])['id'];
    }

    public function testCuadreVentasMenosComprasMenosGastos(): void
    {
        $before = $this->finance->summary($this->today, $this->today);
        $dashboardBefore = $this->reports->dashboard([]);

        // Pedido pagado mixto (51.00), pedido pagado y cancelado (neto 0) y pedido sin pagar (vendido, no cobrado).
        $this->order(2, [['EFECTIVO', '30'], ['QR', '21']]);
        $cancelled = $this->order(1, [['QR', '25.50']]);
        (new OrdersService($this->db, $this->admin))->cancel($cancelled, ['reason' => 'Prueba']);
        $this->order(1);
        // Compra de 100 y otra de 40 anulada; gasto de 15 y otro de 7 anulado.
        $this->buy($this->today, '100');
        $this->purchases->void($this->buy($this->today, '40'), ['reason' => 'Duplicada']);
        $this->expense($this->today, '15');
        $this->expenses->void($this->expense($this->today, '7'), ['reason' => 'Error']);

        $after = $this->finance->summary($this->today, $this->today);
        $delta = fn (callable $pick): string => Money::fromCents(Money::toCents($pick($after)) - Money::toCents($pick($before)));
        $this->assertSame('51.00', $delta(fn ($s) => $s['sales_collected']['total']));
        $this->assertSame('30.00', $delta(fn ($s) => $s['sales_collected']['cash']));
        $this->assertSame('21.00', $delta(fn ($s) => $s['sales_collected']['qr']));
        $this->assertSame('100.00', $delta(fn ($s) => $s['purchases']));
        $this->assertSame('15.00', $delta(fn ($s) => $s['expenses']['total']));
        $this->assertSame('-64.00', $delta(fn ($s) => $s['operating_result']));

        // El resultado es exactamente ventas − compras − gastos y coincide con el libro.
        $this->assertSame(Money::toCents($after['operating_result']),
            Money::toCents($after['sales_collected']['total']) - Money::toCents($after['purchases']) - Money::toCents($after['expenses']['total']));
        $this->assertSame($after['operating_result'], $this->scalar(
            "SELECT COALESCE(sum(CASE type WHEN 'INGRESO' THEN amount ELSE -amount END), 0)::numeric(12,2)
             FROM financial_transactions WHERE business_date = ?", [$this->today]));

        $dashboard = $this->reports->dashboard([]);
        $this->assertSame(2, $dashboard['orders']['count'] - $dashboardBefore['orders']['count']);
        $this->assertSame(1, $dashboard['orders']['cancelled'] - $dashboardBefore['orders']['cancelled']);
        $this->assertSame('76.50', Money::fromCents(Money::toCents($dashboard['orders']['sold']) - Money::toCents($dashboardBefore['orders']['sold'])));
        $this->assertSame(1, $dashboard['orders']['by_status']['CANCELADO'] - $dashboardBefore['orders']['by_status']['CANCELADO']);
        $this->assertSame($after, $dashboard['finance']);
    }

    public function testGastosIdempotentesYAnulacionEnSuFecha(): void
    {
        $key = self::uuid();
        $input = ['expense_date' => '2001-05-10', 'category_id' => $this->expenseCategory, 'description' => 'Alquiler mayo',
                  'amount' => '1500', 'payment_method' => 'QR'];
        $first = $this->expenses->create($input, $key);
        $this->assertSame([true, '1500.00', 'Alquiler Test'], [$first['created'], $first['expense']['amount'], $first['expense']['category']['name']]);
        $this->assertSame(false, $this->expenses->create($input, $key)['created']);
        $this->assertApiError('IDEMPOTENCY_KEY_REUSED', 409, fn () => $this->expenses->create(['amount' => '1600'] + $input, $key));

        $voided = $this->expenses->void($first['expense']['id'], ['reason' => 'Era de abril']);
        $this->assertSame(['ANULADO', 'Era de abril'], [$voided['status'], $voided['voided']['reason']]);
        $this->assertSame([['EGRESO', '2001-05-10'], ['INGRESO', '2001-05-10']], array_map('array_values', $this->db->query(
            "SELECT type, business_date::text FROM financial_transactions WHERE source_type = 'EXPENSE' AND source_id = {$first['expense']['id']} ORDER BY id")->fetchAll()));
        $this->assertApiError('EXPENSE_ALREADY_VOIDED', 409, fn () => $this->expenses->void($first['expense']['id'], ['reason' => 'x']));
        $this->assertSame('0.00', $this->finance->summary('2001-05-10', '2001-05-10')['expenses']['total']);

        $list = $this->expenses->list(['from' => '2001-05-01', 'to' => '2001-05-31', 'status' => 'ANULADO']);
        $this->assertSame([$first['expense']['id']], array_column($list['data'], 'id'));

        $tomorrow = (new DateTimeImmutable($this->scalar('SELECT current_date::text')))->modify('+1 day')->format('Y-m-d');
        foreach ([['expense_date' => $tomorrow], ['amount' => 0], ['description' => ''], ['payment_method' => 'TARJETA'], ['category_id' => 999999999]] as $override) {
            $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->expenses->create($override + $input, self::uuid()));
        }
        (new ExpenseCategoriesService($this->db, $this->admin))->update($this->expenseCategory, ['is_active' => false]);
        $this->assertApiError('EXPENSE_CATEGORY_INACTIVE', 409, fn () => $this->expenses->create($input, self::uuid()));
    }

    public function testCategoriasDeGasto(): void
    {
        $categories = new ExpenseCategoriesService($this->db, $this->admin);
        $this->assertApiError('EXPENSE_CATEGORY_NAME_TAKEN', 409, fn () => $categories->create(['name' => 'ALQUILER test']));
        $this->assertSame(['Alquiler Local Test', false], array_values(array_intersect_key(
            $categories->update($this->expenseCategory, ['name' => 'Alquiler Local Test', 'is_active' => false]), array_flip(['name', 'is_active']))));
        $this->assertTrue(!in_array($this->expenseCategory, array_column($categories->list(['active' => 'true']), 'id'), true));
        $this->assertApiError('NOT_FOUND', 404, fn () => $categories->update(999999999, ['name' => 'X']));
    }

    public function testReportesDeComprasGastosYFlujo(): void
    {
        $supplier = (new SuppliersService($this->db, $this->manager))->create(['name' => 'Frigorífico Reporte Test'])['id'];
        $this->buy('2001-06-01', '60', '2', $supplier);       // 120.00
        $this->buy('2001-06-03', '70', '1');                  // 70.00, sin proveedor
        $this->purchases->void($this->buy('2001-06-03', '99', '1'), ['reason' => 'Error']);
        $this->expense('2001-06-01', '30');
        $this->expense('2001-06-02', '20');

        $report = $this->reports->purchases(['from' => '2001-06-01', 'to' => '2001-06-03']);
        $this->assertSame([2, '190.00'], [$report['purchases'], $report['total']]);
        $this->assertSame([['Frigorífico Reporte Test', '120.00'], [null, '70.00']],
            array_map(static fn (array $row): array => [$row['supplier']['name'] ?? null, $row['total']], $report['by_supplier']));
        // 190 / 3 kg = 63.33
        $this->assertSame(['3.000', '190.00', '63.33'], array_values(array_intersect_key($report['by_ingredient'][0], array_flip(['quantity', 'total', 'average_unit_price']))));

        $expenses = $this->reports->expensesByCategory(['from' => '2001-06-01', 'to' => '2001-06-03']);
        $this->assertSame(['50.00', 2], [$expenses['total'], $expenses['categories'][0]['expenses']]);

        // Flujo: la compra anulada entra y sale el mismo día (neto 0); el día 2 solo tiene el gasto.
        $flow = $this->reports->financeMovements(['from' => '2001-06-01', 'to' => '2001-06-04']);
        $this->assertSame([
            ['date' => '2001-06-01', 'income' => '0.00', 'outcome' => '150.00', 'net' => '-150.00', 'cumulative' => '-150.00'],
            ['date' => '2001-06-02', 'income' => '0.00', 'outcome' => '20.00', 'net' => '-20.00', 'cumulative' => '-170.00'],
            ['date' => '2001-06-03', 'income' => '99.00', 'outcome' => '169.00', 'net' => '-70.00', 'cumulative' => '-240.00'],
            ['date' => '2001-06-04', 'income' => '0.00', 'outcome' => '0.00', 'net' => '0.00', 'cumulative' => '-240.00'],
        ], $flow['days']);

        $summary = $this->finance->summary('2001-06-01', '2001-06-04');
        $this->assertSame(['190.00', '50.00', '-240.00'], [$summary['purchases'], $summary['expenses']['total'], $summary['operating_result']]);
        $this->assertSame([['Alquiler Test', '50.00']], array_map(static fn (array $row): array => [$row['category']['name'], $row['total']], $summary['expenses']['by_category']));
    }

    public function testVentasDiariasMensualesYProductosTop(): void
    {
        $from = (new DateTimeImmutable($this->today))->modify('-2 days')->format('Y-m-d');
        $dailyBefore = $this->reports->salesDaily(['from' => $from, 'to' => $this->today]);
        $monthlyBefore = $this->reports->salesMonthly([]);

        $this->order(3, [['EFECTIVO', '76.50']]);
        $cancelled = $this->order(2);
        (new OrdersService($this->db, $this->admin))->cancel($cancelled, ['reason' => 'Prueba']);

        $daily = $this->reports->salesDaily(['from' => $from, 'to' => $this->today]);
        $this->assertSame([$from, $this->today], [$daily[0]['date'], $daily[2]['date']]);
        $this->assertSame(3, count($daily));
        $todayDelta = self::delta($daily[2], $dailyBefore[2]);
        $this->assertSame(['orders' => 1, 'sold' => '76.50', 'cancelled' => 1, 'collected' => '76.50', 'cash' => '76.50', 'qr' => '0.00'], $todayDelta);

        $monthly = $this->reports->salesMonthly([]);
        $month = (int) substr($this->today, 5, 2) - 1;
        $this->assertSame([12, substr($this->today, 0, 7)], [count($monthly['months']), $monthly['months'][$month]['month']]);
        $this->assertSame('76.50', self::delta($monthly['months'][$month], $monthlyBefore['months'][$month])['sold']);
        $this->assertSame('0.00', $this->reports->salesMonthly(['year' => '2001'])['months'][0]['sold']);

        $mine = array_values(array_filter($this->reports->topProductsReport(['limit' => '50'])['products'],
            fn (array $row): bool => $row['product']['id'] === $this->product));
        $this->assertSame([3, '76.50'], [$mine[0]['quantity'], $mine[0]['total']], 'Lo cancelado no cuenta');

        foreach ([fn () => $this->reports->topProductsReport(['limit' => '51']),
                  fn () => $this->reports->salesMonthly(['year' => '1999']),
                  fn () => $this->reports->salesDaily(['from' => '2026-01-01', 'to' => '2026-06-01']),
                  fn () => $this->finance->transactions(['type' => 'OTRO'])] as $call) {
            $this->assertApiError('VALIDATION_ERROR', 400, $call);
        }
    }

    public function testLibroFinancieroConOrigenYReverso(): void
    {
        $this->purchases->void($this->buy('2001-07-01', '10'), ['reason' => 'x']);
        $rows = $this->finance->transactions(['from' => '2001-07-01', 'to' => '2001-07-01'])['data'];
        $this->assertSame([['INGRESO', true], ['EGRESO', false]], array_map(static fn (array $row): array => [$row['type'], $row['is_reversal']], $rows));
        $this->assertSame([$rows[1]['id'], 'PURCHASE'], [$rows[0]['reverses_id'], $rows[0]['source']['type']]);
        $this->assertSame(1, $this->finance->transactions(['from' => '2001-07-01', 'to' => '2001-07-01', 'type' => 'EGRESO'])['meta']['total']);
        $this->assertSame(0, $this->finance->transactions(['from' => '2001-07-01', 'to' => '2001-07-01', 'category' => 'VENTA'])['meta']['total']);
    }

    /** Pedido LOCAL de $quantity unidades del producto de prueba (25.50) con pagos opcionales. */
    private function order(int $quantity, array $payments = []): int
    {
        return (new OrdersService($this->db, $this->cashier))->create([
            'channel' => 'LOCAL',
            'items' => [['product_id' => $this->product, 'quantity' => $quantity]],
            'payments' => array_map(static fn (array $p): array => ['method' => $p[0], 'amount' => $p[1]], $payments),
        ], self::uuid())['order']['id'];
    }

    private function buy(string $date, string $unitPrice, string $quantity = '1', ?int $supplierId = null): int
    {
        return $this->purchases->create([
            'purchase_date' => $date, 'supplier_id' => $supplierId, 'payment_method' => 'EFECTIVO',
            'items' => [['ingredient_id' => $this->ingredient, 'quantity' => $quantity, 'unit_price' => $unitPrice]],
        ], self::uuid())['purchase']['id'];
    }

    private function expense(string $date, string $amount): int
    {
        return $this->expenses->create(['expense_date' => $date, 'category_id' => $this->expenseCategory,
            'description' => 'Gasto test', 'amount' => $amount, 'payment_method' => 'EFECTIVO'], self::uuid())['expense']['id'];
    }

    /** Diferencia campo a campo entre dos renglones de reporte de ventas. */
    private static function delta(array $after, array $before): array
    {
        $delta = [];
        foreach (['orders', 'sold', 'cancelled', 'collected', 'cash', 'qr'] as $field) {
            $delta[$field] = is_int($after[$field])
                ? $after[$field] - $before[$field]
                : Money::fromCents(Money::toCents($after[$field]) - Money::toCents($before[$field]));
        }
        return $delta;
    }
}
