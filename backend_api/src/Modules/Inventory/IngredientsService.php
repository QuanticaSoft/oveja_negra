<?php

declare(strict_types=1);

/** Insumos, categorías de insumo y unidades. El stock y el costo solo cambian por movimientos. */
final class IngredientsService
{
    private const NAME_ERROR = 'Requerido, máximo 80 caracteres.';
    private const MIN_STOCK_ERROR = 'Cantidad ≥ 0 con hasta 3 decimales.';

    private readonly IngredientRepository $ingredients;

    public function __construct(private readonly PDO $db, private readonly AuthUser $actor)
    {
        $this->ingredients = new IngredientRepository($db);
    }

    public function units(): array
    {
        return array_map(static fn (array $row): array => ['id' => (int) $row['id'], 'code' => $row['code'], 'name' => $row['name']],
            $this->ingredients->units());
    }

    public function categories(): array
    {
        return array_map(self::categoryToPublic(...), $this->ingredients->categories());
    }

    public function createCategory(array $input): array
    {
        $name = Validation::text($input['name'] ?? null, 60)
            ?? throw ApiException::validation(['name' => 'Requerido, máximo 60 caracteres.']);
        try {
            return Db::transaction($this->db, function () use ($name): array {
                $id = $this->ingredients->insertCategory($name);
                $category = self::categoryToPublic($this->ingredients->findCategory($id));
                Audit::log($this->db, $this->actor->id, 'ingredient_categories', $id, 'create', null, $category);
                return $category;
            });
        } catch (PDOException $e) {
            if (Db::isUniqueViolation($e, 'uq_ingredient_categories_name')) {
                throw ApiException::conflict('INGREDIENT_CATEGORY_NAME_TAKEN', 'Ya existe una categoría de insumo con ese nombre.');
            }
            throw $e;
        }
    }

    /** @return array{data: list<array>, meta: array} */
    public function list(array $query): array
    {
        $filters = [];
        if (isset($query['category_id'])) {
            $filters['category_id'] = Validation::positiveInt($query['category_id'])
                ?? throw ApiException::validation(['category_id' => 'Entero positivo.']);
        }
        foreach (['active', 'low_stock'] as $flag) {
            $value = Validation::boolQuery($query[$flag] ?? null, $flag);
            if ($value !== null) {
                $filters[$flag] = $value;
            }
        }
        if (isset($query['q'])) {
            $filters['q'] = Validation::text($query['q'], 80) ?? throw ApiException::validation(['q' => 'Máximo 80 caracteres.']);
        }
        $pagination = Pagination::fromQuery($query);
        $result = $this->ingredients->list($filters, $pagination->perPage, $pagination->offset());
        return ['data' => array_map(self::toPublic(...), $result['rows']), 'meta' => $pagination->meta($result['total'])];
    }

    public function get(int $id): array
    {
        return self::toPublic($this->ingredients->find($id) ?? throw self::notFound());
    }

    public function create(array $input): array
    {
        $errors = [];
        $name = Validation::text($input['name'] ?? null, 80);
        if ($name === null) {
            $errors['name'] = self::NAME_ERROR;
        }
        $categoryId = Validation::positiveInt($input['category_id'] ?? null);
        if ($categoryId === null) {
            $errors['category_id'] = 'Requerido.';
        }
        $unitId = Validation::positiveInt($input['unit_id'] ?? null);
        if ($unitId === null) {
            $errors['unit_id'] = 'Requerido.';
        }
        $minStock = self::minStock($input['min_stock'] ?? 0);
        if ($minStock === null) {
            $errors['min_stock'] = self::MIN_STOCK_ERROR;
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }

        return $this->mapDuplicateName(fn (): array => Db::transaction($this->db, function () use ($name, $categoryId, $unitId, $minStock): array {
            $this->assertReferences($categoryId, $unitId);
            $id = $this->ingredients->insert($name, $categoryId, $unitId, $minStock);
            $ingredient = $this->get($id);
            Audit::log($this->db, $this->actor->id, 'ingredients', $id, 'create', null, $ingredient);
            return $ingredient;
        }));
    }

    public function update(int $id, array $input): array
    {
        foreach (['current_stock', 'avg_unit_cost'] as $derived) {
            if (array_key_exists($derived, $input)) {
                throw ApiException::validation([$derived => 'Se calcula con los movimientos: usa una compra o un ajuste de inventario.']);
            }
        }
        $fields = [];
        $errors = [];
        if (array_key_exists('name', $input)) {
            $fields['name'] = Validation::text($input['name'], 80);
            if ($fields['name'] === null) {
                $errors['name'] = self::NAME_ERROR;
            }
        }
        foreach (['category_id', 'unit_id'] as $reference) {
            if (array_key_exists($reference, $input)) {
                $fields[$reference] = Validation::positiveInt($input[$reference]);
                if ($fields[$reference] === null) {
                    $errors[$reference] = 'Entero positivo.';
                }
            }
        }
        if (array_key_exists('min_stock', $input)) {
            $fields['min_stock'] = self::minStock($input['min_stock']);
            if ($fields['min_stock'] === null) {
                $errors['min_stock'] = self::MIN_STOCK_ERROR;
            }
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }
        if ($fields === []) {
            throw ApiException::validation([], 'No hay campos para actualizar.');
        }

        return $this->mapDuplicateName(fn (): array => Db::transaction($this->db, function () use ($id, $fields): array {
            $this->ingredients->lockMany([$id]) !== [] || throw self::notFound();
            $before = $this->get($id);
            $this->assertReferences($fields['category_id'] ?? null, $fields['unit_id'] ?? null);
            // El stock y el kardex están en la unidad actual: cambiarla los volvería incoherentes.
            if (isset($fields['unit_id']) && $fields['unit_id'] !== $before['unit']['id'] && $this->ingredients->hasMovements($id)) {
                throw ApiException::conflict('UNIT_LOCKED', 'El insumo ya tiene movimientos: su unidad no se puede cambiar.');
            }
            $this->ingredients->update($id, $fields);
            $after = $this->get($id);
            Audit::log($this->db, $this->actor->id, 'ingredients', $id, 'update', $before, $after);
            return $after;
        }));
    }

    public function setActive(int $id, array $input): array
    {
        $active = Validation::bool($input['is_active'] ?? null)
            ?? throw ApiException::validation(['is_active' => 'Debe ser true o false.']);

        return Db::transaction($this->db, function () use ($id, $active): array {
            $this->ingredients->lockMany([$id]) !== [] || throw self::notFound();
            $before = $this->get($id);
            if ($before['is_active'] === $active) {
                return $before;
            }
            $this->ingredients->update($id, ['is_active' => $active]);
            Audit::log($this->db, $this->actor->id, 'ingredients', $id, $active ? 'activate' : 'deactivate',
                ['is_active' => !$active], ['is_active' => $active]);
            return $this->get($id);
        });
    }

    public static function toPublic(array $row): array
    {
        return [
            'id' => (int) $row['id'],
            'name' => $row['name'],
            'category' => ['id' => (int) $row['category_id'], 'name' => $row['category_name']],
            'unit' => ['id' => (int) $row['unit_id'], 'code' => $row['unit_code'], 'name' => $row['unit_name']],
            'current_stock' => $row['current_stock'],
            'min_stock' => $row['min_stock'],
            'avg_unit_cost' => $row['avg_unit_cost'],
            'is_low_stock' => (bool) $row['is_active'] && (bool) $row['is_low_stock'],
            'is_active' => (bool) $row['is_active'],
            'created_at' => Dates::iso($row['created_at']),
            'updated_at' => Dates::iso($row['updated_at']),
        ];
    }

    private function assertReferences(?int $categoryId, ?int $unitId): void
    {
        $errors = [];
        if ($categoryId !== null && $this->ingredients->findCategory($categoryId) === null) {
            $errors['category_id'] = 'Categoría inexistente.';
        }
        if ($unitId !== null && !$this->ingredients->unitExists($unitId)) {
            $errors['unit_id'] = 'Unidad inexistente.';
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }
    }

    /** Stock mínimo ≥ 0 como NUMERIC ("2.500"); null si no es válido. */
    private static function minStock(mixed $value): ?string
    {
        if ($value === 0 || $value === '0') {
            return '0.000';
        }
        $milli = Validation::quantity($value);
        return $milli === null ? null : Quantity::fromMilli($milli);
    }

    private static function categoryToPublic(array $row): array
    {
        return [
            'id' => (int) $row['id'],
            'name' => $row['name'],
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
            if (Db::isUniqueViolation($e, 'uq_ingredients_name')) {
                throw ApiException::conflict('INGREDIENT_NAME_TAKEN', 'Ya existe un insumo con ese nombre.');
            }
            throw $e;
        }
    }

    private static function notFound(): ApiException
    {
        return ApiException::notFound('Insumo no encontrado.');
    }
}
