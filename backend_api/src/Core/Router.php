<?php

declare(strict_types=1);

final class Router
{
    /** @var list<array{method: string, pattern: string, handler: array{class-string, string}, permission: ?string}> */
    private array $routes = [];

    /**
     * El permiso se declara junto a la ruta; AuthMiddleware lo hará cumplir (Fase 3).
     * null = ruta pública.
     */
    public function add(string $method, string $pattern, array $handler, ?string $permission = null): void
    {
        $this->routes[] = [
            'method' => $method,
            'pattern' => $pattern,
            'handler' => $handler,
            'permission' => $permission,
        ];
    }

    public function get(string $pattern, array $handler, ?string $permission = null): void
    {
        $this->add('GET', $pattern, $handler, $permission);
    }

    public function post(string $pattern, array $handler, ?string $permission = null): void
    {
        $this->add('POST', $pattern, $handler, $permission);
    }

    public function patch(string $pattern, array $handler, ?string $permission = null): void
    {
        $this->add('PATCH', $pattern, $handler, $permission);
    }

    public function put(string $pattern, array $handler, ?string $permission = null): void
    {
        $this->add('PUT', $pattern, $handler, $permission);
    }

    /**
     * Patrones tipo "/v1/products/{id}"; los parámetros se devuelven en orden.
     *
     * @return array{handler: array{class-string, string}, params: list<string>, permission: ?string}
     */
    public function match(string $method, string $path): array
    {
        $pathMatched = false;
        foreach ($this->routes as $route) {
            $regex = '#^' . preg_replace('#\{[a-z_]+\}#', '([^/]+)', $route['pattern']) . '$#';
            if (!preg_match($regex, $path, $matches)) {
                continue;
            }
            $pathMatched = true;
            if ($route['method'] === $method) {
                return [
                    'handler' => $route['handler'],
                    'params' => array_map('urldecode', array_slice($matches, 1)),
                    'permission' => $route['permission'],
                ];
            }
        }

        throw $pathMatched
            ? new ApiException('METHOD_NOT_ALLOWED', 'Método no permitido.', 405)
            : new ApiException('NOT_FOUND', 'Ruta no encontrada.', 404);
    }

    // Soporta rewrite (/oveja_negra/api/v1/x) y PATH_INFO (/index.php/v1/x).
    public static function requestPath(): string
    {
        if (!empty($_SERVER['PATH_INFO'])) {
            return '/' . trim($_SERVER['PATH_INFO'], '/');
        }
        $uriPath = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
        $basePath = rtrim(dirname($_SERVER['SCRIPT_NAME'] ?? ''), '/');
        if ($basePath !== '' && str_starts_with($uriPath, $basePath)) {
            $uriPath = substr($uriPath, strlen($basePath));
        }
        return '/' . trim($uriPath, '/');
    }
}
