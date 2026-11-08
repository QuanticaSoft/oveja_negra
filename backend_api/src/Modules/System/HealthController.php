<?php

declare(strict_types=1);

final class HealthController
{
    private const REQUIRED_EXTENSIONS = ['pdo_pgsql', 'gd', 'intl', 'mbstring', 'openssl', 'fileinfo'];

    public function show(): never
    {
        $config = App::config();
        $data = [
            'status' => 'ok',
            'version' => API_VERSION,
            'env' => $config['env'],
            'db' => $this->dbStatus(),
            'auth' => ['jwt_secret_ok' => $this->jwtSecretOk()],
        ];

        // Fuera de prod se exponen versión y extensiones para verificar el pool PHP-FPM real
        // (en flamenco el PHP de la terminal puede no ser el mismo que el del pool gyros.sock).
        if ($config['env'] !== 'prod') {
            $data['php'] = [
                'version' => PHP_VERSION,
                'sapi' => PHP_SAPI,
                'missing_extensions' => array_values(array_filter(
                    self::REQUIRED_EXTENSIONS,
                    static fn (string $ext): bool => !extension_loaded($ext),
                )),
            ];
        }

        if (!$data['db']['ok'] || !$data['auth']['jwt_secret_ok']) {
            $data['status'] = 'degraded';
            Response::ok($data, 503);
        }
        Response::ok($data);
    }

    private function jwtSecretOk(): bool
    {
        try {
            App::jwtSecret();
            return true;
        } catch (RuntimeException) {
            return false;
        }
    }

    private function dbStatus(): array
    {
        try {
            $row = App::db()->query(
                "SELECT current_setting('TimeZone') AS timezone,
                        (SELECT count(*) FROM schema_migrations) AS migrations"
            )->fetch();
            return ['ok' => true, 'timezone' => $row['timezone'], 'migrations' => (int) $row['migrations']];
        } catch (Throwable $e) {
            error_log('[oveja_negra] health: ' . $e->getMessage());
            return ['ok' => false];
        }
    }
}
