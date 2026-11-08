<?php

declare(strict_types=1);

final class Request
{
    private const MAX_BODY_BYTES = 65536;

    /** Body JSON como array. Vacío → []. */
    public static function json(): array
    {
        $raw = file_get_contents('php://input', false, null, 0, self::MAX_BODY_BYTES + 1);
        if ($raw === false || $raw === '') {
            return [];
        }
        if (strlen($raw) > self::MAX_BODY_BYTES) {
            throw new ApiException('PAYLOAD_TOO_LARGE', 'El cuerpo de la petición es demasiado grande.', 413);
        }
        $data = json_decode($raw, true);
        if (!is_array($data) || array_is_list($data) && $data !== []) {
            throw new ApiException('INVALID_JSON', 'El cuerpo debe ser un objeto JSON válido.', 400);
        }
        return $data;
    }

    public static function header(string $name): ?string
    {
        $value = $_SERVER['HTTP_' . strtoupper(str_replace('-', '_', $name))] ?? null;
        return is_string($value) && $value !== '' ? $value : null;
    }

    public static function query(string $name): ?string
    {
        $value = $_GET[$name] ?? null;
        return is_string($value) && $value !== '' ? $value : null;
    }

    public static function ip(): string
    {
        return $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    }

    public static function userAgent(): ?string
    {
        $agent = $_SERVER['HTTP_USER_AGENT'] ?? null;
        return is_string($agent) ? mb_substr($agent, 0, 255) : null;
    }
}
