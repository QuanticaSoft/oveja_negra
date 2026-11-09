<?php

declare(strict_types=1);

/** @var Router $router */

$router->get('/v1/health', [HealthController::class, 'show']);

// Auth. logout es público: revoca por el refresh token, que ya prueba la sesión, así la app
// puede cerrar sesión aunque su access token haya expirado.
$router->post('/v1/auth/login', [AuthController::class, 'login']);
$router->post('/v1/auth/refresh', [AuthController::class, 'refresh']);
$router->post('/v1/auth/logout', [AuthController::class, 'logout']);
$router->get('/v1/auth/me', [AuthController::class, 'me'], Router::SESSION);
$router->patch('/v1/auth/me/password', [AuthController::class, 'changePassword'], Router::SESSION);

// Usuarios
$router->get('/v1/users', [UsersController::class, 'index'], 'users.manage');
$router->post('/v1/users', [UsersController::class, 'create'], 'users.manage');
$router->get('/v1/users/{id}', [UsersController::class, 'show'], 'users.manage');
$router->patch('/v1/users/{id}', [UsersController::class, 'update'], 'users.manage');
$router->patch('/v1/users/{id}/status', [UsersController::class, 'setStatus'], 'users.manage');
$router->patch('/v1/users/{id}/password', [UsersController::class, 'resetPassword'], 'users.manage');

// Catálogo y cartilla
$router->get('/v1/menu', [CatalogController::class, 'menu'], 'catalog.read');
$router->get('/v1/categories', [CatalogController::class, 'categories'], 'catalog.read');
$router->post('/v1/categories', [CatalogController::class, 'createCategory'], 'catalog.manage');
$router->patch('/v1/categories/{id}', [CatalogController::class, 'updateCategory'], 'catalog.manage');
$router->get('/v1/products', [CatalogController::class, 'products'], 'catalog.read');
$router->post('/v1/products', [CatalogController::class, 'createProduct'], 'catalog.manage');
$router->get('/v1/products/{id}', [CatalogController::class, 'product'], 'catalog.read');
$router->patch('/v1/products/{id}', [CatalogController::class, 'updateProduct'], 'catalog.manage');
$router->patch('/v1/products/{id}/price', [CatalogController::class, 'changePrice'], 'catalog.manage');
$router->patch('/v1/products/{id}/status', [CatalogController::class, 'setStatus'], 'catalog.manage');
$router->patch('/v1/products/{id}/availability', [CatalogController::class, 'setAvailability'], 'products.availability');
$router->post('/v1/products/{id}/image', [CatalogController::class, 'uploadImage'], 'catalog.manage');
$router->get('/v1/products/{id}/price-history', [CatalogController::class, 'priceHistory'], 'catalog.manage');

// Pedidos y pagos
$router->get('/v1/orders', [OrdersController::class, 'index'], 'orders.read');
$router->post('/v1/orders', [OrdersController::class, 'create'], 'orders.create');
$router->get('/v1/orders/{id}', [OrdersController::class, 'show'], 'orders.read');
$router->patch('/v1/orders/{id}/items', [OrdersController::class, 'replaceItems'], 'orders.create');
$router->patch('/v1/orders/{id}/status', [OrdersController::class, 'changeStatus'], 'orders.update_status');
$router->post('/v1/orders/{id}/cancel', [OrdersController::class, 'cancel'], 'orders.cancel');
$router->post('/v1/orders/{id}/payments', [OrdersController::class, 'createPayment'], 'payments.create');
$router->post('/v1/payments/{id}/void', [OrdersController::class, 'voidPayment'], 'payments.void');

// Roles y permisos
$router->get('/v1/roles', [RolesController::class, 'index'], 'roles.manage');
$router->get('/v1/permissions', [RolesController::class, 'permissions'], 'roles.manage');
$router->put('/v1/roles/{id}/permissions', [RolesController::class, 'replacePermissions'], 'roles.manage');
