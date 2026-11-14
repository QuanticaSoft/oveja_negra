<?php

declare(strict_types=1);

final class ExtraRepository
{
    // in_stock: sin insumo vinculado, o con stock suficiente para al menos una porción.
    private const SELECT = 'SELECT e.*, i.name AS ingredient_name, u.code AS ingredient_unit,
                                   (e.ingredient_id IS NULL OR i.current_stock >= e.ingredient_quantity) AS in_stock
                            FROM extras e
                            LEFT JOIN ingredients i ON i.id = e.ingredient_id
                            LEFT JOIN units u ON u.id = i.unit_id';

    public function __construct(private readonly PDO $db)
    {
    }

    public function list(?bool $active): array
    {
        $stmt = $this->db->prepare(self::SELECT . ($active === null ? '' : ' WHERE e.is_active = ?') . ' ORDER BY e.sort_order, e.name');
        $stmt->execute($active === null ? [] : [$active ? 'true' : 'false']);
        return $stmt->fetchAll();
    }

    public function find(int $id, bool $forUpdate = false): ?array
    {
        $stmt = $this->db->prepare(self::SELECT . ' WHERE e.id = ?' . ($forUpdate ? ' FOR UPDATE OF e' : ''));
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row === false ? null : $row;
    }

    /** @param array<string, mixed> $fields columnas ya validadas */
    public function insert(array $fields): int
    {
        $columns = implode(', ', array_keys($fields));
        $placeholders = implode(', ', array_fill(0, count($fields), '?'));
        $stmt = $this->db->prepare("INSERT INTO extras ({$columns}) VALUES ({$placeholders}) RETURNING id");
        $stmt->execute(array_values(self::dbValues($fields)));
        return (int) $stmt->fetchColumn();
    }

    /** @param array<string, mixed> $fields columnas ya validadas */
    public function update(int $id, array $fields): void
    {
        $set = implode(', ', array_map(static fn (string $column): string => "{$column} = ?", array_keys($fields)));
        $this->db->prepare("UPDATE extras SET {$set} WHERE id = ?")->execute([...array_values(self::dbValues($fields)), $id]);
    }

    /** @return array<int, list<int>> ids de extras por categoría */
    public function extraIdsByCategory(): array
    {
        $grouped = [];
        foreach ($this->db->query('SELECT category_id, extra_id FROM category_extras ORDER BY category_id, extra_id')->fetchAll() as $row) {
            $grouped[(int) $row['category_id']][] = (int) $row['extra_id'];
        }
        return $grouped;
    }

    /** @return list<int> */
    public function extraIdsOf(int $categoryId): array
    {
        $stmt = $this->db->prepare('SELECT extra_id FROM category_extras WHERE category_id = ? ORDER BY extra_id');
        $stmt->execute([$categoryId]);
        return array_map('intval', $stmt->fetchAll(PDO::FETCH_COLUMN));
    }

    /** @param list<int> $extraIds */
    public function replaceCategoryExtras(int $categoryId, array $extraIds): void
    {
        $this->db->prepare('DELETE FROM category_extras WHERE category_id = ?')->execute([$categoryId]);
        $insert = $this->db->prepare('INSERT INTO category_extras (category_id, extra_id) VALUES (?, ?)');
        foreach ($extraIds as $extraId) {
            $insert->execute([$categoryId, $extraId]);
        }
    }

    /**
     * Extras pedidos con lo necesario para venderlos: precio, si están permitidos en la categoría del
     * producto, si se pueden vender y el insumo que descuentan.
     *
     * @param list<int> $extraIds
     * @return array<int, array> por id
     */
    public function forSale(array $extraIds): array
    {
        if ($extraIds === []) {
            return [];
        }
        $stmt = $this->db->prepare(
            'SELECT e.id, e.name, e.price, e.ingredient_id, e.ingredient_quantity, e.is_active AND e.is_available AS sellable
             FROM extras e WHERE e.id IN (' . implode(', ', array_fill(0, count($extraIds), '?')) . ')'
        );
        $stmt->execute(array_values(array_unique($extraIds)));
        return array_column($stmt->fetchAll(), null, 'id');
    }

    private static function dbValues(array $fields): array
    {
        return array_map(static fn (mixed $v): mixed => is_bool($v) ? ($v ? 'true' : 'false') : $v, $fields);
    }
}
