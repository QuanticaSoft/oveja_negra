<?php

declare(strict_types=1);

/** Devuelve filas crudas: ProductsService arma la forma pública (URLs de imagen, etc.). */
final class ProductRepository
{
    private const SELECT = 'SELECT p.id, p.category_id, c.name AS category_name, p.name, p.description, p.price,
                                   p.image_path, p.is_active, p.is_available, p.created_at, p.updated_at
                            FROM products p JOIN categories c ON c.id = p.category_id';

    public function __construct(private readonly PDO $db)
    {
    }

    /**
     * @param array{category_id?: int, active?: bool, available?: bool, q?: string} $filters
     * @return array{rows: list<array>, total: int}
     */
    public function list(array $filters, int $limit, int $offset): array
    {
        $where = [];
        $params = [];
        if (isset($filters['category_id'])) {
            $where[] = 'p.category_id = ?';
            $params[] = $filters['category_id'];
        }
        if (isset($filters['active'])) {
            $where[] = 'p.is_active = ?';
            $params[] = $filters['active'] ? 'true' : 'false';
        }
        if (isset($filters['available'])) {
            $where[] = 'p.is_available = ?';
            $params[] = $filters['available'] ? 'true' : 'false';
        }
        if (isset($filters['q'])) {
            $where[] = "(p.name ILIKE ? ESCAPE '!' OR p.description ILIKE ? ESCAPE '!')";
            $pattern = Validation::likePattern($filters['q']);
            array_push($params, $pattern, $pattern);
        }
        $whereSql = $where === [] ? '' : ' WHERE ' . implode(' AND ', $where);

        $count = $this->db->prepare('SELECT count(*) FROM products p' . $whereSql);
        $count->execute($params);
        $stmt = $this->db->prepare(self::SELECT . $whereSql . ' ORDER BY c.sort_order, c.name, p.name LIMIT ? OFFSET ?');
        $stmt->execute([...$params, $limit, $offset]);

        return ['rows' => $stmt->fetchAll(), 'total' => (int) $count->fetchColumn()];
    }

    public function find(int $id, bool $forUpdate = false): ?array
    {
        $stmt = $this->db->prepare(self::SELECT . ' WHERE p.id = ?' . ($forUpdate ? ' FOR UPDATE OF p' : ''));
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row === false ? null : $row;
    }

    /** Categorías activas con sus productos activos, en el orden de la cartilla. */
    public function menuRows(): array
    {
        return $this->db->query(
            'SELECT c.id AS category_id, c.name AS category_name, p.id, p.name, p.description, p.price,
                    p.image_path, p.is_available
             FROM categories c JOIN products p ON p.category_id = c.id
             WHERE c.is_active AND p.is_active
             ORDER BY c.sort_order, c.name, p.name'
        )->fetchAll();
    }

    public function insert(int $categoryId, string $name, ?string $description, string $price): int
    {
        $stmt = $this->db->prepare(
            'INSERT INTO products (category_id, name, description, price) VALUES (?, ?, ?, ?) RETURNING id'
        );
        $stmt->execute([$categoryId, $name, $description, $price]);
        return (int) $stmt->fetchColumn();
    }

    /** @param array{category_id?: int, name?: string, description?: ?string} $fields */
    public function update(int $id, array $fields): void
    {
        $fields = array_intersect_key($fields, array_flip(['category_id', 'name', 'description']));
        if ($fields === []) {
            return;
        }
        $set = implode(', ', array_map(static fn (string $column): string => "{$column} = ?", array_keys($fields)));
        $this->db->prepare("UPDATE products SET {$set} WHERE id = ?")->execute([...array_values($fields), $id]);
    }

    public function setPrice(int $id, string $price): void
    {
        $this->db->prepare('UPDATE products SET price = ? WHERE id = ?')->execute([$price, $id]);
    }

    public function setFlag(int $id, string $column, bool $value): void
    {
        if (!in_array($column, ['is_active', 'is_available'], true)) {
            throw new InvalidArgumentException("Columna no permitida: {$column}");
        }
        $this->db->prepare("UPDATE products SET {$column} = ? WHERE id = ?")->execute([$value ? 'true' : 'false', $id]);
    }

    public function setImagePath(int $id, string $path): void
    {
        $this->db->prepare('UPDATE products SET image_path = ? WHERE id = ?')->execute([$path, $id]);
    }

    public function insertPriceChange(int $productId, string $oldPrice, string $newPrice, int $userId): void
    {
        $this->db->prepare(
            'INSERT INTO product_price_history (product_id, old_price, new_price, changed_by) VALUES (?, ?, ?, ?)'
        )->execute([$productId, $oldPrice, $newPrice, $userId]);
    }

    public function priceHistory(int $productId): array
    {
        $stmt = $this->db->prepare(
            'SELECT h.old_price, h.new_price, h.created_at AS changed_at, u.id AS user_id, u.full_name
             FROM product_price_history h JOIN users u ON u.id = h.changed_by
             WHERE h.product_id = ? ORDER BY h.id DESC'
        );
        $stmt->execute([$productId]);
        return array_map(static fn (array $row): array => [
            'old_price' => $row['old_price'],
            'new_price' => $row['new_price'],
            'changed_at' => Dates::iso($row['changed_at']),
            'changed_by' => ['id' => (int) $row['user_id'], 'full_name' => $row['full_name']],
        ], $stmt->fetchAll());
    }
}
