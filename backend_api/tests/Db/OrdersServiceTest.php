<?php

declare(strict_types=1);

final class OrdersServiceTest extends DbTestCase
{
    private AuthUser $admin;
    private AuthUser $cashier;
    private OrdersService $orders;
    private PaymentsService $payments;
    private int $burger;
    private int $fries;

    public function setUp(): void
    {
        parent::setUp();
        $this->admin = $this->authUser($this->insertUser('ADMIN', 'admin.test'));
        $this->cashier = $this->authUser($this->insertUser('CAJERO', 'cajero.test'));
        $this->orders = new OrdersService($this->db, $this->cashier);
        $this->payments = new PaymentsService($this->db, $this->cashier);
        $categoryId = (int) $this->scalar("INSERT INTO categories (name) VALUES ('Pedidos Test') RETURNING id");
        $this->burger = $this->insertProduct($categoryId, 'Hamburguesa Test', '25.50');
        $this->fries = $this->insertProduct($categoryId, 'Papas Test', '12.00');
    }

    public function testCreaPedidoConPreciosDeLaBdYSnapshot(): void
    {
        $order = $this->create(['channel' => 'LOCAL', 'items' => [
            ['product_id' => $this->burger, 'quantity' => 2, 'price' => '1.00'],
            ['product_id' => $this->fries, 'quantity' => 1],
        ], 'customer_phone' => '+591 7000-0000'])['order'];

        $this->assertSame(['63.00', '0.00', '63.00', '0.00', '63.00'],
            [$order['subtotal'], $order['discount'], $order['total'], $order['paid'], $order['balance']]);
        $this->assertSame(['25.50', '51.00'], [$order['items'][0]['unit_price'], $order['items'][0]['line_total']]);
        $this->assertSame(['PENDIENTE', 'SIN_PAGAR', '+59170000000'],
            [$order['status'], $order['payment_status'], $order['customer_phone']]);
        $this->assertSame(1, (int) $this->scalar("SELECT count(*) FROM audit_logs WHERE entity = 'orders' AND entity_id = ? AND action = 'create'", [$order['id']]));

        // Cambiar el precio después no altera el pedido.
        $this->db->prepare("UPDATE products SET price = '99.00' WHERE id = ?")->execute([$this->burger]);
        $this->assertSame('25.50', $this->orders->get($order['id'])['items'][0]['unit_price']);
    }

    public function testNumeroDiarioCorrelativoYSeparadoPorDia(): void
    {
        $first = $this->create()['order'];
        $second = $this->create()['order'];
        $this->assertSame($first['number'] + 1, $second['number']);

        // Los pedidos de otro día operativo no afectan la numeración de hoy (rollback al final del test).
        $this->db->prepare('UPDATE orders SET business_date = business_date - 3650 WHERE business_date = ?')
            ->execute([$first['business_date']]);
        $this->assertSame(1, $this->create()['order']['number']);

        // El día operativo usa la hora de corte configurada.
        $lateCutoff = new OrdersService($this->db, $this->cashier, '24:00');
        $order = $lateCutoff->create(['channel' => 'LOCAL', 'items' => [['product_id' => $this->burger, 'quantity' => 1]]], self::uuid())['order'];
        $this->assertSame($this->scalar("SELECT business_date_of(now(), '24:00')::text"), $order['business_date']);
    }

    public function testValidaciones(): void
    {
        $this->assertApiError('IDEMPOTENCY_KEY_REQUIRED', 400, fn () => $this->orders->create(['channel' => 'LOCAL'], null));
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->orders->create(['channel' => 'LOCAL'], 'no-es-uuid'));
        $invalid = [
            ['channel' => 'DELIVERY', 'items' => [['product_id' => $this->burger, 'quantity' => 1]]],
            ['channel' => 'LOCAL', 'items' => []],
            ['channel' => 'LOCAL', 'items' => [['product_id' => $this->burger, 'quantity' => 0]]],
            ['channel' => 'LOCAL', 'items' => [['product_id' => $this->burger, 'quantity' => 100]]],
            ['channel' => 'LOCAL', 'items' => [['product_id' => $this->burger, 'quantity' => 1], ['product_id' => $this->burger, 'quantity' => 2]]],
            ['channel' => 'LOCAL', 'items' => [['product_id' => 999999999, 'quantity' => 1]]],
            ['channel' => 'LOCAL', 'items' => [['product_id' => $this->burger, 'quantity' => 1]], 'customer_phone' => 'abc'],
            ['channel' => 'LOCAL', 'items' => [['product_id' => $this->burger, 'quantity' => 1]], 'payments' => [['method' => 'TARJETA', 'amount' => 5]]],
        ];
        foreach ($invalid as $input) {
            $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->orders->create($input, self::uuid()));
        }
        $this->assertSame(0, (int) $this->scalar('SELECT count(*) FROM orders WHERE created_by = ?', [$this->cashier->id]));

        foreach ([
            fn () => $this->orders->get(999999999),
            fn () => $this->orders->replaceItems(999999999, ['items' => [['product_id' => $this->burger, 'quantity' => 1]]]),
            fn () => $this->orders->changeStatus(999999999, ['status' => 'LISTO']),
            fn () => $this->adminOrders()->cancel(999999999, ['reason' => 'x']),
        ] as $call) {
            $this->assertApiError('NOT_FOUND', 404, $call);
        }
    }

    public function testProductoAgotadoOInactivoRechazado(): void
    {
        $this->db->prepare('UPDATE products SET is_available = false WHERE id = ?')->execute([$this->fries]);
        $e = $this->assertApiError('PRODUCT_UNAVAILABLE', 409, fn () => $this->create(['items' => [
            ['product_id' => $this->burger, 'quantity' => 1], ['product_id' => $this->fries, 'quantity' => 1]]]));
        $this->assertSame([['id' => $this->fries, 'name' => 'Papas Test']], $e->details['products']);
    }

    public function testDescuentoRequierePermisoYNoSuperaElSubtotal(): void
    {
        $order = $this->create(['discount' => '5.50'])['order'];
        $this->assertSame(['5.50', '20.00'], [$order['discount'], $order['total']]);
        $this->assertApiError('DISCOUNT_EXCEEDS_SUBTOTAL', 422, fn () => $this->create(['discount' => '25.51']));

        $this->db->exec("DELETE FROM role_permissions WHERE role_id = (SELECT id FROM roles WHERE code = 'CAJERO')
                         AND permission_id = (SELECT id FROM permissions WHERE code = 'orders.discount')");
        $this->orders = new OrdersService($this->db, $this->authUser($this->cashier->id));
        $this->assertApiError('FORBIDDEN', 403, fn () => $this->create(['discount' => '1']));
        $this->assertSame('0.00', $this->create(['discount' => 0])['order']['discount']);
    }

    public function testPedidoConPagosEnUnaTransaccion(): void
    {
        $order = $this->create(['payments' => [['method' => 'EFECTIVO', 'amount' => '20'], ['method' => 'QR', 'amount' => '5.50']]])['order'];
        $this->assertSame(['25.50', '0.00', 'PAGADO'], [$order['paid'], $order['balance'], $order['payment_status']]);
        $this->assertSame(2, count($order['payments']));
        $this->assertSame('25.50', $this->scalar(
            "SELECT sum(amount) FROM financial_transactions WHERE type = 'INGRESO' AND source_type = 'PAYMENT'
             AND source_id IN (SELECT id FROM payments WHERE order_id = ?)", [$order['id']]));

        // Si los pagos superan el total no queda nada: ni pedido, ni ítems, ni pagos.
        $before = (int) $this->scalar('SELECT count(*) FROM orders');
        $this->assertApiError('OVERPAYMENT', 422, fn () => $this->create(['payments' => [['method' => 'EFECTIVO', 'amount' => '30']]]));
        $this->assertSame($before, (int) $this->scalar('SELECT count(*) FROM orders'));
    }

    public function testReintentoConLaMismaClaveNoDuplica(): void
    {
        $key = self::uuid();
        $input = ['channel' => 'WHATSAPP', 'items' => [['product_id' => $this->burger, 'quantity' => 1]],
                  'payments' => [['method' => 'QR', 'amount' => '25.50']]];
        $first = $this->orders->create($input, $key);
        $retry = $this->orders->create($input, strtoupper($key));
        $this->assertSame([true, false], [$first['created'], $retry['created']]);
        $this->assertSame($first['order']['id'], $retry['order']['id']);
        $this->assertSame(1, (int) $this->scalar('SELECT count(*) FROM payments WHERE order_id = ?', [$first['order']['id']]));

        $other = $input;
        $other['items'][0]['quantity'] = 2;
        $this->assertApiError('IDEMPOTENCY_KEY_REUSED', 409, fn () => $this->orders->create($other, $key));
        $adminOrders = new OrdersService($this->db, $this->admin);
        $this->assertApiError('IDEMPOTENCY_KEY_REUSED', 409, fn () => $adminOrders->create($input, $key));
    }

    public function testPagosSinSobrepagoEIdempotentes(): void
    {
        $orderId = $this->create()['order']['id'];
        $key = self::uuid();
        $payment = $this->payments->create($orderId, ['method' => 'EFECTIVO', 'amount' => 10], $key);
        $this->assertSame([true, '10.00'], [$payment['created'], $payment['payment']['amount']]);
        $this->assertSame(false, $this->payments->create($orderId, ['method' => 'EFECTIVO', 'amount' => '10.00'], $key)['created']);
        $this->assertApiError('IDEMPOTENCY_KEY_REUSED', 409, fn () => $this->payments->create($orderId, ['method' => 'QR', 'amount' => 10], $key));

        $e = $this->assertApiError('OVERPAYMENT', 422, fn () => $this->payments->create($orderId, ['method' => 'QR', 'amount' => '15.51'], self::uuid()));
        $this->assertSame('15.50', $e->details['balance']);
        $this->payments->create($orderId, ['method' => 'QR', 'amount' => '15.50'], self::uuid());
        $this->assertSame('PAGADO', $this->orders->get($orderId)['payment_status']);
        $this->assertApiError('NOT_FOUND', 404, fn () => $this->payments->create(999999999, ['method' => 'QR', 'amount' => 1], self::uuid()));
    }

    public function testTransicionesDeEstado(): void
    {
        $orderId = $this->create()['order']['id'];
        $this->assertSame('EN_PREPARACION', $this->orders->changeStatus($orderId, ['status' => 'EN_PREPARACION'])['status']);
        $this->assertApiError('INVALID_TRANSITION', 409, fn () => $this->orders->changeStatus($orderId, ['status' => 'PENDIENTE']));
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->orders->changeStatus($orderId, ['status' => 'CANCELADO']));
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->orders->changeStatus($orderId, ['status' => 'X']));

        // Sin pago completo no se entrega; se puede saltar LISTO.
        $e = $this->assertApiError('UNPAID_ORDER', 422, fn () => $this->orders->changeStatus($orderId, ['status' => 'ENTREGADO']));
        $this->assertSame('25.50', $e->details['balance']);
        $this->payments->create($orderId, ['method' => 'EFECTIVO', 'amount' => '25.50'], self::uuid());
        $this->assertSame('ENTREGADO', $this->orders->changeStatus($orderId, ['status' => 'ENTREGADO'])['status']);
        $this->assertSame(2, (int) $this->scalar("SELECT count(*) FROM audit_logs WHERE entity = 'orders' AND entity_id = ? AND action = 'change_status'", [$orderId]));

        // Un pedido de total 0 (descuento completo) se puede entregar sin pagos.
        $free = $this->create(['discount' => '25.50'])['order'];
        $this->assertSame('PAGADO', $free['payment_status']);
        $this->assertSame('ENTREGADO', $this->orders->changeStatus($free['id'], ['status' => 'ENTREGADO'])['status']);
    }

    public function testCancelarAnulaPagosYElIngresoNetoEsCero(): void
    {
        $orderId = $this->create(['payments' => [['method' => 'EFECTIVO', 'amount' => '10'], ['method' => 'QR', 'amount' => '15.50']]])['order']['id'];
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->adminOrders()->cancel($orderId, ['reason' => ' ']));

        $cancelled = $this->adminOrders()->cancel($orderId, ['reason' => 'Cliente no vino']);
        $this->assertSame(['CANCELADO', '0.00', 'Cliente no vino'],
            [$cancelled['status'], $cancelled['paid'], $cancelled['cancelled']['reason']]);
        $this->assertSame(['ANULADO', 'ANULADO'], array_column($cancelled['payments'], 'status'));
        $this->assertSame('0.00', $this->scalar(
            "SELECT sum(CASE type WHEN 'INGRESO' THEN amount ELSE -amount END) FROM financial_transactions
             WHERE source_type = 'PAYMENT' AND source_id IN (SELECT id FROM payments WHERE order_id = ?)", [$orderId]));
        $this->assertSame(2, (int) $this->scalar(
            "SELECT count(*) FROM financial_transactions WHERE is_reversal AND reverses_id IS NOT NULL
             AND source_id IN (SELECT id FROM payments WHERE order_id = ?)", [$orderId]));

        $this->assertApiError('ORDER_CANCELLED', 409, fn () => $this->adminOrders()->cancel($orderId, ['reason' => 'otra vez']));
        $this->assertApiError('ORDER_CANCELLED', 409, fn () => $this->orders->changeStatus($orderId, ['status' => 'LISTO']));
        $this->assertApiError('ORDER_CANCELLED', 409, fn () => $this->payments->create($orderId, ['method' => 'QR', 'amount' => 1], self::uuid()));
    }

    public function testPedidoEntregadoNoSeCancela(): void
    {
        $orderId = $this->create(['payments' => [['method' => 'QR', 'amount' => '25.50']]])['order']['id'];
        $this->orders->changeStatus($orderId, ['status' => 'ENTREGADO']);
        $this->assertApiError('INVALID_TRANSITION', 409, fn () => $this->adminOrders()->cancel($orderId, ['reason' => 'Error']));
    }

    public function testAnularPagoCreaReversoYDesbloqueaItems(): void
    {
        $orderId = $this->create()['order']['id'];
        $paymentId = $this->payments->create($orderId, ['method' => 'QR', 'amount' => 5], self::uuid())['payment']['id'];
        $newItems = ['items' => [['product_id' => $this->fries, 'quantity' => 3]]];
        $this->assertApiError('ORDER_LOCKED', 409, fn () => $this->orders->replaceItems($orderId, $newItems));

        $adminPayments = new PaymentsService($this->db, $this->admin);
        $voided = $adminPayments->void($paymentId, ['reason' => 'QR no llegó']);
        $this->assertSame(['ANULADO', 'QR no llegó', $this->admin->id], [$voided['status'], $voided['voided']['reason'], $voided['voided']['by']['id']]);
        $this->assertSame('EGRESO', $this->scalar("SELECT type FROM financial_transactions WHERE source_type = 'PAYMENT' AND source_id = ? AND is_reversal", [$paymentId]));
        $this->assertApiError('PAYMENT_ALREADY_VOIDED', 409, fn () => $adminPayments->void($paymentId, ['reason' => 'otra vez']));

        $order = $this->orders->replaceItems($orderId, $newItems);
        $this->assertSame(['36.00', 1, 'Papas Test'], [$order['total'], count($order['items']), $order['items'][0]['name']]);
        $this->assertApiError('NOT_FOUND', 404, fn () => $adminPayments->void(999999999, ['reason' => 'x']));
    }

    public function testEditarItemsRespetaDescuentoYEstado(): void
    {
        $orderId = $this->create(['discount' => '20'])['order']['id'];
        $this->assertApiError('DISCOUNT_EXCEEDS_SUBTOTAL', 422,
            fn () => $this->orders->replaceItems($orderId, ['items' => [['product_id' => $this->fries, 'quantity' => 1]]]));
        $order = $this->orders->replaceItems($orderId, ['items' => [['product_id' => $this->fries, 'quantity' => 1]], 'discount' => '2']);
        $this->assertSame(['12.00', '2.00', '10.00'], [$order['subtotal'], $order['discount'], $order['total']]);
        $this->assertSame(1, (int) $this->scalar("SELECT count(*) FROM audit_logs WHERE entity = 'orders' AND entity_id = ? AND action = 'replace_items'", [$orderId]));

        $this->orders->changeStatus($orderId, ['status' => 'EN_PREPARACION']);
        $this->assertApiError('ORDER_LOCKED', 409,
            fn () => $this->orders->replaceItems($orderId, ['items' => [['product_id' => $this->burger, 'quantity' => 1]]]));
    }

    public function testListadoPorDiaEstadoYCanal(): void
    {
        $local = $this->create()['order'];
        $whatsapp = $this->create(['channel' => 'WHATSAPP'])['order'];
        $this->orders->changeStatus($whatsapp['id'], ['status' => 'LISTO']);

        $ids = fn (array $query): array => array_column($this->orders->list($query + ['per_page' => '100'])['data'], 'id');
        $this->assertTrue(in_array($local['id'], $ids([]), true), 'Por defecto lista el día de hoy');
        $this->assertSame([$whatsapp['id']], array_values(array_intersect($ids(['status' => 'listo,ENTREGADO']), [$local['id'], $whatsapp['id']])));
        $this->assertSame([$whatsapp['id']], array_values(array_intersect($ids(['channel' => 'WHATSAPP']), [$local['id'], $whatsapp['id']])));
        $this->assertSame([$local['id'], $whatsapp['id']], array_values(array_intersect($ids(['sort' => 'asc']), [$local['id'], $whatsapp['id']])));
        $this->assertSame(1, count($this->orders->list(['status' => 'PENDIENTE', 'per_page' => '100'])['data'][0]['items']));
        $this->assertSame([], $ids(['from' => '2020-01-01', 'to' => '2020-01-31']));

        foreach ([['from' => '2026-02-30'], ['from' => '2026-11-08', 'to' => '2026-11-01'], ['from' => '2026-01-01', 'to' => '2026-06-01'],
                  ['status' => 'ABIERTO'], ['channel' => 'X'], ['sort' => 'up']] as $query) {
            $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->orders->list($query));
        }
    }

    private function adminOrders(): OrdersService
    {
        return new OrdersService($this->db, $this->admin);
    }

    /** Pedido LOCAL de una hamburguesa (25.50) con los campos que se sobrescriban. */
    private function create(array $overrides = []): array
    {
        return $this->orders->create($overrides + [
            'channel' => 'LOCAL',
            'items' => [['product_id' => $this->burger, 'quantity' => 1]],
        ], self::uuid());
    }

    private function insertProduct(int $categoryId, string $name, string $price): int
    {
        return (int) $this->scalar('INSERT INTO products (category_id, name, price) VALUES (?, ?, ?) RETURNING id', [$categoryId, $name, $price]);
    }
}
