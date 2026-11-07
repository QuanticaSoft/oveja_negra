<?php

declare(strict_types=1);

final class AuthMiddleware
{
    /**
     * Valida el JWT de X-Auth-Token y el permiso que declara la ruta. El usuario y sus permisos
     * se leen de la BD en cada petición: desactivar a alguien o cambiar un rol rige al instante,
     * sin esperar a que expire su access token.
     */
    public static function authenticate(PDO $db, ?string $token, string $permission, string $secret, int $now): AuthUser
    {
        if ($token === null) {
            throw new ApiException('UNAUTHENTICATED', 'Sesión requerida.', 401);
        }
        try {
            $claims = Jwt::decode($token, $secret, $now);
        } catch (InvalidArgumentException) {
            throw new ApiException('UNAUTHENTICATED', 'Sesión inválida o expirada.', 401);
        }
        if (!is_int($claims['sub'] ?? null)) {
            throw new ApiException('UNAUTHENTICATED', 'Sesión inválida o expirada.', 401);
        }

        $user = (new UserRepository($db))->findActiveAuthUser($claims['sub']);
        if ($user === null) {
            throw new ApiException('USER_INACTIVE', 'La cuenta no existe o está desactivada.', 401);
        }
        if ($permission !== Router::SESSION && !$user->can($permission)) {
            throw new ApiException('FORBIDDEN', 'No tienes permiso para esta acción.', 403);
        }
        return $user;
    }
}
