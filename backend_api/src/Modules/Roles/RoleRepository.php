<?php

declare(strict_types=1);

final class RoleRepository
{
    public function __construct(private readonly PDO $db)
    {
    }

    public function findIdByCode(string $code): ?int
    {
        $stmt = $this->db->prepare('SELECT id FROM roles WHERE code = ?');
        $stmt->execute([$code]);
        $id = $stmt->fetchColumn();
        return $id === false ? null : (int) $id;
    }

    public function find(int $id, bool $forUpdate = false): ?array
    {
        $stmt = $this->db->prepare('SELECT id, code, name FROM roles WHERE id = ?' . ($forUpdate ? ' FOR UPDATE' : ''));
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row === false ? null : $row + ['permissions' => $this->permissionCodes($id)];
    }

    public function listWithPermissions(): array
    {
        $rows = $this->db->query(
            "SELECT r.id, r.code, r.name,
                    COALESCE(json_agg(p.code ORDER BY p.code) FILTER (WHERE p.code IS NOT NULL), '[]') AS permissions
             FROM roles r
             LEFT JOIN role_permissions rp ON rp.role_id = r.id
             LEFT JOIN permissions p ON p.id = rp.permission_id
             GROUP BY r.id ORDER BY r.id"
        )->fetchAll();
        return array_map(static fn (array $row): array => [
            'id' => (int) $row['id'],
            'code' => $row['code'],
            'name' => $row['name'],
            'permissions' => json_decode($row['permissions'], true),
        ], $rows);
    }

    public function listPermissions(): array
    {
        return $this->db->query('SELECT code, description FROM permissions ORDER BY code')->fetchAll();
    }

    /** @return list<string> */
    public function permissionCodes(int $roleId): array
    {
        $stmt = $this->db->prepare(
            'SELECT p.code FROM role_permissions rp JOIN permissions p ON p.id = rp.permission_id
             WHERE rp.role_id = ? ORDER BY p.code'
        );
        $stmt->execute([$roleId]);
        return $stmt->fetchAll(PDO::FETCH_COLUMN);
    }

    /** @return array<string, int> código → id, solo de los que existen */
    public function permissionIdsByCode(array $codes): array
    {
        if ($codes === []) {
            return [];
        }
        $placeholders = implode(', ', array_fill(0, count($codes), '?'));
        $stmt = $this->db->prepare("SELECT code, id FROM permissions WHERE code IN ({$placeholders})");
        $stmt->execute(array_values($codes));
        return array_map('intval', $stmt->fetchAll(PDO::FETCH_KEY_PAIR));
    }

    /** @param list<int> $permissionIds */
    public function replacePermissions(int $roleId, array $permissionIds): void
    {
        $this->db->prepare('DELETE FROM role_permissions WHERE role_id = ?')->execute([$roleId]);
        $insert = $this->db->prepare('INSERT INTO role_permissions (role_id, permission_id) VALUES (?, ?)');
        foreach ($permissionIds as $permissionId) {
            $insert->execute([$roleId, $permissionId]);
        }
    }
}
