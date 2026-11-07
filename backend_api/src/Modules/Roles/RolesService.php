<?php

declare(strict_types=1);

final class RolesService
{
    // Sin estos dos, nadie podría volver a administrar usuarios ni permisos.
    private const ADMIN_REQUIRED = ['users.manage', 'roles.manage'];

    private readonly RoleRepository $roles;

    public function __construct(private readonly PDO $db, private readonly AuthUser $actor)
    {
        $this->roles = new RoleRepository($db);
    }

    public function list(): array
    {
        return $this->roles->listWithPermissions();
    }

    public function permissions(): array
    {
        return $this->roles->listPermissions();
    }

    public function replacePermissions(int $roleId, array $input): array
    {
        $codes = $input['permissions'] ?? null;
        if (!is_array($codes) || !array_is_list($codes) || array_filter($codes, 'is_string') !== $codes) {
            throw ApiException::validation(['permissions' => 'Debe ser una lista de códigos de permiso.']);
        }
        $codes = array_values(array_unique($codes));
        $ids = $this->roles->permissionIdsByCode($codes);
        $unknown = array_values(array_diff($codes, array_keys($ids)));
        if ($unknown !== []) {
            throw ApiException::validation(['permissions' => 'Desconocidos: ' . implode(', ', $unknown)]);
        }

        return Db::transaction($this->db, function () use ($roleId, $codes, $ids): array {
            $role = $this->roles->find($roleId, forUpdate: true) ?? throw ApiException::notFound('Rol no encontrado.');
            if ($role['code'] === 'ADMIN' && array_diff(self::ADMIN_REQUIRED, $codes) !== []) {
                throw ApiException::conflict('ADMIN_PERMISSIONS_REQUIRED',
                    'El rol ADMIN debe conservar ' . implode(' y ', self::ADMIN_REQUIRED) . '.');
            }
            $this->roles->replacePermissions($roleId, array_values($ids));
            $after = $this->roles->find($roleId);
            Audit::log($this->db, $this->actor->id, 'roles', $roleId, 'replace_permissions',
                ['permissions' => $role['permissions']], ['permissions' => $after['permissions']]);
            return self::toPublic($after);
        });
    }

    private static function toPublic(array $role): array
    {
        return ['id' => (int) $role['id'], 'code' => $role['code'], 'name' => $role['name'], 'permissions' => $role['permissions']];
    }
}
