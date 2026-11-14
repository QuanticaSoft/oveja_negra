<?php

declare(strict_types=1);

final class ExtrasTest extends DbTestCase
{
    private AuthUser $admin;
    private ExtrasService $extras;
    private OrdersService $orders;
    private int $burgers;
    private int $drinks;
    private int $burger;
    private int $drink;
    private int $eggIngredient;
    private int $egg;
    private int $cheese;

    public function setUp(): void
    {
        parent::setUp();
        $this->admin = $this->authUser($this->insertUser('ADMIN', 'admin.test'));
        $this->extras = new ExtrasService($this->db, $this->admin);
        $this->orders = new OrdersService($this->db, $this->admin);

        $this->burgers = (int) $this->scalar("INSERT INTO categories (name) VALUES ('Hamburguesas Extras Test') RETURNING id");
        $this->drinks = (int) $this->scalar("INSERT INTO categories (name) VALUES ('Bebidas Extras Test') RETURNING id");
        $this->burger = (int) $this->scalar("INSERT INTO products (category_id, name, price) VALUES (?, 'Clásica Extras Test', '25.50') RETURNING id", [$this->burgers]);
        $this->drink = (int) $this->scalar("INSERT INTO products (category_id, name, price) VALUES (?, 'Limonada Extras Test', '10.00') RETURNING id", [$this->drinks]);

        $ingredients = new IngredientsService($this->db, $this->admin);
        $units = array_column($ingredients->units(), 'id', 'code');
        $this->eggIngredient = $ingredients->create([
            'name' => 'Huevo Extras Test',
            'category_id' => $ingredients->createCategory(['name' => 'Extras Test'])['id'],
            'unit_id' => $units['unidad'],
        ])['id'];
        (new InventoryService($this->db, $this->admin))->adjust(['ingredient_id' => $this->eggIngredient, 'quantity' => 10, 'reason' => 'Stock inicial']);

        $this->egg = $this->extras->create(['name' => 'Huevo Test', 'price' => '4', 'ingredient_id' => $this->eggIngredient, 'ingredient_quantity' => 1])['id'];
        $this->cheese = $this->extras->create(['name' => 'Queso Test', 'price' => '4.00'])['id'];
        $this->extras->setCategoryExtras($this->burgers, ['extra_ids' => [$this->egg, $this->cheese]]);
    }

    public function testCatalogoDeExtrasYCartilla(): void
    {
        $this->assertApiError('EXTRA_NAME_TAKEN', 409, fn () => $this->extras->create(['name' => 'HUEVO test', 'price' => 1]));
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->extras->create(['name' => 'X', 'price' => 1, 'ingredient_id' => $this->eggIngredient]));
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->extras->create(['name' => 'X', 'price' => 1, 'ingredient_id' => 999999999, 'ingredient_quantity' => 1]));
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->extras->create(['name' => 'X', 'price' => -1]));
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->extras->setCategoryExtras($this->burgers, ['extra_ids' => [999999999]]));

        $listed = array_column($this->extras->list([]), null, 'id');
        $this->assertSame([$this->burgers], $listed[$this->egg]['category_ids']);
        $this->assertSame(['1.000', 'unidad'], [$listed[$this->egg]['ingredient']['quantity'], $listed[$this->egg]['ingredient']['unit']]);

        // La cartilla trae los extras de cada categoría; las bebidas no tienen.
        $menu = array_column((new ProductsService($this->db, $this->admin, new Media(['media_dir' => '/tmp'])))->menu(), null, 'id');
        $this->assertSame([['Huevo Test', '4.00', true], ['Queso Test', '4.00', true]],
            array_map(static fn (array $e): array => [$e['name'], $e['price'], $e['is_available']], $menu[$this->burgers]['extras']));
        $this->assertSame([], $menu[$this->drinks]['extras']);

        // Sin stock del insumo, el extra figura agotado aunque esté marcado como disponible.
        (new InventoryService($this->db, $this->admin))->adjust(['ingredient_id' => $this->eggIngredient, 'quantity' => -10, 'reason' => 'Se acabó']);
        $menu = array_column((new ProductsService($this->db, $this->admin, new Media(['media_dir' => '/tmp'])))->menu(), null, 'id');
        $this->assertSame(false, array_column($menu[$this->burgers]['extras'], 'is_available', 'name')['Huevo Test']);

        $this->assertSame(false, $this->extras->setAvailability($this->cheese, ['is_available' => false])['is_available']);
    }

    public function testPedidoConExtrasCobraDesdeLaBdYDescuentaInsumo(): void
    {
        $order = $this->order([
            ['product_id' => $this->burger, 'quantity' => 2, 'notes' => 'sin cebolla',
             'extras' => [['extra_id' => $this->egg, 'quantity' => 2], ['extra_id' => $this->cheese, 'quantity' => 1]]],
            // El mismo producto en otra línea, sin extras, es válido.
            ['product_id' => $this->burger, 'quantity' => 1],
        ]);
        // (25,50 + 2·4 + 4) · 2 = 75,00; más 25,50 sin extras.
        $this->assertSame(['75.00', '12.00', 'sin cebolla'], [$order['items'][0]['line_total'], $order['items'][0]['extras_unit_total'], $order['items'][0]['notes']]);
        $this->assertSame([['Huevo Test', '4.00', 2], ['Queso Test', '4.00', 1]],
            array_map(static fn (array $e): array => [$e['name'], $e['unit_price'], $e['quantity']], $order['items'][0]['extras']));
        $this->assertSame('100.50', $order['total']);

        // 1 huevo × 2 (extra) × 2 (hamburguesas) = 4 menos.
        $this->assertSame('6.000', $this->stock());
        $this->assertSame(1, (int) $this->scalar(
            "SELECT count(*) FROM inventory_movements WHERE type = 'SALIDA_CONSUMO' AND source_type = 'ORDER_ITEM_EXTRA' AND quantity = -4"));

        // Cambiar el precio del extra después no altera el pedido.
        $this->extras->update($this->egg, ['price' => '9']);
        $this->assertSame('4.00', $this->orders->get($order['id'])['items'][0]['extras'][0]['unit_price']);
    }

    public function testExtraNoPermitidoAgotadoOSinStock(): void
    {
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->order([
            ['product_id' => $this->drink, 'quantity' => 1, 'extras' => [['extra_id' => $this->cheese, 'quantity' => 1]]],
        ]));

        $this->extras->setAvailability($this->cheese, ['is_available' => false]);
        $e = $this->assertApiError('EXTRA_UNAVAILABLE', 409, fn () => $this->order([
            ['product_id' => $this->burger, 'quantity' => 1, 'extras' => [['extra_id' => $this->cheese, 'quantity' => 1]]],
        ]));
        $this->assertSame([['id' => $this->cheese, 'name' => 'Queso Test']], $e->details['extras']);

        // 3 hamburguesas × 5 huevos = 15 > 10 en stock: no se guarda nada.
        $before = (int) $this->scalar('SELECT count(*) FROM orders');
        $e = $this->assertApiError('EXTRA_OUT_OF_STOCK', 409, fn () => $this->order([
            ['product_id' => $this->burger, 'quantity' => 3, 'extras' => [['extra_id' => $this->egg, 'quantity' => 5]]],
        ]));
        $this->assertSame('Huevo Test', $e->details['extras'][0]['name']);
        $this->assertSame([$before, '10.000'], [(int) $this->scalar('SELECT count(*) FROM orders'), $this->stock()]);
    }

    public function testCancelarYEditarDevuelvenElStock(): void
    {
        $order = $this->order([['product_id' => $this->burger, 'quantity' => 1, 'extras' => [['extra_id' => $this->egg, 'quantity' => 2]]]]);
        $this->assertSame('8.000', $this->stock());

        // Editar: vuelven los 2 y se descuenta 1.
        $edited = $this->orders->replaceItems($order['id'], ['items' => [
            ['product_id' => $this->burger, 'quantity' => 1, 'extras' => [['extra_id' => $this->egg, 'quantity' => 1]]],
        ]]);
        $this->assertSame(['29.50', '9.000'], [$edited['total'], $this->stock()]);

        $this->orders->cancel($order['id'], ['reason' => 'Prueba']);
        $this->assertSame('10.000', $this->stock());
        $this->assertSame(2, (int) $this->scalar(
            "SELECT count(*) FROM inventory_movements WHERE type = 'REVERSO' AND source_type = 'ORDER_ITEM_EXTRA'"));
    }

    public function testReintentoIdempotenteConExtras(): void
    {
        $key = self::uuid();
        $items = [['product_id' => $this->burger, 'quantity' => 1, 'notes' => 'término medio', 'extras' => [['extra_id' => $this->egg, 'quantity' => 1]]]];
        $first = $this->orders->create(['channel' => 'LOCAL', 'items' => $items], $key);
        $retry = $this->orders->create(['channel' => 'LOCAL', 'items' => $items], $key);
        $this->assertSame([true, false, $first['order']['id']], [$first['created'], $retry['created'], $retry['order']['id']]);
        $this->assertSame('9.000', $this->stock(), 'el reintento no descuenta dos veces');

        $other = $items;
        $other[0]['extras'][0]['quantity'] = 2;
        $this->assertApiError('IDEMPOTENCY_KEY_REUSED', 409, fn () => $this->orders->create(['channel' => 'LOCAL', 'items' => $other], $key));
    }

    private function order(array $items): array
    {
        return $this->orders->create(['channel' => 'LOCAL', 'items' => $items], self::uuid())['order'];
    }

    private function stock(): string
    {
        return (string) $this->scalar('SELECT current_stock FROM ingredients WHERE id = ?', [$this->eggIngredient]);
    }
}
