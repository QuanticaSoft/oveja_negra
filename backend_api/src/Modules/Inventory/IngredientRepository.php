<?php

declare(strict_types=1);

/** Insumos, sus categorías y las unidades. */
final class IngredientRepository
{
    private const SELECT = 'SELECT i.id, i.name, i.category_id, c.name AS category_name, i.unit_id, u.code AS unit_code,
                                   u.name AS unit_name, i.current_stock, i.min_stock, i.avg_unit_cost, i.is_active,
                                   i.current_stock <= i.min_stock AS is_low_stock, i.created_at, i.updated_at
                            FROM ingredients i
                            JOIN ingredient_categories c ON c.id = i.category_id
                            JOIN units u ON u.id = i.unit_id';

    public function __construct(private readonly PDO $db)
    {
    }

    /**
     * @param array{category_id?: int, active?: bool, low_stock?: bool, q?: string} $filters
     * @return array{rows: list<array>, total: int}
     */
    public function list(array $filters, int $limit, int $offset): array
    {
        $where = [];
        $params = [];
        if (isset($filters['category_id'])) {
            $where[] = 'i.category_id = ?';
            $params[] = $filters['category_id'];
        }
        if (isset($filters['active'])) {
            $where[] = 'i.is_active = ?';
            $params[] = $filters['active'] ? 'true' : 'false';
        }
        if (isset($filters['low_stock'])) {
            // Un insumo inactivo no se repone: no cuenta como stock bajo.
            $where[] = $filters['low_stock'] ? '(i.is_active AND i.current_stock <= i.min_stock)'
                                             : 'NOT (i.is_active AND i.current_stock <= i.min_stock)';
        }
        if (isset($filters['q'])) {
            $where[] = "i.name ILIKE ? ESCAPE '!'";
            $params[] = Validation::likePattern($filters['q']);
        }
        $whereSql = $where === [] ? '' : ' WHERE ' . implode(' AND ', $where);

        $count = $this->db->prepare('SELECT count(*) FROM ingredients i' . $whereSql);
        $count->execute($params);
        $stmt = $this->db->prepare(self::SELECT . $whereSql . ' ORDER BY c.name, i.name LIMIT ? OFFSET ?');
        $stmt->execute([...$params, $limit, $offset]);
        return ['rows' => $stmt->fetchAll(), 'total' => (int) $count->fetchColumn()];
    }

    public function find(int $id): ?array
    {
        $stmt = $this->db->prepare(self::SELECT . ' WHERE i.id = ?');
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row === false ? null : $row;
    }

    /**
     * Bloquea los insumos en orden de id (mismo orden en toda la API: sin interbloqueos).
     *
     * @param list<int> $ids
     * @return array<int, array> por id; los inexistentes no aparecen
     */
    public function lockMany(array $ids): array
    {
        if ($ids === []) {
            return [];
        }
        $ids = array_values(array_unique($ids));
        sort($ids);
        $stmt = $this->db->prepare(
            'SELECT i.id, i.name, i.is_active, i.current_stock, i.avg_unit_cost, u.code AS unit_code
             FROM ingredients i JOIN units u ON u.id = i.unit_id
             WHERE i.id IN (' . implode(', ', array_fill(0, count($ids), '?')) . ')
             ORDER BY i.id FOR UPDATE OF i'
        );
        $stmt->execute($ids);
        return array_column($stmt->fetchAll(), null, 'id');
    }

    public function insert(string $name, int $categoryId, int $unitId, string $minStock): int
    {
        $stmt = $this->db->prepare(
            'INSERT INTO ingredients (name, category_id, unit_id, min_stock) VALUES (?, ?, ?, ?) RETURNING id'
        );
        $stmt->execute([$name, $categoryId, $unitId, $minStock]);
        return (int) $stmt->fetchColumn();
    }

    /** @param array{name?: string, category_id?: int, unit_id?: int, min_stock?: string, is_active?: bool} $fields */
    public function update(int $id, array $fields): void
    {
        $fields = array_intersect_key($fields, array_flip(['name', 'category_id', 'unit_id', 'min_stock', 'is_active']));
        if ($fields === []) {
            return;
        }
        $values = array_map(static fn (mixed $v): mixed => is_bool($v) ? ($v ? 'true' : 'false') : $v, $fields);
        $set = implode(', ', array_map(static fn (string $column): string => "{$column} = ?", array_keys($values)));
        $this->db->prepare("UPDATE ingredients SET {$set} WHERE id = ?")->execute([...array_values($values), $id]);
    }

    public function hasMovements(int $id): bool
    {
        $stmt = $this->db->prepare('SELECT EXISTS (SELECT 1 FROM inventory_movements WHERE ingredient_id = ?)');
        $stmt->execute([$id]);
        return (bool) $stmt->fetchColumn();
    }

    public function categories(): array
    {
        return $this->db->query('SELECT id, name, created_at, updated_at FROM ingredient_categories ORDER BY name')->fetchAll();
    }

    public function findCategory(int $id): ?array
    {
        $stmt = $this->db->prepare('SELECT id, name, created_at, updated_at FROM ingredient_categories WHERE id = ?');
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row === false ? null : $row;
    }

    public function insertCategory(string $name): int
    {
        $stmt = $this->db->prepare('INSERT INTO ingredient_categories (name) VALUES (?) RETURNING id');
        $stmt->execute([$name]);
        return (int) $stmt->fetchColumn();
    }

    public function units(): array
    {
        return $this->db->query('SELECT id, code, name FROM units ORDER BY id')->fetchAll();
    }

    public function unitExists(int $id): bool
    {
        $stmt = $this->db->prepare('SELECT EXISTS (SELECT 1 FROM units WHERE id = ?)');
        $stmt->execute([$id]);
        return (bool) $stmt->fetchColumn();
    }
}
