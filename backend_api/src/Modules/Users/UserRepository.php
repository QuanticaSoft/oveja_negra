<?php

declare(strict_types=1);

final class UserRepository
{
    private const PUBLIC_SELECT = 'SELECT u.id, u.username, u.full_name, u.phone, r.code AS role, u.is_active,
                                          u.last_login_at, u.created_at, u.updated_at
                                   FROM users u JOIN roles r ON r.id = u.role_id';

    public function __construct(private readonly PDO $db)
    {
    }

    public function findActiveAuthUser(int $id): ?AuthUser
    {
        $stmt = $this->db->prepare(
            "SELECT u.id, u.username, u.full_name, r.code AS role,
                    COALESCE((SELECT json_agg(p.code ORDER BY p.code)
                              FROM role_permissions rp JOIN permissions p ON p.id = rp.permission_id
                              WHERE rp.role_id = u.role_id), '[]') AS permissions
             FROM users u JOIN roles r ON r.id = u.role_id
             WHERE u.id = ? AND u.is_active"
        );
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        if ($row === false) {
            return null;
        }
        return new AuthUser(
            (int) $row['id'], $row['username'], $row['full_name'], $row['role'],
            json_decode($row['permissions'], true),
        );
    }

    /** @return array{id: int, password_hash: string, is_active: bool}|null */
    public function findForLogin(string $identifier): ?array
    {
        $stmt = $this->db->prepare('SELECT id, password_hash, is_active FROM users WHERE username = ? OR phone = ? LIMIT 1');
        $stmt->execute([$identifier, $identifier]);
        $row = $stmt->fetch();
        return $row === false ? null : $row;
    }

    public function findPasswordHash(int $id): ?string
    {
        $stmt = $this->db->prepare('SELECT password_hash FROM users WHERE id = ?');
        $stmt->execute([$id]);
        $hash = $stmt->fetchColumn();
        return $hash === false ? null : $hash;
    }

    public function find(int $id, bool $forUpdate = false): ?array
    {
        $stmt = $this->db->prepare(self::PUBLIC_SELECT . ' WHERE u.id = ?' . ($forUpdate ? ' FOR UPDATE OF u' : ''));
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row === false ? null : self::toPublic($row);
    }

    /** @return array{rows: list<array>, total: int} */
    public function list(?bool $active, ?string $roleCode, int $limit, int $offset): array
    {
        $where = [];
        $params = [];
        if ($active !== null) {
            $where[] = 'u.is_active = ?';
            $params[] = $active ? 'true' : 'false';
        }
        if ($roleCode !== null) {
            $where[] = 'r.code = ?';
            $params[] = $roleCode;
        }
        $whereSql = $where === [] ? '' : ' WHERE ' . implode(' AND ', $where);

        $count = $this->db->prepare('SELECT count(*) FROM users u JOIN roles r ON r.id = u.role_id' . $whereSql);
        $count->execute($params);

        $stmt = $this->db->prepare(self::PUBLIC_SELECT . $whereSql . ' ORDER BY u.full_name, u.id LIMIT ? OFFSET ?');
        $stmt->execute([...$params, $limit, $offset]);

        return [
            'rows' => array_map(self::toPublic(...), $stmt->fetchAll()),
            'total' => (int) $count->fetchColumn(),
        ];
    }

    public function insert(string $username, string $fullName, ?string $phone, int $roleId, string $passwordHash): int
    {
        $stmt = $this->db->prepare(
            'INSERT INTO users (username, full_name, phone, role_id, password_hash) VALUES (?, ?, ?, ?, ?) RETURNING id'
        );
        $stmt->execute([$username, $fullName, $phone, $roleId, $passwordHash]);
        return (int) $stmt->fetchColumn();
    }

    /** @param array{full_name?: string, phone?: ?string, role_id?: int} $fields */
    public function update(int $id, array $fields): void
    {
        $allowed = array_intersect_key($fields, array_flip(['full_name', 'phone', 'role_id']));
        if ($allowed === []) {
            return;
        }
        $set = implode(', ', array_map(static fn (string $column): string => "{$column} = ?", array_keys($allowed)));
        $this->db->prepare("UPDATE users SET {$set} WHERE id = ?")->execute([...array_values($allowed), $id]);
    }

    public function setPasswordHash(int $id, string $hash): void
    {
        $this->db->prepare('UPDATE users SET password_hash = ? WHERE id = ?')->execute([$hash, $id]);
    }

    public function setActive(int $id, bool $active): void
    {
        $this->db->prepare('UPDATE users SET is_active = ? WHERE id = ?')->execute([$active ? 'true' : 'false', $id]);
    }

    public function touchLastLogin(int $id): void
    {
        $this->db->prepare('UPDATE users SET last_login_at = now() WHERE id = ?')->execute([$id]);
    }

    /**
     * Bloquea las filas de los ADMIN activos: dos peticiones simultáneas no pueden
     * desactivar cada una "al otro" y dejar el sistema sin administradores.
     *
     * @return list<int>
     */
    public function lockActiveAdminIds(): array
    {
        $stmt = $this->db->query(
            "SELECT u.id FROM users u JOIN roles r ON r.id = u.role_id
             WHERE r.code = 'ADMIN' AND u.is_active ORDER BY u.id FOR UPDATE OF u"
        );
        return array_map('intval', $stmt->fetchAll(PDO::FETCH_COLUMN));
    }

    public function adminExists(): bool
    {
        return (bool) $this->db->query(
            "SELECT EXISTS (SELECT 1 FROM users u JOIN roles r ON r.id = u.role_id WHERE r.code = 'ADMIN')"
        )->fetchColumn();
    }

    private static function toPublic(array $row): array
    {
        return [
            'id' => (int) $row['id'],
            'username' => $row['username'],
            'full_name' => $row['full_name'],
            'phone' => $row['phone'],
            'role' => $row['role'],
            'is_active' => (bool) $row['is_active'],
            'last_login_at' => Dates::iso($row['last_login_at']),
            'created_at' => Dates::iso($row['created_at']),
            'updated_at' => Dates::iso($row['updated_at']),
        ];
    }
}
