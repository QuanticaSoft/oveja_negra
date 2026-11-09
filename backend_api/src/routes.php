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

// Compras, proveedores e insumos
$router->get('/v1/suppliers', [PurchasingController::class, 'suppliers'], 'suppliers.manage');
$router->post('/v1/suppliers', [PurchasingController::class, 'createSupplier'], 'suppliers.manage');
$router->patch('/v1/suppliers/{id}', [PurchasingController::class, 'updateSupplier'], 'suppliers.manage');
$router->get('/v1/units', [InventoryController::class, 'units'], 'ingredients.read');
$router->get('/v1/ingredient-categories', [InventoryController::class, 'categories'], 'ingredients.read');
$router->post('/v1/ingredient-categories', [InventoryController::class, 'createCategory'], 'ingredients.manage');
$router->get('/v1/ingredients', [InventoryController::class, 'index'], 'ingredients.read');
$router->post('/v1/ingredients', [InventoryController::class, 'create'], 'ingredients.manage');
$router->get('/v1/ingredients/{id}', [InventoryController::class, 'show'], 'ingredients.read');
$router->patch('/v1/ingredients/{id}', [InventoryController::class, 'update'], 'ingredients.manage');
$router->patch('/v1/ingredients/{id}/status', [InventoryController::class, 'setStatus'], 'ingredients.manage');
$router->get('/v1/purchases', [PurchasingController::class, 'purchases'], 'purchases.read');
$router->post('/v1/purchases', [PurchasingController::class, 'createPurchase'], 'purchases.create');
$router->get('/v1/purchases/{id}', [PurchasingController::class, 'purchase'], 'purchases.read');
$router->post('/v1/purchases/{id}/void', [PurchasingController::class, 'voidPurchase'], 'purchases.void');

// Inventario
$router->get('/v1/inventory/movements', [InventoryController::class, 'movements'], 'inventory.read');
$router->post('/v1/inventory/adjustments', [InventoryController::class, 'adjust'], 'inventory.adjust');
$router->post('/v1/inventory/consumptions', [InventoryController::class, 'consume'], 'inventory.consume');

// Gastos y finanzas
$router->get('/v1/expense-categories', [FinanceController::class, 'expenseCategories'], 'expenses.read');
$router->post('/v1/expense-categories', [FinanceController::class, 'createExpenseCategory'], 'expense_categories.manage');
$router->patch('/v1/expense-categories/{id}', [FinanceController::class, 'updateExpenseCategory'], 'expense_categories.manage');
$router->get('/v1/expenses', [FinanceController::class, 'expenses'], 'expenses.read');
$router->post('/v1/expenses', [FinanceController::class, 'createExpense'], 'expenses.create');
$router->post('/v1/expenses/{id}/void', [FinanceController::class, 'voidExpense'], 'expenses.void');
$router->get('/v1/finance/transactions', [FinanceController::class, 'transactions'], 'finance.read');
$router->get('/v1/finance/summary', [FinanceController::class, 'summary'], 'finance.read');

// Dashboard y reportes
$router->get('/v1/dashboard', [ReportsController::class, 'dashboard'], 'dashboard.read');
$router->get('/v1/reports/sales/daily', [ReportsController::class, 'salesDaily'], 'reports.read');
$router->get('/v1/reports/sales/monthly', [ReportsController::class, 'salesMonthly'], 'reports.read');
$router->get('/v1/reports/purchases', [ReportsController::class, 'purchases'], 'reports.read');
$router->get('/v1/reports/expenses/by-category', [ReportsController::class, 'expensesByCategory'], 'reports.read');
$router->get('/v1/reports/products/top', [ReportsController::class, 'topProducts'], 'reports.read');
$router->get('/v1/reports/finance/movements', [ReportsController::class, 'financeMovements'], 'reports.read');

// Roles y permisos
$router->get('/v1/roles', [RolesController::class, 'index'], 'roles.manage');
$router->get('/v1/permissions', [RolesController::class, 'permissions'], 'roles.manage');
$router->put('/v1/roles/{id}/permissions', [RolesController::class, 'replacePermissions'], 'roles.manage');
