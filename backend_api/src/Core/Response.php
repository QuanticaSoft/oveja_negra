<?php

declare(strict_types=1);

final class Response
{
    public static function ok(mixed $data, int $status = 200, ?array $meta = null): never
    {
        $body = ['data' => $data];
        if ($meta !== null) {
            $body['meta'] = $meta;
        }
        self::json($body, $status);
    }

    public static function error(string $code, string $message, int $status = 400, array $details = []): never
    {
        $error = ['code' => $code, 'message' => $message];
        if ($details !== []) {
            $error['details'] = $details;
        }
        self::json(['error' => $error], $status);
    }

    private static function json(array $body, int $status): never
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        header('X-Content-Type-Options: nosniff');
        echo json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }
}
