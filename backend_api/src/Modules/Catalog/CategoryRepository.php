<?php

declare(strict_types=1);

final class CategoryRepository
{
    public function __construct(private readonly PDO $db)
    {
    }

    public function list(?bool $active): array
    {
        $sql = 'SELECT id, name, sort_order, is_active, created_at, updated_at FROM categories';
        $params = [];
        if ($active !== null) {
            $sql .= ' WHERE is_active = ?';
            $params[] = $active ? 'true' : 'false';
        }
        $stmt = $this->db->prepare($sql . ' ORDER BY sort_order, name');
        $stmt->execute($params);
        return array_map(self::toPublic(...), $stmt->fetchAll());
    }

    public function find(int $id, bool $forUpdate = false): ?array
    {
        $stmt = $this->db->prepare(
            'SELECT id, name, sort_order, is_active, created_at, updated_at FROM categories WHERE id = ?'
            . ($forUpdate ? ' FOR UPDATE' : '')
        );
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row === false ? null : self::toPublic($row);
    }

    public function insert(string $name, int $sortOrder): int
    {
        $stmt = $this->db->prepare('INSERT INTO categories (name, sort_order) VALUES (?, ?) RETURNING id');
        $stmt->execute([$name, $sortOrder]);
        return (int) $stmt->fetchColumn();
    }

    /** @param array{name?: string, sort_order?: int, is_active?: bool} $fields */
    public function update(int $id, array $fields): void
    {
        $fields = array_intersect_key($fields, array_flip(['name', 'sort_order', 'is_active']));
        if ($fields === []) {
            return;
        }
        $values = array_map(static fn (mixed $v): mixed => is_bool($v) ? ($v ? 'true' : 'false') : $v, $fields);
        $set = implode(', ', array_map(static fn (string $column): string => "{$column} = ?", array_keys($values)));
        $this->db->prepare("UPDATE categories SET {$set} WHERE id = ?")->execute([...array_values($values), $id]);
    }

    private static function toPublic(array $row): array
    {
        return [
            'id' => (int) $row['id'],
            'name' => $row['name'],
            'sort_order' => (int) $row['sort_order'],
            'is_active' => (bool) $row['is_active'],
            'created_at' => Dates::iso($row['created_at']),
            'updated_at' => Dates::iso($row['updated_at']),
        ];
    }
}
