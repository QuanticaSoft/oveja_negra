<?php

declare(strict_types=1);

final class UsersService
{
    private const FULL_NAME_ERROR = 'Requerido, máximo 120 caracteres.';
    private const PASSWORD_ERROR = 'Entre 8 y 72 caracteres.';

    private readonly UserRepository $users;
    private readonly RoleRepository $roles;
    private readonly RefreshTokenRepository $tokens;

    public function __construct(private readonly PDO $db, private readonly AuthUser $actor)
    {
        $this->users = new UserRepository($db);
        $this->roles = new RoleRepository($db);
        $this->tokens = new RefreshTokenRepository($db);
    }

    /** @return array{data: list<array>, meta: array} */
    public function list(array $query): array
    {
        $active = Validation::boolQuery($query['active'] ?? null, 'active');
        $role = isset($query['role']) ? strtoupper($query['role']) : null;
        $pagination = Pagination::fromQuery($query);

        $result = $this->users->list($active, $role, $pagination->perPage, $pagination->offset());
        return ['data' => $result['rows'], 'meta' => $pagination->meta($result['total'])];
    }

    public function get(int $id): array
    {
        return $this->users->find($id) ?? throw self::notFound();
    }

    public function create(array $input): array
    {
        $errors = [];
        $username = Validation::username($input['username'] ?? null);
        if ($username === null) {
            $errors['username'] = '3 a 40 caracteres: letras minúsculas, números, punto, guion o guion bajo.';
        }
        $fullName = Validation::text($input['full_name'] ?? null, 120);
        if ($fullName === null) {
            $errors['full_name'] = self::FULL_NAME_ERROR;
        }
        $phone = $this->optionalPhone($input, $errors);
        $roleId = $this->roleIdFrom($input, $errors);
        $password = Validation::password($input['password'] ?? null);
        if ($password === null) {
            $errors['password'] = self::PASSWORD_ERROR;
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }

        return $this->mapUniqueViolations(fn (): array => Db::transaction($this->db, function () use ($username, $fullName, $phone, $roleId, $password): array {
            $id = $this->users->insert($username, $fullName, $phone, $roleId, Passwords::hash($password));
            $user = $this->users->find($id);
            Audit::log($this->db, $this->actor->id, 'users', $id, 'create', null, $user);
            return $user;
        }));
    }

    public function update(int $id, array $input): array
    {
        $errors = [];
        $fields = [];
        if (array_key_exists('full_name', $input)) {
            $fields['full_name'] = Validation::text($input['full_name'], 120);
            if ($fields['full_name'] === null) {
                $errors['full_name'] = self::FULL_NAME_ERROR;
            }
        }
        if (array_key_exists('phone', $input)) {
            $fields['phone'] = $this->optionalPhone($input, $errors);
        }
        $newRoleCode = null;
        if (array_key_exists('role_code', $input)) {
            $fields['role_id'] = $this->roleIdFrom($input, $errors);
            $newRoleCode = is_string($input['role_code']) ? strtoupper($input['role_code']) : null;
        }
        if ($errors !== []) {
            throw ApiException::validation($errors);
        }
        if ($fields === []) {
            throw ApiException::validation([], 'No hay campos para actualizar.');
        }

        return $this->mapUniqueViolations(fn (): array => Db::transaction($this->db, function () use ($id, $fields, $newRoleCode): array {
            $before = $this->users->find($id, forUpdate: true) ?? throw self::notFound();
            if ($newRoleCode !== null && $newRoleCode !== $before['role']) {
                if ($id === $this->actor->id) {
                    throw ApiException::conflict('CANNOT_CHANGE_OWN_ROLE', 'No puedes cambiar tu propio rol.');
                }
                if ($before['role'] === 'ADMIN' && $before['is_active']) {
                    $this->ensureNotLastAdmin($id);
                }
            }
            $this->users->update($id, $fields);
            $after = $this->users->find($id);
            Audit::log($this->db, $this->actor->id, 'users', $id, 'update', $before, $after);
            return $after;
        }));
    }

    public function setStatus(int $id, array $input): array
    {
        $active = Validation::bool($input['is_active'] ?? null)
            ?? throw ApiException::validation(['is_active' => 'Debe ser true o false.']);

        return Db::transaction($this->db, function () use ($id, $active): array {
            $before = $this->users->find($id, forUpdate: true) ?? throw self::notFound();
            if ($before['is_active'] === $active) {
                return $before;
            }
            if (!$active) {
                if ($id === $this->actor->id) {
                    throw ApiException::conflict('CANNOT_DEACTIVATE_SELF', 'No puedes desactivar tu propia cuenta.');
                }
                if ($before['role'] === 'ADMIN') {
                    $this->ensureNotLastAdmin($id);
                }
                $this->tokens->revokeAllForUser($id);
            }
            $this->users->setActive($id, $active);
            $after = $this->users->find($id);
            Audit::log($this->db, $this->actor->id, 'users', $id, $active ? 'activate' : 'deactivate', $before, $after);
            return $after;
        });
    }

    public function resetPassword(int $id, array $input): array
    {
        $password = Validation::password($input['new_password'] ?? null)
            ?? throw ApiException::validation(['new_password' => self::PASSWORD_ERROR]);

        return Db::transaction($this->db, function () use ($id, $password): array {
            $user = $this->users->find($id, forUpdate: true) ?? throw self::notFound();
            $this->users->setPasswordHash($id, Passwords::hash($password));
            $this->tokens->revokeAllForUser($id);
            Audit::log($this->db, $this->actor->id, 'users', $id, 'reset_password');
            return $user;
        });
    }

    /** Debe correr dentro de la transacción: bloquea a los ADMIN activos. */
    private function ensureNotLastAdmin(int $targetId): void
    {
        $activeAdmins = $this->users->lockActiveAdminIds();
        if (array_diff($activeAdmins, [$targetId]) === []) {
            throw ApiException::conflict('LAST_ADMIN', 'Debe quedar al menos un ADMIN activo.');
        }
    }

    private function optionalPhone(array $input, array &$errors): ?string
    {
        $phone = $input['phone'] ?? null;
        if ($phone === null || $phone === '') {
            return null;
        }
        $valid = Validation::phone($phone);
        if ($valid === null) {
            $errors['phone'] = 'Formato +591 seguido de 8 dígitos.';
        }
        return $valid;
    }

    private function roleIdFrom(array $input, array &$errors): ?int
    {
        $code = $input['role_code'] ?? null;
        $roleId = is_string($code) ? $this->roles->findIdByCode(strtoupper($code)) : null;
        if ($roleId === null) {
            $errors['role_code'] = 'Rol inexistente (ADMIN, CAJERO o ENCARGADO).';
        }
        return $roleId;
    }

    /**
     * @template T
     * @param callable(): T $work
     * @return T
     */
    private function mapUniqueViolations(callable $work): mixed
    {
        try {
            return $work();
        } catch (PDOException $e) {
            if ($e->getCode() === '23505' && str_contains($e->getMessage(), 'users_username_key')) {
                throw ApiException::conflict('USERNAME_TAKEN', 'Ese nombre de usuario ya existe.');
            }
            if ($e->getCode() === '23505' && str_contains($e->getMessage(), 'users_phone_key')) {
                throw ApiException::conflict('PHONE_TAKEN', 'Ese celular ya está registrado.');
            }
            throw $e;
        }
    }

    private static function notFound(): ApiException
    {
        return ApiException::notFound('Usuario no encontrado.');
    }
}
