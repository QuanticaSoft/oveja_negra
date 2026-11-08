<?php

declare(strict_types=1);

/**
 * JWT HS256 mínimo (sin composer). Solo acepta exactamente el header que emite:
 * así un token con "alg":"none" u otro algoritmo nunca se valida.
 */
final class Jwt
{
    private const HEADER = ['alg' => 'HS256', 'typ' => 'JWT'];
    // Tolerancia para relojes del servidor levemente adelantados al validar "iat".
    private const CLOCK_SKEW_SECONDS = 60;

    public static function encode(array $claims, string $secret): string
    {
        $header = self::base64UrlEncode(json_encode(self::HEADER));
        $payload = self::base64UrlEncode(json_encode($claims));
        return "{$header}.{$payload}." . self::sign("{$header}.{$payload}", $secret);
    }

    /** @throws InvalidArgumentException si el token no es válido o expiró. */
    public static function decode(string $token, string $secret, int $now): array
    {
        $parts = explode('.', $token);
        if (count($parts) !== 3) {
            throw new InvalidArgumentException('Formato de token inválido.');
        }
        [$header, $payload, $signature] = $parts;

        if (!hash_equals(self::sign("{$header}.{$payload}", $secret), $signature)) {
            throw new InvalidArgumentException('Firma inválida.');
        }
        if (self::decodeJson($header) !== self::HEADER) {
            throw new InvalidArgumentException('Header no permitido.');
        }

        $claims = self::decodeJson($payload);
        if (!is_int($claims['exp'] ?? null) || !is_int($claims['iat'] ?? null)) {
            throw new InvalidArgumentException('Faltan exp/iat.');
        }
        if ($claims['exp'] <= $now) {
            throw new InvalidArgumentException('Token expirado.');
        }
        if ($claims['iat'] > $now + self::CLOCK_SKEW_SECONDS) {
            throw new InvalidArgumentException('Token emitido en el futuro.');
        }
        return $claims;
    }

    private static function sign(string $data, string $secret): string
    {
        return self::base64UrlEncode(hash_hmac('sha256', $data, $secret, true));
    }

    private static function decodeJson(string $segment): array
    {
        $json = base64_decode(strtr($segment, '-_', '+/'), true);
        $data = $json === false ? null : json_decode($json, true);
        if (!is_array($data)) {
            throw new InvalidArgumentException('Segmento inválido.');
        }
        return $data;
    }

    public static function base64UrlEncode(string $bytes): string
    {
        return rtrim(strtr(base64_encode($bytes), '+/', '-_'), '=');
    }
}
