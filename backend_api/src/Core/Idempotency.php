<?php

declare(strict_types=1);

/**
 * Header Idempotency-Key: la app genera un UUID por operación y lo repite en cada reintento,
 * así una red inestable no duplica pedidos ni pagos. La columna UNIQUE de cada tabla es la garantía.
 */
final class Idempotency
{
    public const HEADER = 'Idempotency-Key';

    public static function key(?string $value): string
    {
        if ($value === null) {
            throw new ApiException('IDEMPOTENCY_KEY_REQUIRED', 'Falta el header Idempotency-Key (UUID).', 400);
        }
        $value = strtolower(trim($value));
        if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/', $value)) {
            throw ApiException::validation([self::HEADER => 'Debe ser un UUID.']);
        }
        return $value;
    }

    public static function reused(): ApiException
    {
        return ApiException::conflict('IDEMPOTENCY_KEY_REUSED',
            'Esa Idempotency-Key ya se usó para otra operación. Genera una clave nueva.');
    }

    public static function isUniqueViolation(Throwable $e, string $constraint): bool
    {
        return $e instanceof PDOException && $e->getCode() === '23505' && str_contains($e->getMessage(), $constraint);
    }
}
