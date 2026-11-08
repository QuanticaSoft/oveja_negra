<?php

declare(strict_types=1);

final class LoginRateLimiter
{
    public function __construct(
        private readonly PDO $db,
        private readonly int $windowMinutes,
        private readonly int $maxFailuresPerIdentifier,
        private readonly int $maxFailuresPerIp,
    ) {
    }

    /**
     * Por usuario solo cuentan los fallos posteriores al último login correcto: quien se
     * equivoca y luego entra no queda penalizado. Por IP cuentan todos (frena a quien prueba
     * muchos usuarios distintos).
     */
    public function assertAllowed(string $identifier, string $ip): void
    {
        $stmt = $this->db->prepare(
            "SELECT
               (SELECT count(*) FROM auth_attempts
                 WHERE identifier = ? AND NOT success
                   AND created_at > now() - ? * interval '1 minute'
                   AND created_at > COALESCE((SELECT max(created_at) FROM auth_attempts
                                              WHERE identifier = ? AND success), '-infinity')) AS by_identifier,
               (SELECT count(*) FROM auth_attempts
                 WHERE ip = ?::inet AND NOT success
                   AND created_at > now() - ? * interval '1 minute') AS by_ip"
        );
        $stmt->execute([$identifier, $this->windowMinutes, $identifier, $ip, $this->windowMinutes]);
        $counts = $stmt->fetch();

        if ($counts['by_identifier'] >= $this->maxFailuresPerIdentifier || $counts['by_ip'] >= $this->maxFailuresPerIp) {
            throw new ApiException('TOO_MANY_ATTEMPTS', 'Demasiados intentos fallidos. Espera unos minutos.', 429);
        }
    }

    public function record(string $identifier, string $ip, bool $success): void
    {
        $this->db->prepare('INSERT INTO auth_attempts (identifier, ip, success) VALUES (?, ?::inet, ?)')
            ->execute([$identifier, $ip, $success ? 'true' : 'false']);
    }
}
