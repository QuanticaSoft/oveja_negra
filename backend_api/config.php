<?php

declare(strict_types=1);

// Sin variables de entorno: en flamenco corremos en el pool PHP-FPM compartido
// de gyros, cuyo entorno no controlamos sin sudo. Cada entorno sobreescribe
// estos valores con un config.local.php no versionado.
$defaults = [
    'env' => 'dev',
    'db' => [
        'dsn' => 'pgsql:host=db;port=5432;dbname=oveja_negra_dev',
        'user' => 'oveja',
        'password' => 'oveja',
        'schema' => 'oveja_negra',
        'statement_timeout' => '10s',
    ],
    // Hora de corte del día operativo en La Paz: lo vendido antes cuenta para el día anterior.
    'business_day_cutoff' => '04:00',
    // En staging/prod: 64+ caracteres aleatorios, solo en config.local.php. App::jwtSecret()
    // rechaza este valor de dev fuera de dev.
    'jwt_secret' => App::DEV_JWT_SECRET,
    'access_token_ttl' => 900,
    'refresh_token_ttl' => 7 * 24 * 3600,
    'login_rate_limit' => [
        'window_minutes' => 15,
        'max_failures_per_identifier' => 5,
        'max_failures_per_ip' => 20,
    ],
    'media_base_url' => null,
    'media_dir' => __DIR__ . '/public/media',
];

$localOverridesFile = __DIR__ . '/config.local.php';
if (file_exists($localOverridesFile)) {
    $overrides = require $localOverridesFile;
    return array_replace_recursive($defaults, is_array($overrides) ? $overrides : []);
}

return $defaults;
