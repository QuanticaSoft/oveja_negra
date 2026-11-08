<?php

declare(strict_types=1);

/** bcrypt nativo de PHP: el PHP de flamenco no tiene Argon2id (ver DECISIONS.md). */
final class Passwords
{
    private const OPTIONS = ['cost' => 12];

    // Hash de una cadena aleatoria descartada. Se verifica contra él cuando el usuario no
    // existe, para que el login tarde lo mismo y no revele qué usuarios existen.
    private const DUMMY_HASH = '$2y$12$TRlj91oePvKOyX0jyg2vMedyjWuZHZRkA5EgsIb6i2AhEJDRULcTm';

    public static function hash(string $password): string
    {
        return password_hash($password, PASSWORD_BCRYPT, self::OPTIONS);
    }

    public static function verify(string $password, ?string $hash): bool
    {
        $matches = password_verify($password, $hash ?? self::DUMMY_HASH);
        return $hash !== null && $matches;
    }

    public static function needsRehash(string $hash): bool
    {
        return password_needs_rehash($hash, PASSWORD_BCRYPT, self::OPTIONS);
    }
}
