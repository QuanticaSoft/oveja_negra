<?php

declare(strict_types=1);

/**
 * Extras (huevo, queso, jalapeño…): se venden sobre los productos de las categorías que los aceptan.
 * Pueden descontar un insumo al registrar el pedido. Nunca se borran: se desactivan.
 */
final class ExtrasService
{
    private const NAME_ERROR = 'Requerido, máximo 60 caracteres.';

    private readonly ExtraRepository $extras;
    private readonly CategoryRepository $categories;

    public function __construct(private readonly PDO $db, private readonly AuthUser $actor)
    {
        $this->extras = new ExtraRepository($db);
        $this->categories = new CategoryRepository($db);
    }

    public function list(array $query): array
    {
        $byCategory = $this->extras->extraIdsByCategory();
        return array_map(fn (array $row): array => self::toPublic($row) + [
            'category_ids' => self::categoriesOf((int) $row['id'], $byCategory),
        ], $this->extras->list(Validation::boolQuery($query['active'] ?? null, 'active')));
    }

    public function create(array $input): array
    {
        $fields = $this->fields($input, creating: true);
        return $this->mapDuplicateName(fn (): array => Db::transaction($this->db, function () use ($fields): array {
            $this->assertIngredient($fields);
            $id = $this->extras->insert($fields);
            $extra = self::toPublic($this->extras->find($id));
            Audit::log($this->db, $this->actor->id, 'extras', $id, 'create', null, $extra);
            return $extra;
        }));
    }

    public function update(int $id, array $input): array
    {
        $fields = $this->fields($input, creating: false);
        if ($fields === []) {
            throw ApiException::validation([], 'No hay campos para actualizar.');
        }
        return $this->mapDuplicateName(fn (): array => Db::transaction($this->db, function () use ($id, $fields): array {
            $before = $this->extras->find($id, forUpdate: true) ?? throw self::notFound();
            // Insumo y cantidad van juntos: si cambia uno, se valida el par resultante.
            $merged = $fields + ['ingredient_id' => $before['ingredient_id'], 'ingredient_quantity' => $before['ingredient_quantity']];
            $this->assertIngredient($merged);
            $this->extras->update($id, $fields);
            $after = self::toPublic($this->extras->find($id));
            Audit::log($this->db, $this->actor->id, 'extras', $id, 'update', self::toPublic($before), $after);
            return $after;
        }));
    }

    /** "Agotado hoy" (como los productos): lo puede marcar quien tenga `products.availability`. */
    public function setAvailability(int $id, array $input): array
    {
        $available = Validation::bool($input['is_available'] ?? null)
            ?? throw ApiException::validation(['is_available' => 'Debe ser true o false.']);
        return Db::transaction($this->db, function () use ($id, $available): array {
            $before = $this->extras->find($id, forUpdate: true) ?? throw self::notFound();
            if ((bool) $before['is_available'] !== $available) {
                $this->extras->update($id, ['is_available' => $available]);
                Audit::log($this->db, $this->actor->id, 'extras', $id, $available ? 'mark_available' : 'mark_unavailable',
                    ['is_available' => !$available], ['is_available' => $available]);
            }
            return self::toPublic($this->extras->find($id));
        });
    }

    /** Reemplaza el conjunto de extras que acepta una categoría. */
    public function setCategoryExtras(int $categoryId, array $input): array
    {
        $ids = $input['extra_ids'] ?? null;
        if (!is_array($ids) || !array_is_list($ids)) {
            throw ApiException::validation(['extra_ids' => 'Lista de ids de extras (puede ser vacía).']);
        }
        $extraIds = [];
        foreach ($ids as $id) {
            $extraIds[] = Validation::positiveInt($id) ?? throw ApiException::validation(['extra_ids' => 'Ids enteros positivos.']);
        }
        $extraIds = array_values(array_unique($extraIds));
        sort($extraIds);

        return Db::transaction($this->db, function () use ($categoryId, $extraIds): array {
            $this->categories->find($categoryId, forUpdate: true) ?? throw ApiException::notFound('Categoría no encontrada.');
            $missing = array_diff($extraIds, array_keys($this->extras->forSale($extraIds)));
            if ($missing !== []) {
                throw ApiException::validation(['extra_ids' => 'Extras inexistentes: ' . implode(', ', $missing) . '.']);
            }
            $before = $this->extras->extraIdsOf($categoryId);
            $this->extras->replaceCategoryExtras($categoryId, $extraIds);
            Audit::log($this->db, $this->actor->id, 'categories', $categoryId, 'set_extras', ['extra_ids' => $before], ['extra_ids' => $extraIds]);
            return ['category_id' => $categoryId, 'extra_ids' => $extraIds];
        });
    }

    /**
     * Extras de la cartilla por categoría: solo activos, con disponibilidad calculada
     * (disponible y con stock del insumo para al menos una porción).
     *
     * @return array<int, list<array>> por id de categoría
     */
    public function menuExtras(): array
    {
        $active = array_column($this->extras->list(true), null, 'id');
        $menu = [];
        foreach ($this->extras->extraIdsByCategory() as $categoryId => $extraIds) {
            foreach ($extraIds as $extraId) {
                $row = $active[$extraId] ?? null;
                if ($row !== null) {
                    $menu[$categoryId][] = [
                        'id' => (int) $row['id'],
                        'name' => $row['name'],
                        'price' => $row['price'],
                        'is_available' => (bool) $row['is_available'] && (bool) $row['in_stock'],
                        'sort_order' => (int) $row['sort_order'],
                    ];
                }
            }
        }
        foreach ($menu as &$list) {
            usort($list, static fn (array $a, array $b): int => [$a['sort_order'], $a['name']] <=> [$b['sort_order'], $b['name']]);
            $list = array_map(static fn (array $e): array => array_diff_key($e, ['sort_order' => true]), $list);
        }
        return $menu;
    }

    /** @return array<string, mixed> columnas validadas */
    private function fields(array $input, bool $creating): array
    {
        $fields = [];
        $errors = [];
        if ($creating || array_key_exists('name', $input)) {
            $name = Validation::text($input['name'] ?? null, 60);
            if ($name === null) {
                $errors['name'] = self::NAME_ERROR;
            } else {
                $fields['name'] = $name;
            }
        }
        if ($creating || array_key_exists('price', $input)) {
            $cents = Validation::money($input['price'] ?? null);
            if ($cents === null) {
                $errors['price'] = 'Importe ≥ 0 con hasta 2 decimales.';
            } else {
                $fields['price'] = Money::fromCents($cents);
            }
        }
        if (array_key_exists('ingredient_id', $input)) {
            $id = $input['ingredient_id'] === null ? null : Validation::positiveInt($input['ingredient_id']);
            if ($input['ingredient_id'] !== null && $id === null) {
                $errors['ingredient_id'] = 'Entero positivo o null.';
            } else {
                $fields['ingredient_id'] = $id;
            }
        }
        if (array_key_exists('ingredient_quantity', $input)) {
            $milli = $input['ingredient_quantity'] === null ? null : Validation::quantity($input['ingredient_quantity']);
            if ($input['ingredient_quantity'] !== null && $milli === null) {
                $errors['ingredient_quantity'] = 'Cantidad mayor que 0 con hasta 3 decimales.';
            } else {
                $fields['ingredient_quantity'] = $milli === null ? null : Quantity::fromMilli($milli);
            }
        }
        if (array_key_exists('sort_order', $input)) {
            $order = $input['sort_order'];
            if (is_int($order) && $order >= 0 && $order <= 10_000) {
                $fields['sort_order'] = $order;
            } else {
                $errors['sort_order'] = 'Entero entre 0 y 10000.';
            }
        }
        if (!$creating && array_key_exists('is_active', $input)) {
            $active = Validation::bool($input['is_active']);
            if ($active === null) {
                $errors['is_active'] = 'Debe ser true o false.';
            } else {
                $fields['is_active'] = $active;
            }
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }
        return $fields;
    }

    /** Insumo y cantidad van juntos, y el insumo debe existir. */
    private function assertIngredient(array $fields): void
    {
        $ingredientId = $fields['ingredient_id'] ?? null;
        $quantity = $fields['ingredient_quantity'] ?? null;
        if (($ingredientId === null) !== ($quantity === null)) {
            throw ApiException::validation([
                'ingredient_quantity' => 'El insumo y su cantidad van juntos: ambos o ninguno.',
            ]);
        }
        if ($ingredientId !== null && (new IngredientRepository($this->db))->find((int) $ingredientId) === null) {
            throw ApiException::validation(['ingredient_id' => 'Insumo inexistente.']);
        }
    }

    /** @param array<int, list<int>> $byCategory */
    private static function categoriesOf(int $extraId, array $byCategory): array
    {
        $ids = [];
        foreach ($byCategory as $categoryId => $extraIds) {
            if (in_array($extraId, $extraIds, true)) {
                $ids[] = $categoryId;
            }
        }
        return $ids;
    }

    private static function toPublic(array $row): array
    {
        return [
            'id' => (int) $row['id'],
            'name' => $row['name'],
            'price' => $row['price'],
            'ingredient' => $row['ingredient_id'] === null ? null : [
                'id' => (int) $row['ingredient_id'],
                'name' => $row['ingredient_name'],
                'unit' => $row['ingredient_unit'],
                'quantity' => $row['ingredient_quantity'],
            ],
            'sort_order' => (int) $row['sort_order'],
            'is_active' => (bool) $row['is_active'],
            'is_available' => (bool) $row['is_available'],
            'in_stock' => (bool) $row['in_stock'],
            'created_at' => Dates::iso($row['created_at']),
            'updated_at' => Dates::iso($row['updated_at']),
        ];
    }

    /**
     * @template T
     * @param callable(): T $work
     * @return T
     */
    private function mapDuplicateName(callable $work): mixed
    {
        try {
            return $work();
        } catch (PDOException $e) {
            if (Db::isUniqueViolation($e, 'uq_extras_name')) {
                throw ApiException::conflict('EXTRA_NAME_TAKEN', 'Ya existe un extra con ese nombre.');
            }
            throw $e;
        }
    }

    private static function notFound(): ApiException
    {
        return ApiException::notFound('Extra no encontrado.');
    }
}
