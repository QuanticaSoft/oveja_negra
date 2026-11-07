<?php

declare(strict_types=1);

final class AuthService
{
    private readonly UserRepository $users;
    private readonly RefreshTokenRepository $tokens;
    private readonly LoginRateLimiter $rateLimiter;

    public function __construct(
        private readonly PDO $db,
        private readonly array $config,
        private readonly string $jwtSecret,
    ) {
        $this->users = new UserRepository($db);
        $this->tokens = new RefreshTokenRepository($db);
        $limits = $config['login_rate_limit'];
        $this->rateLimiter = new LoginRateLimiter(
            $db, $limits['window_minutes'], $limits['max_failures_per_identifier'], $limits['max_failures_per_ip']);
    }

    /** @param mixed $identifier usuario o celular +591… */
    public function login(mixed $identifier, mixed $password, string $ip, ?string $userAgent): array
    {
        $identifier = is_string($identifier) ? strtolower(trim($identifier)) : '';
        if ($identifier === '' || mb_strlen($identifier) > 120 || !is_string($password) || $password === '' || strlen($password) > 200) {
            throw ApiException::validation(
                ['identifier' => 'Requerido.', 'password' => 'Requerido.'], 'Usuario y contraseña son obligatorios.');
        }

        $this->rateLimiter->assertAllowed($identifier, $ip);
        $user = $this->users->findForLogin($identifier);
        if (!Passwords::verify($password, $user['password_hash'] ?? null)) {
            $this->rateLimiter->record($identifier, $ip, false);
            throw new ApiException('INVALID_CREDENTIALS', 'Usuario o contraseña incorrectos.', 401);
        }
        $this->rateLimiter->record($identifier, $ip, true);

        // Solo se informa que la cuenta está desactivada a quien conoce la contraseña.
        if (!$user['is_active']) {
            throw new ApiException('USER_INACTIVE', 'La cuenta está desactivada.', 403);
        }

        $userId = (int) $user['id'];
        if (Passwords::needsRehash($user['password_hash'])) {
            $this->users->setPasswordHash($userId, Passwords::hash($password));
        }
        $this->users->touchLastLogin($userId);

        [, $refreshToken] = $this->tokens->create($userId, $this->config['refresh_token_ttl'], $userAgent);
        return $this->session($this->users->findActiveAuthUser($userId), $refreshToken);
    }

    /**
     * Rota el refresh token. Presentar uno ya revocado indica que alguien lo copió:
     * se revocan todas las sesiones del usuario. La app debe serializar sus refresh
     * (uno a la vez) para no disparar esto con dos peticiones simultáneas.
     */
    public function refresh(mixed $refreshToken, ?string $userAgent): array
    {
        if (!is_string($refreshToken) || !preg_match(RefreshTokenRepository::TOKEN_PATTERN, $refreshToken)) {
            throw self::invalidRefreshToken();
        }

        // Los errores se devuelven y se lanzan fuera de la transacción: la revocación
        // por reuso tiene que quedar confirmada aunque la respuesta sea un error.
        $outcome = Db::transaction($this->db, function () use ($refreshToken, $userAgent): array {
            $row = $this->tokens->findForUpdate($refreshToken);
            if ($row === null || $row['expired']) {
                return ['error' => 'invalid'];
            }
            if ($row['revoked_at'] !== null) {
                $this->tokens->revokeAllForUser((int) $row['user_id']);
                return ['error' => 'reused', 'user_id' => (int) $row['user_id']];
            }
            $user = $this->users->findActiveAuthUser((int) $row['user_id']);
            if ($user === null) {
                return ['error' => 'inactive'];
            }
            [$newId, $newToken] = $this->tokens->create($user->id, $this->config['refresh_token_ttl'], $userAgent);
            $this->tokens->revoke((int) $row['id'], $newId);
            return ['session' => $this->session($user, $newToken)];
        });

        if (($outcome['error'] ?? null) === 'reused') {
            error_log("[oveja_negra] refresh token reutilizado: sesiones del usuario {$outcome['user_id']} revocadas");
        }
        return match ($outcome['error'] ?? null) {
            null => $outcome['session'],
            'inactive' => throw new ApiException('USER_INACTIVE', 'La cuenta no existe o está desactivada.', 401),
            default => throw self::invalidRefreshToken(),
        };
    }

    /** Idempotente: un token desconocido o ya revocado no es un error. */
    public function logout(mixed $refreshToken): void
    {
        if (is_string($refreshToken) && preg_match(RefreshTokenRepository::TOKEN_PATTERN, $refreshToken)) {
            $this->tokens->revokeByToken($refreshToken);
        }
    }

    public function changeOwnPassword(AuthUser $user, mixed $currentPassword, mixed $newPassword, ?string $userAgent): array
    {
        if (!is_string($currentPassword) || !Passwords::verify($currentPassword, $this->users->findPasswordHash($user->id))) {
            throw new ApiException('WRONG_PASSWORD', 'La contraseña actual no es correcta.', 400);
        }
        $newPassword = Validation::password($newPassword)
            ?? throw ApiException::validation(['new_password' => 'Entre 8 y 72 caracteres.']);

        return Db::transaction($this->db, function () use ($user, $newPassword, $userAgent): array {
            $this->users->setPasswordHash($user->id, Passwords::hash($newPassword));
            $this->tokens->revokeAllForUser($user->id);
            Audit::log($this->db, $user->id, 'users', $user->id, 'change_own_password');
            [, $refreshToken] = $this->tokens->create($user->id, $this->config['refresh_token_ttl'], $userAgent);
            return $this->session($user, $refreshToken);
        });
    }

    private function session(AuthUser $user, string $refreshToken): array
    {
        $now = time();
        $ttl = $this->config['access_token_ttl'];
        return [
            'access_token' => Jwt::encode(['sub' => $user->id, 'iat' => $now, 'exp' => $now + $ttl], $this->jwtSecret),
            'expires_in' => $ttl,
            'refresh_token' => $refreshToken,
            'user' => $user->toArray(),
        ];
    }

    private static function invalidRefreshToken(): ApiException
    {
        return new ApiException('INVALID_REFRESH_TOKEN', 'La sesión expiró. Vuelve a iniciar sesión.', 401);
    }
}
