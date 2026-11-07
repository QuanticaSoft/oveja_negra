# API REST

Base: `/v1`. JSON. Autenticación con header `X-Auth-Token: <jwt>` (todos los endpoints salvo
login, refresh y health).

- Éxito: `{"data": …}`; listados: `{"data": [...], "meta": {"page", "per_page", "total"}}`.
- Error: `{"error": {"code": "VALIDATION_ERROR", "message": "…", "details": {...}}}`.
  Códigos HTTP: 400 validación, 401 sin sesión, 403 sin permiso, 404, 409 conflicto
  (estado inválido, stock insuficiente), 422 regla de negocio, 429 rate limit.
- `Idempotency-Key: <uuid>` obligatorio donde se indica.
- Fechas en ISO 8601 con zona `-04:00`; filtros `from`/`to` son `business_date` (`YYYY-MM-DD`).

## Sistema

| Método | Ruta | Permiso |
|---|---|---|
| GET | `/v1/health` | público |

## Auth

| Método | Ruta | Permiso | Notas |
|---|---|---|---|
| POST | `/v1/auth/login` | público | `{identifier (usuario o celular), password}` → `{access_token, refresh_token, user}` |
| POST | `/v1/auth/refresh` | público | `{refresh_token}` → par nuevo (rotación) |
| POST | `/v1/auth/logout` | sesión | revoca el refresh token |
| GET | `/v1/auth/me` | sesión | usuario + rol + permisos |
| POST | `/v1/auth/otp` | público | Fase 3b. `{otp_session_token}` → valida en `otp/session.php` y emite JWT si el celular pertenece a un usuario activo |

## Usuarios y roles

| Método | Ruta | Permiso |
|---|---|---|
| GET / POST | `/v1/users` | `users.manage` |
| GET / PATCH | `/v1/users/{id}` | `users.manage` |
| PATCH | `/v1/users/{id}/status` | `users.manage` |
| PATCH | `/v1/users/{id}/password` | `users.manage` |
| PATCH | `/v1/auth/me/password` | sesión (contraseña actual requerida) |
| GET | `/v1/roles` · `/v1/permissions` | `roles.manage` |
| PUT | `/v1/roles/{id}/permissions` | `roles.manage` |

## Catálogo

| Método | Ruta | Permiso |
|---|---|---|
| GET | `/v1/menu` (cartilla: activos agrupados por categoría) | `catalog.read` |
| GET | `/v1/categories` · `/v1/products?category_id&active&available&q` | `catalog.read` |
| POST | `/v1/categories` · `/v1/products` | `catalog.manage` |
| PATCH | `/v1/categories/{id}` · `/v1/products/{id}` | `catalog.manage` |
| PATCH | `/v1/products/{id}/price` | `catalog.manage` |
| PATCH | `/v1/products/{id}/status` | `catalog.manage` |
| PATCH | `/v1/products/{id}/availability` | `products.availability` |
| POST | `/v1/products/{id}/image` | `catalog.manage` |
| GET | `/v1/products/{id}/price-history` | `catalog.manage` |

## Pedidos y pagos

| Método | Ruta | Permiso | Notas |
|---|---|---|---|
| POST | `/v1/orders` | `orders.create` | Idempotency-Key. `{channel, items:[{product_id, quantity}], discount?, customer_name?, customer_phone?, notes?, payments?:[{method, amount}]}`. Precios siempre de la BD |
| GET | `/v1/orders?from&to&status&channel` | `orders.read` | |
| GET | `/v1/orders/{id}` | `orders.read` | |
| PATCH | `/v1/orders/{id}/items` | `orders.create` | solo PENDIENTE y sin pagos |
| PATCH | `/v1/orders/{id}/status` | `orders.update_status` | `{status}` con transición válida |
| POST | `/v1/orders/{id}/cancel` | `orders.cancel` | `{reason}`; anula pagos y crea reversos |
| POST | `/v1/orders/{id}/payments` | `payments.create` | Idempotency-Key. `{method, amount}` |
| POST | `/v1/payments/{id}/void` | `payments.void` | `{reason}` |

## Compras, insumos e inventario

| Método | Ruta | Permiso |
|---|---|---|
| GET / POST | `/v1/suppliers` · PATCH `/v1/suppliers/{id}` | `suppliers.manage` |
| GET | `/v1/units` · `/v1/ingredient-categories` | `ingredients.read` |
| POST | `/v1/ingredient-categories` | `ingredients.manage` |
| GET | `/v1/ingredients?category_id&active&low_stock` | `ingredients.read` |
| POST / PATCH | `/v1/ingredients` · `/v1/ingredients/{id}` | `ingredients.manage` |
| PATCH | `/v1/ingredients/{id}/status` | `ingredients.manage` |
| POST | `/v1/purchases` (Idempotency-Key) | `purchases.create` |
| GET | `/v1/purchases?from&to&supplier_id` · `/v1/purchases/{id}` | `purchases.read` |
| POST | `/v1/purchases/{id}/void` `{reason}` | `purchases.void` |
| GET | `/v1/inventory/movements?ingredient_id&type&from&to` | `inventory.read` |
| POST | `/v1/inventory/adjustments` `{ingredient_id, quantity (±), reason}` | `inventory.adjust` |
| POST | `/v1/inventory/consumptions` `{items:[{ingredient_id, quantity}], reason}` | `inventory.consume` |

## Gastos y finanzas

| Método | Ruta | Permiso |
|---|---|---|
| GET / POST | `/v1/expense-categories` · PATCH `/{id}` | `expenses.read` / `expense_categories.manage` |
| POST | `/v1/expenses` (Idempotency-Key) | `expenses.create` |
| GET | `/v1/expenses?from&to&category_id` | `expenses.read` |
| POST | `/v1/expenses/{id}/void` `{reason}` | `expenses.void` |
| GET | `/v1/finance/transactions?from&to&type&category` | `finance.read` |
| GET | `/v1/finance/summary?from&to` → ventas, compras, otros gastos, resultado operativo | `finance.read` |

## Dashboard y reportes

| Método | Ruta | Permiso |
|---|---|---|
| GET | `/v1/dashboard?from&to` → ventas, compras, gastos, resultado, n.º pedidos, top productos, stock bajo | `dashboard.read` |
| GET | `/v1/reports/sales/daily?from&to` | `reports.read` |
| GET | `/v1/reports/sales/monthly?year` | `reports.read` |
| GET | `/v1/reports/purchases?from&to` | `reports.read` |
| GET | `/v1/reports/expenses/by-category?from&to` | `reports.read` |
| GET | `/v1/reports/products/top?from&to&limit` | `reports.read` |
| GET | `/v1/reports/finance/movements?from&to` | `reports.read` |
