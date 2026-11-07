<?php

declare(strict_types=1);

final class App
{
    private static ?array $config = null;

    public static function config(): array
    {
        return self::$config ??= require dirname(__DIR__, 2) . '/config.php';
    }

    public static function db(): PDO
    {
        return Db::connect(self::config()['db']);
    }

    public static function run(): never
    {
        ErrorHandler::register();

        $router = new Router();
        require dirname(__DIR__) . '/routes.php';

        $route = $router->match($_SERVER['REQUEST_METHOD'] ?? 'GET', Router::requestPath());
        [$class, $method] = $route['handler'];
        (new $class())->$method(...$route['params']);

        throw new LogicException("El handler {$class}::{$method} no envió respuesta.");
    }
}
