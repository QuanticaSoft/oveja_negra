<?php

declare(strict_types=1);

final class CategoriesService
{
    private const NAME_ERROR = 'Requerido, máximo 60 caracteres.';

    private readonly CategoryRepository $categories;

    public function __construct(private readonly PDO $db, private readonly AuthUser $actor)
    {
        $this->categories = new CategoryRepository($db);
    }

    public function list(array $query): array
    {
        return $this->categories->list(Validation::boolQuery($query['active'] ?? null, 'active'));
    }

    public function create(array $input): array
    {
        $name = Validation::text($input['name'] ?? null, 60) ?? throw ApiException::validation(['name' => self::NAME_ERROR]);
        $sortOrder = self::sortOrder($input['sort_order'] ?? 0);

        return self::mapDuplicateName(fn (): array => Db::transaction($this->db, function () use ($name, $sortOrder): array {
            $id = $this->categories->insert($name, $sortOrder);
            $category = $this->categories->find($id);
            Audit::log($this->db, $this->actor->id, 'categories', $id, 'create', null, $category);
            return $category;
        }));
    }

    public function update(int $id, array $input): array
    {
        $fields = [];
        $errors = [];
        if (array_key_exists('name', $input)) {
            $fields['name'] = Validation::text($input['name'], 60);
            if ($fields['name'] === null) {
                $errors['name'] = self::NAME_ERROR;
            }
        }
        if (array_key_exists('sort_order', $input)) {
            $fields['sort_order'] = self::sortOrder($input['sort_order']);
        }
        if (array_key_exists('is_active', $input)) {
            $fields['is_active'] = Validation::bool($input['is_active']);
            if ($fields['is_active'] === null) {
                $errors['is_active'] = 'Debe ser true o false.';
            }
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }
        if ($fields === []) {
            throw ApiException::validation([], 'No hay campos para actualizar.');
        }

        return self::mapDuplicateName(fn (): array => Db::transaction($this->db, function () use ($id, $fields): array {
            $before = $this->categories->find($id, forUpdate: true) ?? throw ApiException::notFound('Categoría no encontrada.');
            $this->categories->update($id, $fields);
            $after = $this->categories->find($id);
            Audit::log($this->db, $this->actor->id, 'categories', $id, 'update', $before, $after);
            return $after;
        }));
    }

    private static function sortOrder(mixed $value): int
    {
        if (!is_int($value) || $value < 0 || $value > 10_000) {
            throw ApiException::validation(['sort_order' => 'Entero entre 0 y 10000.']);
        }
        return $value;
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
            if ($e->getCode() === '23505' && str_contains($e->getMessage(), 'uq_categories_name')) {
                throw ApiException::conflict('CATEGORY_NAME_TAKEN', 'Ya existe una categoría con ese nombre.');
            }
            throw $e;
        }
    }
}
