<?php

declare(strict_types=1);

/** Validadores puros: devuelven el valor normalizado o null si no es válido. */
final class Validation
{
    // Mismo formato que otp_auth y el gateway OTP: +591 + 8 dígitos.
    public static function phone(mixed $phone): ?string
    {
        if (!is_string($phone)) {
            return null;
        }
        return preg_match('/^\+591\d{8}$/', $phone) ? $phone : null;
    }

    /** Igual que el CHECK de users.username; se normaliza a minúsculas. */
    public static function username(mixed $value): ?string
    {
        if (!is_string($value)) {
            return null;
        }
        $value = strtolower(trim($value));
        return preg_match('/^[a-z0-9._-]{3,40}$/', $value) ? $value : null;
    }

    /** 8+ caracteres y como máximo 72 bytes: bcrypt ignora lo que pase de 72. */
    public static function password(mixed $value): ?string
    {
        if (!is_string($value) || mb_strlen($value) < 8 || strlen($value) > 72) {
            return null;
        }
        return $value;
    }

    public static function bool(mixed $value): ?bool
    {
        return is_bool($value) ? $value : null;
    }

    /** Texto obligatorio, con espacios normalizados y longitud máxima. */
    public static function text(mixed $value, int $maxLength): ?string
    {
        if (!is_string($value)) {
            return null;
        }
        $value = trim(preg_replace('/\s+/u', ' ', $value) ?? '');
        if ($value === '' || mb_strlen($value) > $maxLength) {
            return null;
        }
        return $value;
    }

    /**
     * Texto libre opcional: null o "" se guardan como null.
     * Devuelve false si el valor no es válido.
     */
    public static function optionalText(mixed $value, int $maxLength): string|null|false
    {
        if ($value === null || (is_string($value) && trim($value) === '')) {
            return null;
        }
        return self::text($value, $maxLength) ?? false;
    }

    public static function positiveInt(mixed $value): ?int
    {
        if (is_int($value)) {
            return $value > 0 ? $value : null;
        }
        if (is_string($value) && preg_match('/^[1-9]\d{0,17}$/', $value)) {
            return (int) $value;
        }
        return null;
    }

    /**
     * Importe ≥ 0 en centavos. Acepta "12.50", 12 o 12.5 (json_decode entrega floats:
     * se convierten por su representación textual más corta, así 12.5 no se vuelve 12.4999…).
     */
    public static function money(mixed $value): ?int
    {
        if (is_int($value) || is_float($value)) {
            $value = (string) $value;
        }
        if (!is_string($value) || !preg_match('/^\d{1,10}(\.\d{1,2})?$/', $value)) {
            return null;
        }
        return Money::toCents($value);
    }
}
