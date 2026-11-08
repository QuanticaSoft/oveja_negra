<?php

declare(strict_types=1);

final class Audit
{
    private const REDACTED_KEYS = ['password_hash', 'password', 'token_hash'];

    public static function log(
        PDO $db,
        ?int $userId,
        string $entity,
        ?int $entityId,
        string $action,
        ?array $before = null,
        ?array $after = null,
    ): void {
        $db->prepare(
            'INSERT INTO audit_logs (user_id, entity, entity_id, action, before, after) VALUES (?, ?, ?, ?, ?, ?)'
        )->execute([
            $userId,
            $entity,
            $entityId,
            $action,
            self::encode($before),
            self::encode($after),
        ]);
    }

    private static function encode(?array $data): ?string
    {
        if ($data === null) {
            return null;
        }
        return json_encode(array_diff_key($data, array_flip(self::REDACTED_KEYS)), JSON_UNESCAPED_UNICODE);
    }
}
