<?php

declare(strict_types=1);

final class ExpenseCategoriesService
{
    private const SELECT = 'SELECT id, name, is_active, created_at, updated_at FROM expense_categories';
    private const NAME_ERROR = 'Requerido, máximo 60 caracteres.';

    public function __construct(private readonly PDO $db, private readonly AuthUser $actor)
    {
    }

    public function list(array $query): array
    {
        $active = Validation::boolQuery($query['active'] ?? null, 'active');
        $stmt = $this->db->prepare(self::SELECT . ($active === null ? '' : ' WHERE is_active = ?') . ' ORDER BY name');
        $stmt->execute($active === null ? [] : [$active ? 'true' : 'false']);
        return array_map(self::toPublic(...), $stmt->fetchAll());
    }

    public function find(int $id, bool $forUpdate = false): ?array
    {
        $stmt = $this->db->prepare(self::SELECT . ' WHERE id = ?' . ($forUpdate ? ' FOR UPDATE' : ''));
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row === false ? null : self::toPublic($row);
    }

    public function create(array $input): array
    {
        $name = Validation::text($input['name'] ?? null, 60) ?? throw ApiException::validation(['name' => self::NAME_ERROR]);
        return $this->mapDuplicateName(fn (): array => Db::transaction($this->db, function () use ($name): array {
            $stmt = $this->db->prepare('INSERT INTO expense_categories (name) VALUES (?) RETURNING id');
            $stmt->execute([$name]);
            $category = $this->find((int) $stmt->fetchColumn());
            Audit::log($this->db, $this->actor->id, 'expense_categories', $category['id'], 'create', null, $category);
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
        if (array_key_exists('is_active', $input)) {
            $active = Validation::bool($input['is_active']);
            if ($active === null) {
                $errors['is_active'] = 'Debe ser true o false.';
            }
            $fields['is_active'] = $active ? 'true' : 'false';
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }
        if ($fields === []) {
            throw ApiException::validation([], 'No hay campos para actualizar.');
        }

        return $this->mapDuplicateName(fn (): array => Db::transaction($this->db, function () use ($id, $fields): array {
            $before = $this->find($id, forUpdate: true) ?? throw ApiException::notFound('Categoría de gasto no encontrada.');
            $set = implode(', ', array_map(static fn (string $column): string => "{$column} = ?", array_keys($fields)));
            $this->db->prepare("UPDATE expense_categories SET {$set} WHERE id = ?")->execute([...array_values($fields), $id]);
            $after = $this->find($id);
            Audit::log($this->db, $this->actor->id, 'expense_categories', $id, 'update', $before, $after);
            return $after;
        }));
    }

    private static function toPublic(array $row): array
    {
        return [
            'id' => (int) $row['id'],
            'name' => $row['name'],
            'is_active' => (bool) $row['is_active'],
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
            if (Db::isUniqueViolation($e, 'uq_expense_categories_name')) {
                throw ApiException::conflict('EXPENSE_CATEGORY_NAME_TAKEN', 'Ya existe una categoría de gasto con ese nombre.');
            }
            throw $e;
        }
    }
}
