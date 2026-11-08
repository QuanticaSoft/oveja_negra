<?php

declare(strict_types=1);

/** Refresh tokens opacos: en la BD solo queda su sha256, nunca el token. */
final class RefreshTokenRepository
{
    public const TOKEN_PATTERN = '/^[A-Za-z0-9_-]{43}$/';

    public function __construct(private readonly PDO $db)
    {
    }

    /** @return array{int, string} [id, token en claro para el cliente] */
    public function create(int $userId, int $ttlSeconds, ?string $userAgent): array
    {
        $token = Jwt::base64UrlEncode(random_bytes(32));
        $stmt = $this->db->prepare(
            "INSERT INTO refresh_tokens (user_id, token_hash, expires_at, user_agent)
             VALUES (?, ?, now() + ? * interval '1 second', ?) RETURNING id"
        );
        $stmt->execute([$userId, self::hash($token), $ttlSeconds, $userAgent]);
        return [(int) $stmt->fetchColumn(), $token];
    }

    /** @return array{id: int, user_id: int, revoked_at: ?string, expired: bool}|null */
    public function findForUpdate(string $token): ?array
    {
        $stmt = $this->db->prepare(
            'SELECT id, user_id, revoked_at, expires_at <= now() AS expired
             FROM refresh_tokens WHERE token_hash = ? FOR UPDATE'
        );
        $stmt->execute([self::hash($token)]);
        $row = $stmt->fetch();
        return $row === false ? null : $row;
    }

    public function revoke(int $id, ?int $replacedBy = null): void
    {
        $this->db->prepare('UPDATE refresh_tokens SET revoked_at = now(), replaced_by = ? WHERE id = ? AND revoked_at IS NULL')
            ->execute([$replacedBy, $id]);
    }

    public function revokeByToken(string $token): void
    {
        $this->db->prepare('UPDATE refresh_tokens SET revoked_at = now() WHERE token_hash = ? AND revoked_at IS NULL')
            ->execute([self::hash($token)]);
    }

    public function revokeAllForUser(int $userId): void
    {
        $this->db->prepare('UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = ? AND revoked_at IS NULL')
            ->execute([$userId]);
    }

    public function countActive(int $userId): int
    {
        $stmt = $this->db->prepare('SELECT count(*) FROM refresh_tokens WHERE user_id = ? AND revoked_at IS NULL AND expires_at > now()');
        $stmt->execute([$userId]);
        return (int) $stmt->fetchColumn();
    }

    private static function hash(string $token): string
    {
        return hash('sha256', $token);
    }
}
