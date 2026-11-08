<?php

declare(strict_types=1);

/** Usuario autenticado de la petición actual. */
final class AuthUser
{
    /** @param list<string> $permissions */
    public function __construct(
        public readonly int $id,
        public readonly string $username,
        public readonly string $fullName,
        public readonly string $roleCode,
        public readonly array $permissions,
    ) {
    }

    public function can(string $permission): bool
    {
        return in_array($permission, $this->permissions, true);
    }

    public function toArray(): array
    {
        return [
            'id' => $this->id,
            'username' => $this->username,
            'full_name' => $this->fullName,
            'role' => $this->roleCode,
            'permissions' => $this->permissions,
        ];
    }
}
