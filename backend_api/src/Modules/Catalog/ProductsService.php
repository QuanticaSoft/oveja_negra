<?php

declare(strict_types=1);

final class ProductsService
{
    // Las imágenes subidas viven bajo este prefijo; la media de demo ("demo/") nunca se borra.
    private const UPLOAD_PREFIX = 'p/';
    private const NAME_ERROR = 'Requerido, máximo 80 caracteres.';
    private const PRICE_ERROR = 'Importe mayor que 0 con hasta 2 decimales (p. ej. "35.50").';

    private readonly ProductRepository $products;
    private readonly CategoryRepository $categories;

    public function __construct(private readonly PDO $db, private readonly AuthUser $actor, private readonly Media $media)
    {
        $this->products = new ProductRepository($db);
        $this->categories = new CategoryRepository($db);
    }

    /** Cartilla: categorías activas con sus productos activos (incluye los agotados, marcados). */
    public function menu(): array
    {
        $menu = [];
        foreach ($this->products->menuRows() as $row) {
            $categoryId = (int) $row['category_id'];
            $menu[$categoryId] ??= ['id' => $categoryId, 'name' => $row['category_name'], 'products' => []];
            $menu[$categoryId]['products'][] = [
                'id' => (int) $row['id'],
                'name' => $row['name'],
                'description' => $row['description'],
                'price' => $row['price'],
                'is_available' => (bool) $row['is_available'],
            ] + $this->imageUrls($row['image_path']);
        }
        return array_values($menu);
    }

    /** @return array{data: list<array>, meta: array} */
    public function list(array $query): array
    {
        $filters = [];
        if (isset($query['category_id'])) {
            $filters['category_id'] = Validation::positiveInt($query['category_id'])
                ?? throw ApiException::validation(['category_id' => 'Entero positivo.']);
        }
        foreach (['active', 'available'] as $flag) {
            $value = Validation::boolQuery($query[$flag] ?? null, $flag);
            if ($value !== null) {
                $filters[$flag] = $value;
            }
        }
        if (isset($query['q'])) {
            $filters['q'] = Validation::text($query['q'], 80) ?? throw ApiException::validation(['q' => 'Máximo 80 caracteres.']);
        }
        $pagination = Pagination::fromQuery($query);

        $result = $this->products->list($filters, $pagination->perPage, $pagination->offset());
        return ['data' => array_map($this->toPublic(...), $result['rows']), 'meta' => $pagination->meta($result['total'])];
    }

    public function get(int $id): array
    {
        return $this->toPublic($this->products->find($id) ?? throw self::notFound());
    }

    public function create(array $input): array
    {
        $errors = [];
        $categoryId = Validation::positiveInt($input['category_id'] ?? null);
        if ($categoryId === null) {
            $errors['category_id'] = 'Requerido.';
        }
        $name = Validation::text($input['name'] ?? null, 80);
        if ($name === null) {
            $errors['name'] = self::NAME_ERROR;
        }
        $description = Validation::optionalText($input['description'] ?? null, 500);
        if ($description === false) {
            $errors['description'] = 'Máximo 500 caracteres.';
        }
        $price = self::price($input['price'] ?? null);
        if ($price === null) {
            $errors['price'] = self::PRICE_ERROR;
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }

        return self::mapDuplicateName(fn (): array => Db::transaction($this->db, function () use ($categoryId, $name, $description, $price): array {
            $this->assertActiveCategory($categoryId);
            $id = $this->products->insert($categoryId, $name, $description, $price);
            $product = $this->products->find($id);
            Audit::log($this->db, $this->actor->id, 'products', $id, 'create', null, $product);
            return $this->toPublic($product);
        }));
    }

    /** Nombre, descripción y categoría. El precio tiene su propio endpoint (deja historial). */
    public function update(int $id, array $input): array
    {
        if (array_key_exists('price', $input)) {
            throw ApiException::validation(['price' => 'El precio se cambia con PATCH /v1/products/{id}/price.']);
        }
        $fields = [];
        $errors = [];
        if (array_key_exists('category_id', $input)) {
            $fields['category_id'] = Validation::positiveInt($input['category_id']);
            if ($fields['category_id'] === null) {
                $errors['category_id'] = 'Entero positivo.';
            }
        }
        if (array_key_exists('name', $input)) {
            $fields['name'] = Validation::text($input['name'], 80);
            if ($fields['name'] === null) {
                $errors['name'] = self::NAME_ERROR;
            }
        }
        if (array_key_exists('description', $input)) {
            $fields['description'] = Validation::optionalText($input['description'], 500);
            if ($fields['description'] === false) {
                $errors['description'] = 'Máximo 500 caracteres.';
            }
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }
        if ($fields === []) {
            throw ApiException::validation([], 'No hay campos para actualizar.');
        }

        return self::mapDuplicateName(fn (): array => Db::transaction($this->db, function () use ($id, $fields): array {
            $before = $this->products->find($id, forUpdate: true) ?? throw self::notFound();
            if (isset($fields['category_id']) && $fields['category_id'] !== (int) $before['category_id']) {
                $this->assertActiveCategory($fields['category_id']);
            }
            $this->products->update($id, $fields);
            $after = $this->products->find($id);
            Audit::log($this->db, $this->actor->id, 'products', $id, 'update', $before, $after);
            return $this->toPublic($after);
        }));
    }

    /** Las ventas guardan su propio precio (order_items.unit_price_snapshot): esto no las altera. */
    public function changePrice(int $id, array $input): array
    {
        $price = self::price($input['price'] ?? null) ?? throw ApiException::validation(['price' => self::PRICE_ERROR]);

        return Db::transaction($this->db, function () use ($id, $price): array {
            $before = $this->products->find($id, forUpdate: true) ?? throw self::notFound();
            if (Money::toCents($before['price']) === Money::toCents($price)) {
                return $this->toPublic($before);
            }
            $this->products->setPrice($id, $price);
            $this->products->insertPriceChange($id, $before['price'], $price, $this->actor->id);
            Audit::log($this->db, $this->actor->id, 'products', $id, 'change_price',
                ['price' => $before['price']], ['price' => $price]);
            return $this->toPublic($this->products->find($id));
        });
    }

    public function setActive(int $id, array $input): array
    {
        return $this->setFlag($id, 'is_active', $input, 'activate', 'deactivate');
    }

    public function setAvailability(int $id, array $input): array
    {
        return $this->setFlag($id, 'is_available', $input, 'mark_available', 'mark_unavailable');
    }

    /** Guarda la imagen nueva y recién después de confirmar en la BD borra la anterior. */
    public function replaceImage(int $id, string $sourcePath): array
    {
        $this->products->find($id) ?? throw self::notFound();
        $newPath = ImageProcessor::store($sourcePath, $this->media->dir(), self::UPLOAD_PREFIX . date('Y/m'));

        try {
            [$product, $oldPath] = Db::transaction($this->db, function () use ($id, $newPath): array {
                $before = $this->products->find($id, forUpdate: true) ?? throw self::notFound();
                $this->products->setImagePath($id, $newPath);
                Audit::log($this->db, $this->actor->id, 'products', $id, 'replace_image',
                    ['image_path' => $before['image_path']], ['image_path' => $newPath]);
                return [$this->products->find($id), $before['image_path']];
            });
        } catch (Throwable $e) {
            ImageProcessor::delete($this->media->dir(), $newPath, self::UPLOAD_PREFIX);
            throw $e;
        }

        ImageProcessor::delete($this->media->dir(), $oldPath, self::UPLOAD_PREFIX);
        return $this->toPublic($product);
    }

    public function priceHistory(int $id): array
    {
        $this->products->find($id) ?? throw self::notFound();
        return $this->products->priceHistory($id);
    }

    private function setFlag(int $id, string $column, array $input, string $actionOn, string $actionOff): array
    {
        $value = Validation::bool($input[$column] ?? null)
            ?? throw ApiException::validation([$column => 'Debe ser true o false.']);

        return Db::transaction($this->db, function () use ($id, $column, $value, $actionOn, $actionOff): array {
            $before = $this->products->find($id, forUpdate: true) ?? throw self::notFound();
            if ((bool) $before[$column] === $value) {
                return $this->toPublic($before);
            }
            $this->products->setFlag($id, $column, $value);
            Audit::log($this->db, $this->actor->id, 'products', $id, $value ? $actionOn : $actionOff,
                [$column => !$value], [$column => $value]);
            return $this->toPublic($this->products->find($id));
        });
    }

    private function assertActiveCategory(int $categoryId): void
    {
        $category = $this->categories->find($categoryId)
            ?? throw ApiException::validation(['category_id' => 'Categoría inexistente.']);
        if (!$category['is_active']) {
            throw ApiException::conflict('CATEGORY_INACTIVE', 'La categoría está desactivada.');
        }
    }

    /** Precio > 0 como string NUMERIC ("35.50"); null si no es válido. */
    private static function price(mixed $value): ?string
    {
        $cents = Validation::money($value);
        return $cents === null || $cents === 0 ? null : Money::fromCents($cents);
    }

    private function imageUrls(?string $imagePath): array
    {
        return [
            'image_url' => $this->media->url($imagePath),
            'thumb_url' => $imagePath === null ? null : $this->media->url(ImageProcessor::thumbPathFor($imagePath)),
        ];
    }

    private function toPublic(array $row): array
    {
        return [
            'id' => (int) $row['id'],
            'category' => ['id' => (int) $row['category_id'], 'name' => $row['category_name']],
            'name' => $row['name'],
            'description' => $row['description'],
            'price' => $row['price'],
        ] + $this->imageUrls($row['image_path']) + [
            'is_active' => (bool) $row['is_active'],
            'is_available' => (bool) $row['is_available'],
            'created_at' => Dates::iso($row['created_at']),
            'updated_at' => Dates::iso($row['updated_at']),
        ];
    }

    /**
     * @template T
     * @param callable(): T $work
     * @return T
     */
    private static function mapDuplicateName(callable $work): mixed
    {
        try {
            return $work();
        } catch (PDOException $e) {
            if ($e->getCode() === '23505' && str_contains($e->getMessage(), 'uq_products_category_name')) {
                throw ApiException::conflict('PRODUCT_NAME_TAKEN', 'Ya existe un producto con ese nombre en la categoría.');
            }
            throw $e;
        }
    }

    private static function notFound(): ApiException
    {
        return ApiException::notFound('Producto no encontrado.');
    }
}
