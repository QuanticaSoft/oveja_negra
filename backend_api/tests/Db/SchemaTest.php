<?php

declare(strict_types=1);

/** Reglas que la BD debe garantizar aunque la API tenga un bug. Requiere migrate.sh dev. */
final class SchemaTest extends DbTestCase
{
    private const CHECK_VIOLATION = '23514';
    private const UNIQUE_VIOLATION = '23505';
    private const RESTRICT_VIOLATION = '23001';

    public function testConexionUsaNuestroSchemaYZonaHoraria(): void
    {
        $this->assertSame('oveja_negra', $this->scalar('SELECT current_schema()'));
        $this->assertSame('America/La_Paz', $this->scalar("SELECT current_setting('TimeZone')"));
    }

    public function testTodasLasMigracionesAplicadas(): void
    {
        $files = glob(dirname(__DIR__, 2) . '/sql/[0-9][0-9][0-9]_*.sql');
        $this->assertSame(count($files), (int) $this->scalar('SELECT count(*) FROM schema_migrations'));
    }

    public function testSemillaDeRolesYPermisos(): void
    {
        $countFor = fn (string $role): int => (int) $this->scalar(
            'SELECT count(*) FROM role_permissions rp JOIN roles r ON r.id = rp.role_id WHERE r.code = ?', [$role]);

        $this->assertSame((int) $this->scalar('SELECT count(*) FROM permissions'), $countFor('ADMIN'));
        $this->assertSame(7, $countFor('CAJERO'));
        $this->assertSame(16, $countFor('ENCARGADO'));
        $this->assertSame(0, (int) $this->scalar(
            "SELECT count(*) FROM role_permissions rp JOIN roles r ON r.id = rp.role_id
             JOIN permissions p ON p.id = rp.permission_id
             WHERE r.code = 'CAJERO' AND p.code IN ('orders.cancel', 'payments.void')"));
    }

    public function testDiaOperativoConCorteALas4(): void
    {
        $this->assertSame('2026-11-07', $this->scalar("SELECT business_date_of('2026-11-08 01:30-04')::text"));
        $this->assertSame('2026-11-08', $this->scalar("SELECT business_date_of('2026-11-08 04:00-04')::text"));
    }

    public function testPedidoRechazaDescuentoMayorAlSubtotalYTotalIncorrecto(): void
    {
        $userId = $this->createUser();
        $insert = "INSERT INTO orders (business_date, daily_number, channel, subtotal, discount, total, created_by)
                   VALUES ('2026-11-07', 1, 'LOCAL', ?, ?, ?, ?)";
        $this->assertDbRejects(self::CHECK_VIOLATION, $insert, ['50.00', '60.00', '-10.00', $userId]);
        $this->assertDbRejects(self::CHECK_VIOLATION, $insert, ['50.00', '5.00', '50.00', $userId]);
    }

    public function testPedidoNoSeBorra(): void
    {
        $orderId = $this->createOrder($this->createUser());
        $this->assertDbRejects(self::RESTRICT_VIOLATION, 'DELETE FROM orders WHERE id = ?', [$orderId]);
    }

    public function testItemsBloqueadosTrasElPago(): void
    {
        $userId = $this->createUser();
        $orderId = $this->createOrder($userId);
        $productId = $this->createProduct();
        $insertItem = "INSERT INTO order_items (order_id, product_id, product_name_snapshot, unit_price_snapshot, quantity, line_total)
                       VALUES (?, ?, 'Clásica', '35.00', 1, '35.00')";
        $this->db->prepare($insertItem)->execute([$orderId, $productId]);

        $this->db->prepare("INSERT INTO payments (order_id, method, amount, received_by) VALUES (?, 'EFECTIVO', '35.00', ?)")
            ->execute([$orderId, $userId]);

        $this->assertDbRejects(self::RESTRICT_VIOLATION, $insertItem, [$orderId, $productId]);
        $this->assertDbRejects(self::RESTRICT_VIOLATION, 'DELETE FROM order_items WHERE order_id = ?', [$orderId]);
    }

    public function testStockNoPuedeSerNegativo(): void
    {
        $categoryId = $this->scalar("INSERT INTO ingredient_categories (name) VALUES ('Carnes test') RETURNING id");
        $this->assertDbRejects(self::CHECK_VIOLATION,
            "INSERT INTO ingredients (name, category_id, unit_id, current_stock)
             VALUES ('Carne test', ?, (SELECT id FROM units WHERE code = 'kg'), '-1')", [$categoryId]);
    }

    public function testTransaccionFinancieraNoSeDuplicaNiSeModifica(): void
    {
        $userId = $this->createUser();
        $insert = "INSERT INTO financial_transactions (type, category, description, amount, business_date, source_type, source_id, created_by)
                   VALUES ('INGRESO', 'VENTAS', 'Pedido #1', '35.00', '2026-11-07', 'PAYMENT', 999, ?) RETURNING id";
        $id = $this->scalar($insert, [$userId]);

        $this->assertDbRejects(self::UNIQUE_VIOLATION, $insert, [$userId]);
        $this->assertDbRejects(self::RESTRICT_VIOLATION, "UPDATE financial_transactions SET amount = '1.00' WHERE id = ?", [$id]);
        $this->assertDbRejects(self::RESTRICT_VIOLATION, 'DELETE FROM financial_transactions WHERE id = ?', [$id]);
    }

    public function testEntradaDeCompraExigeOrigenYCantidadPositiva(): void
    {
        $userId = $this->createUser();
        $categoryId = $this->scalar("INSERT INTO ingredient_categories (name) VALUES ('Panadería test') RETURNING id");
        $ingredientId = $this->scalar(
            "INSERT INTO ingredients (name, category_id, unit_id) VALUES ('Pan test', ?, (SELECT id FROM units WHERE code = 'unidad')) RETURNING id",
            [$categoryId]);

        $this->assertDbRejects(self::CHECK_VIOLATION,
            "INSERT INTO inventory_movements (ingredient_id, type, quantity, stock_after, created_by)
             VALUES (?, 'ENTRADA_COMPRA', '10', '10', ?)", [$ingredientId, $userId]);
        $this->assertDbRejects(self::CHECK_VIOLATION,
            "INSERT INTO inventory_movements (ingredient_id, type, quantity, stock_after, source_type, source_id, created_by)
             VALUES (?, 'ENTRADA_COMPRA', '-10', '0', 'PURCHASE_ITEM', 1, ?)", [$ingredientId, $userId]);
    }

    private function createUser(): int
    {
        return (int) $this->scalar(
            "INSERT INTO users (username, full_name, password_hash, role_id)
             SELECT 'test.user', 'Usuario de prueba', 'x', id FROM roles WHERE code = 'ADMIN' RETURNING id");
    }

    private function createOrder(int $userId): int
    {
        return (int) $this->scalar(
            "INSERT INTO orders (business_date, daily_number, channel, subtotal, total, created_by)
             VALUES ('2026-11-07', 1, 'LOCAL', '35.00', '35.00', ?) RETURNING id", [$userId]);
    }

    private function createProduct(): int
    {
        $categoryId = $this->scalar("INSERT INTO categories (name) VALUES ('Hamburguesas test') RETURNING id");
        return (int) $this->scalar(
            "INSERT INTO products (category_id, name, price) VALUES (?, 'Clásica', '35.00') RETURNING id", [$categoryId]);
    }
}
