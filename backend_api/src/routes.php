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

// Roles y permisos
$router->get('/v1/roles', [RolesController::class, 'index'], 'roles.manage');
$router->get('/v1/permissions', [RolesController::class, 'permissions'], 'roles.manage');
$router->put('/v1/roles/{id}/permissions', [RolesController::class, 'replacePermissions'], 'roles.manage');
