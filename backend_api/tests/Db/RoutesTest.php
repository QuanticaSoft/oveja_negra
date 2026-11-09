<?php

declare(strict_types=1);

/** Evita que una ruta nueva quede abierta o dependa de un permiso mal escrito. */
final class RoutesTest extends DbTestCase
{
    private const PUBLIC_ROUTES = ['GET /v1/health', 'POST /v1/auth/login', 'POST /v1/auth/refresh', 'POST /v1/auth/logout'];

    public function testCadaRutaDeclaraUnPermisoExistente(): void
    {
        $router = new Router();
        require dirname(__DIR__, 2) . '/src/routes.php';
        $permissions = $this->db->query('SELECT code FROM permissions')->fetchAll(PDO::FETCH_COLUMN);

        $public = [];
        foreach ($router->routes() as $route) {
            $name = "{$route['method']} {$route['pattern']}";
            if ($route['permission'] === null) {
                $public[] = $name;
                continue;
            }
            $this->assertTrue($route['permission'] === Router::SESSION || in_array($route['permission'], $permissions, true),
                "{$name} usa un permiso inexistente: {$route['permission']}");
            [$class, $method] = $route['handler'];
            $this->assertTrue(method_exists($class, $method), "{$name}: no existe {$class}::{$method}");
        }
        $this->assertSame(self::PUBLIC_ROUTES, $public, 'Rutas públicas');
    }
}
