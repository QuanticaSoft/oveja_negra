<?php

declare(strict_types=1);

final class CatalogServiceTest extends DbTestCase
{
    private string $mediaDir;
    private AuthUser $admin;
    private CategoriesService $categories;
    private ProductsService $products;

    public function setUp(): void
    {
        parent::setUp();
        $this->mediaDir = sys_get_temp_dir() . '/oveja_media_' . bin2hex(random_bytes(4));
        mkdir($this->mediaDir);
        $this->admin = $this->authUser($this->insertUser('ADMIN', 'admin.test'));
        $this->categories = new CategoriesService($this->db, $this->admin);
        $this->products = new ProductsService($this->db, $this->admin,
            new Media(['media_dir' => $this->mediaDir, 'media_base_url' => 'https://cdn.test/media']));
    }

    public function tearDown(): void
    {
        parent::tearDown();
        exec('rm -rf ' . escapeshellarg($this->mediaDir));
    }

    public function testCategoriasCrearEditarYNombreUnico(): void
    {
        $category = $this->categories->create(['name' => '  Hamburguesas  Test ', 'sort_order' => 1]);
        $this->assertSame('Hamburguesas Test', $category['name']);

        $this->assertApiError('CATEGORY_NAME_TAKEN', 409, fn () => $this->categories->create(['name' => 'HAMBURGUESAS TEST']));
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->categories->create(['name' => '', 'sort_order' => -1]));

        $updated = $this->categories->update($category['id'], ['is_active' => false, 'sort_order' => 5]);
        $this->assertSame(false, $updated['is_active']);
        $this->assertSame(5, $updated['sort_order']);
        $this->assertApiError('NOT_FOUND', 404, fn () => $this->categories->update(999999999, ['name' => 'X']));
    }

    public function testProductoValidaPrecioYCategoria(): void
    {
        $categoryId = $this->category('Bebidas Test');
        foreach ([0, '0.00', -5, '12.555', 'abc', null] as $invalid) {
            $this->assertApiError('VALIDATION_ERROR', 400,
                fn () => $this->products->create(['category_id' => $categoryId, 'name' => 'Agua', 'price' => $invalid]));
        }
        $this->assertApiError('VALIDATION_ERROR', 400,
            fn () => $this->products->create(['category_id' => 999999999, 'name' => 'Agua', 'price' => '5']));

        $inactive = $this->category('Inactiva Test', active: false);
        $this->assertApiError('CATEGORY_INACTIVE', 409,
            fn () => $this->products->create(['category_id' => $inactive, 'name' => 'Agua', 'price' => '5']));
    }

    public function testProductoCreadoConPrecioComoTexto(): void
    {
        $categoryId = $this->category('Hamburguesas Test');
        $product = $this->product('Clásica Test', 25.5, $categoryId);
        $this->assertSame('25.50', $product['price']);
        $this->assertSame(null, $product['image_url']);
        $this->assertSame(true, $product['is_available']);
        $this->assertApiError('PRODUCT_NAME_TAKEN', 409, fn () => $this->product('CLÁSICA test', 30, $categoryId));
        // El mismo nombre en otra categoría sí se permite.
        $this->assertSame('Clásica Test', $this->product('Clásica Test', 30)['name']);
    }

    public function testCambioDePrecioDejaHistorialYNoAlteraVentas(): void
    {
        $product = $this->product('Doble Test', '30.00');
        $orderId = (int) $this->scalar(
            "INSERT INTO orders (business_date, daily_number, channel, subtotal, total, created_by)
             VALUES ('2000-01-01', (SELECT COALESCE(max(daily_number), 0) + 1 FROM orders WHERE business_date = '2000-01-01'), 'LOCAL', '30.00', '30.00', ?) RETURNING id", [$this->admin->id]);
        $this->db->prepare(
            "INSERT INTO order_items (order_id, product_id, product_name_snapshot, unit_price_snapshot, quantity, line_total)
             VALUES (?, ?, 'Doble Test', '30.00', 1, '30.00')")->execute([$orderId, $product['id']]);

        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->products->update($product['id'], ['price' => '40']));
        $updated = $this->products->changePrice($product['id'], ['price' => '34.50']);
        $this->assertSame('34.50', $updated['price']);

        $this->assertSame('30.00', $this->scalar('SELECT unit_price_snapshot FROM order_items WHERE order_id = ?', [$orderId]));
        $history = $this->products->priceHistory($product['id']);
        $this->assertSame(1, count($history));
        $this->assertSame(['30.00', '34.50', $this->admin->id], [$history[0]['old_price'], $history[0]['new_price'], $history[0]['changed_by']['id']]);

        // Mismo precio: no genera historial.
        $this->products->changePrice($product['id'], ['price' => 34.5]);
        $this->assertSame(1, count($this->products->priceHistory($product['id'])));
        $this->assertSame(1, (int) $this->scalar(
            "SELECT count(*) FROM audit_logs WHERE entity = 'products' AND entity_id = ? AND action = 'change_price'", [$product['id']]));
    }

    public function testDisponibilidadYEstado(): void
    {
        $product = $this->product('Papas Test', 12);
        $this->assertSame(false, $this->products->setAvailability($product['id'], ['is_available' => false])['is_available']);
        $this->assertSame(false, $this->products->setActive($product['id'], ['is_active' => false])['is_active']);
        $this->assertApiError('VALIDATION_ERROR', 400, fn () => $this->products->setAvailability($product['id'], ['is_available' => 'no']));
        $this->assertSame(2, (int) $this->scalar(
            "SELECT count(*) FROM audit_logs WHERE entity_id = ? AND action IN ('mark_unavailable', 'deactivate') AND entity = 'products'",
            [$product['id']]));
    }

    public function testCartillaExcluyeInactivosYMarcaAgotados(): void
    {
        $categoryId = $this->category('Menú Test', sortOrder: 0);
        $visible = $this->product('Visible Test', 10, $categoryId);
        $soldOut = $this->product('Agotado Test', 10, $categoryId);
        $hidden = $this->product('Oculto Test', 10, $categoryId);
        $this->products->setAvailability($soldOut['id'], ['is_available' => false]);
        $this->products->setActive($hidden['id'], ['is_active' => false]);
        $inactiveCategory = $this->category('Categoría Oculta Test', active: false);
        $this->db->prepare("INSERT INTO products (category_id, name, price) VALUES (?, 'En categoría oculta', 5)")
            ->execute([$inactiveCategory]);

        $menu = array_column($this->products->menu(), null, 'name');
        $this->assertTrue(!isset($menu['Categoría Oculta Test']));
        $names = array_column($menu['Menú Test']['products'], 'is_available', 'name');
        $this->assertSame(['Agotado Test' => false, 'Visible Test' => true], $names);
    }

    public function testListadoConFiltrosYBusquedaLiteral(): void
    {
        $categoryId = $this->category('Filtro Test');
        $this->product('Combo 100% Test', 40, $categoryId);
        $this->product('Combo simple Test', 30, $categoryId);

        $result = $this->products->list(['category_id' => (string) $categoryId, 'q' => '100%']);
        $this->assertSame(['Combo 100% Test'], array_column($result['data'], 'name'));
        $this->assertSame(2, $this->products->list(['category_id' => (string) $categoryId, 'q' => 'combo'])['meta']['total']);
        $this->assertSame(0, $this->products->list(['category_id' => (string) $categoryId, 'q' => '_ombo%'])['meta']['total']);
    }

    public function testImagenSeReemplazaYBorraLaAnterior(): void
    {
        $product = $this->product('Con foto Test', 20);
        $first = $this->products->replaceImage($product['id'], $this->jpeg());
        $this->assertTrue(str_starts_with($first['image_url'], 'https://cdn.test/media/p/'));
        $this->assertTrue(str_ends_with($first['thumb_url'], '_t.jpg'));
        $firstPath = substr($first['image_url'], strlen('https://cdn.test/media/'));
        $this->assertTrue(is_file("{$this->mediaDir}/{$firstPath}"));

        $second = $this->products->replaceImage($product['id'], $this->jpeg());
        $this->assertTrue($second['image_url'] !== $first['image_url']);
        $this->assertTrue(!is_file("{$this->mediaDir}/{$firstPath}"), 'La imagen anterior debe borrarse');
        $this->assertApiError('NOT_FOUND', 404, fn () => $this->products->replaceImage(999999999, $this->jpeg()));
    }

    private function category(string $name, bool $active = true, int $sortOrder = 99): int
    {
        $id = $this->categories->create(['name' => $name, 'sort_order' => $sortOrder])['id'];
        if (!$active) {
            $this->categories->update($id, ['is_active' => false]);
        }
        return $id;
    }

    private function product(string $name, mixed $price, ?int $categoryId = null): array
    {
        $categoryId ??= $this->category('Productos ' . bin2hex(random_bytes(3)));
        return $this->products->create(['category_id' => $categoryId, 'name' => $name, 'price' => $price]);
    }

    private function jpeg(): string
    {
        $path = $this->mediaDir . '/' . bin2hex(random_bytes(4)) . '-src.jpg';
        imagejpeg(imagecreatetruecolor(1000, 800), $path);
        return $path;
    }
}
