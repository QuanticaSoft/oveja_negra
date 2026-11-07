<?php

declare(strict_types=1);

final class RouterTest extends TestCase
{
    private Router $router;

    public function setUp(): void
    {
        $this->router = new Router();
        $this->router->get('/v1/products/{id}', ['ProductsController', 'show'], 'catalog.read');
        $this->router->patch('/v1/products/{id}/price', ['ProductsController', 'updatePrice'], 'catalog.manage');
        $this->router->get('/v1/health', ['HealthController', 'show']);
    }

    public function testMatchDevuelveHandlerParametrosYPermiso(): void
    {
        $route = $this->router->match('PATCH', '/v1/products/42/price');
        $this->assertSame(['ProductsController', 'updatePrice'], $route['handler']);
        $this->assertSame(['42'], $route['params']);
        $this->assertSame('catalog.manage', $route['permission']);
    }

    public function testRutaPublicaNoTienePermiso(): void
    {
        $this->assertNull($this->router->match('GET', '/v1/health')['permission']);
    }

    public function testMetodoIncorrectoDa405(): void
    {
        $e = $this->assertThrows(ApiException::class, fn () => $this->router->match('DELETE', '/v1/products/42'));
        $this->assertSame(405, $e->status);
    }

    public function testRutaInexistenteDa404(): void
    {
        $e = $this->assertThrows(ApiException::class, fn () => $this->router->match('GET', '/v1/nada'));
        $this->assertSame(404, $e->status);
        $this->assertSame('NOT_FOUND', $e->errorCode);
    }

    public function testParametroNoCruzaSegmentos(): void
    {
        $this->assertThrows(ApiException::class, fn () => $this->router->match('GET', '/v1/products/1/2'));
    }
}
