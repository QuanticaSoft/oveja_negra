<?php

declare(strict_types=1);

final class PurchasingInventoryTest extends DbTestCase
{
    private AuthUser $manager;
    private IngredientsService $ingredients;
    private PurchasesService $purchases;
    private InventoryService $inventory;
    private int $categoryId;
    private int $kg;
    private int $unit;
    private int $beef;
    private int $buns;

    public function setUp(): void
    {
        parent::setUp();
        $this->manager = $this->authUser($this->insertUser('ENCARGADO', 'encargado.test'));
        $this->ingredients = new IngredientsService($this->db, $this->manager);
        $this->purchases = new PurchasesService($this->db, $this->manager);
        $this->inventory = new InventoryService($this->db, $this->manager);
        $this->categoryId = $this->ingredients->createCategory(['name' => 'Carnes Test'])['id'];
        $units = array_column($this->ingredients->units(), 'id', 'code');
        [$this->kg, $this->unit] = [$units['kg'], $units['unidad']];
        $this->beef = $this->ingredient('Carne Test', $this->kg, '2');
        $this->buns = $this->ingredient('Pan Test', $this->unit);
    }

    public function testCompraSumaStockCostoPromedioYEgresoEnSuFecha(): void
    {
        $first = $this->buy([[$this->beef, '2.500', '60.00'], [$this->buns, 24, '1.50']], date: '2026-10-01');
        $this->assertSame(['186.00', 'CONFIRMADA', 2], [$first['total'], $first['status'], count($first['items'])]);
        $this->assertSame(['2.500', '60.0000'], $this->stockAndCost($this->beef));
        $this->assertSame(['24.000', '1.5000'], $this->stockAndCost($this->buns));

        // (2.5·60 + 1.5·70) / 4 = 63.75
        $this->buy([[$this->beef, 1.5, 70]]);
        $this->assertSame(['4.000', '63.7500'], $this->stockAndCost($this->beef));

        $this->assertSame(['EGRESO', 'COMPRA_INSUMOS', '186.00', '2026-10-01'], array_values($this->db->query(
            "SELECT type, category, amount, business_date::text FROM financial_transactions
             WHERE source_type = 'PURCHASE' AND source_id = {$first['id']}")->fetch()));
        $this->assertSame(2, (int) $this->scalar(
            "SELECT count(*) FROM inventory_movements WHERE type = 'ENTRADA_COMPRA' AND source_type = 'PURCHASE_ITEM'
             AND source_id IN (SELECT id FROM purchase_items WHERE purchase_id = ?)", [$first['id']]));
    }

    public function testLineasSeRedondeanComoEnLaBd(): void
    {
        // 0.333 · 10.05 = 3.34665 → 3.35 (el CHECK de purchase_items lo verifica)
        $purchase = $this->buy([[$this->beef, '0.333', '10.05'], [$this->buns, 3, '0']]);
        $this->assertSame(['3.35', '0.00', '3.35'], [$purchase['items'][0]['line_total'], $purchase['items'][1]['line_total'], $purchase['total']]);
        $this->assertApiError('PURCHASE_TOTAL_ZERO', 422, fn () => $this->buy([[$this->buns, 1, 0]]));
    }

    public function testValidacionesDeCompra(): void
    {
        $this->assertApiError('IDEMPOTENCY_KEY_REQUIRED', 400, fn () => $this->purchases->create([], null));
        $tomorrow = (new DateTimeImmutable($this->scalar('SELECT current_date::text')))->modify('+1 day')->format('Y-m-d');
        foreach ([
            ['purchase_date' => $tomorrow],
            ['purchase_date' => '2026-02-30'],
            ['payment_method' => 'TARJETA'],
            ['items' => []],
            ['items' => [['ingredient_id' => $this->beef, 'quantity' => 0, 'unit_price' => 1]]],
            ['items' => [['ingredient_id' => $this->beef, 'quantity' => '1.2345', 'unit_price' => 1]]],
            ['items' => [['ingredient_id' => $this->beef, 'quantity' => 1, 'unit_price' => -1]]],
            ['items' => [['ingredient_id' => $this->beef, 'quantity' => 1, 'unit_price' => 1], ['ingredient_id' => $this->beef, 'quantity' => 2, 'unit_price' => 1]]],
            ['items' => [['ingredient_id' => 999999999, 'quantity' => 1, 'unit_price' => 1]]],
            ['supplier_id' => 999999999],
        ] as $override) {
            $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->purchases->create($override + $this->purchaseInput([[$this->beef, 1, 10]]), self::uuid()));
        }

        $this->ingredients->setActive($this->buns, ['is_active' => false]);
        $e = $this->assertApiError('INGREDIENT_INACTIVE', 409, fn () => $this->buy([[$this->beef, 1, 10], [$this->buns, 1, 1]]));
        $this->assertSame([['id' => $this->buns, 'name' => 'Pan Test']], $e->details['ingredients']);
        $this->assertSame('0.000', $this->stockAndCost($this->beef)[0], 'La compra rechazada no deja stock');

        $supplier = (new SuppliersService($this->db, $this->manager))->create(['name' => 'Proveedor Test']);
        (new SuppliersService($this->db, $this->manager))->update($supplier['id'], ['is_active' => false]);
        $this->assertApiError('SUPPLIER_INACTIVE', 409, fn () => $this->buy([[$this->beef, 1, 10]], supplierId: $supplier['id']));
    }

    public function testReintentoDeCompraNoDuplica(): void
    {
        $key = self::uuid();
        $input = $this->purchaseInput([[$this->beef, 1, 50]]);
        $first = $this->purchases->create($input, $key);
        $retry = $this->purchases->create($input, $key);
        $this->assertSame([true, false, $first['purchase']['id']], [$first['created'], $retry['created'], $retry['purchase']['id']]);
        $this->assertSame('1.000', $this->stockAndCost($this->beef)[0]);

        $input['items'][0]['unit_price'] = 51;
        $this->assertApiError('IDEMPOTENCY_KEY_REUSED', 409, fn () => $this->purchases->create($input, $key));
    }

    public function testAnularCompraRevierteStockCostoYEgreso(): void
    {
        $first = $this->buy([[$this->beef, 2, 60]], date: '2026-10-01');
        $second = $this->buy([[$this->beef, 2, 80]]);
        $this->assertSame(['4.000', '70.0000'], $this->stockAndCost($this->beef));

        $voided = $this->purchases->void($second['id'], ['reason' => 'Boleta duplicada']);
        $this->assertSame(['ANULADA', 'Boleta duplicada'], [$voided['status'], $voided['voided']['reason']]);
        // (4·70 − 2·80) / 2 = 60: vuelve al costo de la primera compra.
        $this->assertSame(['2.000', '60.0000'], $this->stockAndCost($this->beef));
        $this->assertSame(['INGRESO', $second['purchase_date']], array_values($this->db->query(
            "SELECT type, business_date::text FROM financial_transactions
             WHERE source_type = 'PURCHASE' AND source_id = {$second['id']} AND is_reversal")->fetch()));
        $this->assertApiError('PURCHASE_ALREADY_VOIDED', 409, fn () => $this->purchases->void($second['id'], ['reason' => 'x']));

        // Si el stock queda en 0 se conserva el último costo.
        $this->purchases->void($first['id'], ['reason' => 'Error']);
        $this->assertSame(['0.000', '60.0000'], $this->stockAndCost($this->beef));
        $this->assertSame('-2.000', $this->scalar("SELECT quantity FROM inventory_movements WHERE type = 'REVERSO' ORDER BY id DESC LIMIT 1"));
    }

    public function testNoSeAnulaUnaCompraYaConsumida(): void
    {
        $purchase = $this->buy([[$this->beef, 2, 60]]);
        $this->inventory->consume(['items' => [['ingredient_id' => $this->beef, 'quantity' => '1.5']], 'reason' => 'Turno noche']);
        $e = $this->assertApiError('INSUFFICIENT_STOCK', 409, fn () => $this->purchases->void($purchase['id'], ['reason' => 'x']));
        $this->assertSame(['0.500', '2.000'], [$e->details['ingredients'][0]['stock'], $e->details['ingredients'][0]['required']]);
        $this->assertSame('CONFIRMADA', $this->purchases->get($purchase['id'])['status']);

        // Con un ajuste que repone lo usado, la anulación pasa.
        $this->inventory->adjust(['ingredient_id' => $this->beef, 'quantity' => '1.5', 'reason' => 'Conteo físico']);
        $this->assertSame('ANULADA', $this->purchases->void($purchase['id'], ['reason' => 'x'])['status']);
    }

    public function testAjustesYConsumosNuncaDejanStockNegativo(): void
    {
        $this->buy([[$this->beef, 3, 60], [$this->buns, 10, 1]]);
        $adjust = $this->inventory->adjust(['ingredient_id' => $this->beef, 'quantity' => '-0.250', 'reason' => 'Merma']);
        $this->assertSame(['AJUSTE', '-0.250', '2.750', null], [$adjust['type'], $adjust['quantity'], $adjust['stock_after'], $adjust['unit_cost']]);
        $this->assertSame(['2.750', '60.0000'], $this->stockAndCost($this->beef), 'El ajuste no cambia el costo');

        $this->assertApiError('INSUFFICIENT_STOCK', 409, fn () => $this->inventory->adjust(['ingredient_id' => $this->beef, 'quantity' => -3, 'reason' => 'x']));
        foreach ([['quantity' => 0], ['reason' => ''], ['ingredient_id' => 999999999]] as $override) {
            $this->assertApiError('VALIDATION_ERROR', 400,
                fn () => $this->inventory->adjust($override + ['ingredient_id' => $this->beef, 'quantity' => 1, 'reason' => 'x']));
        }

        // Si un insumo no alcanza, no se registra ninguna salida.
        $this->assertApiError('INSUFFICIENT_STOCK', 409, fn () => $this->inventory->consume(['reason' => 'Turno', 'items' => [
            ['ingredient_id' => $this->buns, 'quantity' => 2], ['ingredient_id' => $this->beef, 'quantity' => 5]]]));
        $this->assertSame('10.000', $this->stockAndCost($this->buns)[0]);

        $out = $this->inventory->consume(['reason' => 'Turno', 'items' => [
            ['ingredient_id' => $this->buns, 'quantity' => 2], ['ingredient_id' => $this->beef, 'quantity' => '0.75']]]);
        $this->assertSame(['SALIDA_CONSUMO', '-2.000', '8.000'], [$out[0]['type'], $out[0]['quantity'], $out[0]['stock_after']]);
        $this->assertSame('2.000', $this->stockAndCost($this->beef)[0]);
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->inventory->consume(['reason' => 'x', 'items' => [
            ['ingredient_id' => $this->buns, 'quantity' => 1], ['ingredient_id' => $this->buns, 'quantity' => 1]]]));
    }

    public function testKardexYStockBajo(): void
    {
        $this->buy([[$this->beef, 1, 60], [$this->buns, 5, 1]]);
        $kardex = $this->inventory->movements(['ingredient_id' => (string) $this->beef]);
        $this->assertSame([1, 'ENTRADA_COMPRA', '1.000'], [$kardex['meta']['total'], $kardex['data'][0]['type'], $kardex['data'][0]['stock_after']]);
        $this->assertSame(0, $this->inventory->movements(['ingredient_id' => (string) $this->beef, 'type' => 'AJUSTE'])['meta']['total']);
        $this->assertSame(0, $this->inventory->movements(['ingredient_id' => (string) $this->beef, 'from' => '2020-01-01', 'to' => '2020-01-31'])['meta']['total']);
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->inventory->movements(['type' => 'ROBO']));

        // Carne: 1 kg con mínimo 2 → stock bajo. Pan: 5 con mínimo 0 → no.
        $low = array_column($this->ingredients->list(['low_stock' => 'true', 'category_id' => (string) $this->categoryId])['data'], 'name');
        $this->assertSame(['Carne Test'], $low);
        $this->assertSame(true, $this->ingredients->get($this->beef)['is_low_stock']);
        $this->ingredients->setActive($this->beef, ['is_active' => false]);
        $this->assertSame([], array_column($this->ingredients->list(['low_stock' => 'true', 'category_id' => (string) $this->categoryId])['data'], 'name'));
    }

    public function testInsumosUnidadBloqueadaYCamposDerivados(): void
    {
        // Sin movimientos la unidad todavía se puede corregir.
        $this->assertSame('unidad', $this->ingredients->update($this->beef, ['unit_id' => $this->unit])['unit']['code']);
        $this->ingredients->update($this->beef, ['unit_id' => $this->kg]);
        $this->buy([[$this->beef, 1, 60]]);
        $this->assertApiError('UNIT_LOCKED', 409, fn () => $this->ingredients->update($this->beef, ['unit_id' => $this->unit]));
        $this->assertSame('3.000', $this->ingredients->update($this->beef, ['min_stock' => 3])['min_stock']);

        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->ingredients->update($this->beef, ['current_stock' => 100]));
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->ingredients->update($this->beef, ['avg_unit_cost' => 1]));
        $this->assertApiError('INGREDIENT_NAME_TAKEN', 409, fn () => $this->ingredient('CARNE test', $this->kg));
        $this->assertApiError('INGREDIENT_CATEGORY_NAME_TAKEN', 409, fn () => $this->ingredients->createCategory(['name' => 'carnes test']));
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->ingredients->create(['name' => 'X', 'category_id' => $this->categoryId, 'unit_id' => 999999999]));
        $this->assertApiError('NOT_FOUND', 404, fn () => $this->ingredients->update(999999999, ['min_stock' => 1]));
    }

    public function testProveedores(): void
    {
        $suppliers = new SuppliersService($this->db, $this->manager);
        $supplier = $suppliers->create(['name' => ' Frigorífico  Test ', 'phone' => '+591 7111-2222']);
        $this->assertSame(['Frigorífico Test', '+59171112222', true], [$supplier['name'], $supplier['phone'], $supplier['is_active']]);
        $this->assertApiError('SUPPLIER_NAME_TAKEN', 409, fn () => $suppliers->create(['name' => 'frigorífico test']));
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $suppliers->create(['name' => 'X', 'phone' => '12']));
        $this->assertSame(false, $suppliers->update($supplier['id'], ['is_active' => false])['is_active']);
        $this->assertTrue(!in_array($supplier['id'], array_column($suppliers->list(['active' => 'true']), 'id'), true));

        $purchase = $this->buy([[$this->beef, 1, 10]]);
        $this->assertSame(null, $purchase['supplier']);
    }

    private function ingredient(string $name, int $unitId, string $minStock = '0'): int
    {
        return $this->ingredients->create(['name' => $name, 'category_id' => $this->categoryId, 'unit_id' => $unitId, 'min_stock' => $minStock])['id'];
    }

    /** @param list<array{0: int, 1: mixed, 2: mixed}> $items [ingredient_id, cantidad, precio unitario] */
    private function buy(array $items, ?string $date = null, ?int $supplierId = null): array
    {
        $input = $this->purchaseInput($items, $date, $supplierId);
        return $this->purchases->create($input, self::uuid())['purchase'];
    }

    private function purchaseInput(array $items, ?string $date = null, ?int $supplierId = null): array
    {
        return [
            'purchase_date' => $date ?? $this->scalar('SELECT current_date::text'),
            'supplier_id' => $supplierId,
            'payment_method' => 'EFECTIVO',
            'items' => array_map(static fn (array $item): array => ['ingredient_id' => $item[0], 'quantity' => $item[1], 'unit_price' => $item[2]], $items),
        ];
    }

    /** @return array{0: string, 1: string} [current_stock, avg_unit_cost] */
    private function stockAndCost(int $ingredientId): array
    {
        return array_values($this->db->query("SELECT current_stock, avg_unit_cost FROM ingredients WHERE id = {$ingredientId}")->fetch());
    }
}
