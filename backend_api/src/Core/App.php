<?php

declare(strict_types=1);

final class App
{
    // Solo válido en dev; fuera de dev la API se niega a arrancar con este valor.
    public const DEV_JWT_SECRET = 'dev-only-insecure-jwt-secret-do-not-use-outside-docker-0000000000';

    private static ?array $config = null;
    private static ?AuthUser $user = null;

    public static function config(): array
    {
        return self::$config ??= require dirname(__DIR__, 2) . '/config.php';
    }

    public static function db(): PDO
    {
        return Db::connect(self::config()['db']);
    }

    /** Usuario de la petición. Solo existe en rutas con permiso (no públicas). */
    public static function user(): AuthUser
    {
        return self::$user ?? throw new LogicException('Ruta pública: no hay usuario autenticado.');
    }

    public static function jwtSecret(): string
    {
        $config = self::config();
        $secret = $config['jwt_secret'] ?? null;
        if ($config['env'] !== 'dev' && (!is_string($secret) || strlen($secret) < 64 || $secret === self::DEV_JWT_SECRET)) {
            throw new RuntimeException('jwt_secret ausente, corto o de dev en config.local.php.');
        }
        return $secret;
    }

    public static function run(): never
    {
        ErrorHandler::register();

        $router = new Router();
        require dirname(__DIR__) . '/routes.php';

        $route = $router->match($_SERVER['REQUEST_METHOD'] ?? 'GET', Router::requestPath());
        if ($route['permission'] !== null) {
            self::$user = AuthMiddleware::authenticate(
                self::db(), Request::header('X-Auth-Token'), $route['permission'], self::jwtSecret(), time());
        }

        [$class, $method] = $route['handler'];
        (new $class())->$method(...$route['params']);

        throw new LogicException("El handler {$class}::{$method} no envió respuesta.");
    }
}
