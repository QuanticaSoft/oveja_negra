<?php

declare(strict_types=1);

/** @var Router $router */

$router->get('/v1/health', [HealthController::class, 'show']);
