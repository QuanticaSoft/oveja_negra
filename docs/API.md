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
| POST | `/v1/auth/login` | público | `{identifier, password}`. `identifier` = usuario (sin distinguir mayúsculas) o celular `+591…` |
| POST | `/v1/auth/refresh` | público | `{refresh_token}` → sesión nueva (rotación) |
| POST | `/v1/auth/logout` | público | `{refresh_token}` → lo revoca. Idempotente. Público para poder cerrar sesión con el access token ya expirado |
| GET | `/v1/auth/me` | sesión | `{id, username, full_name, role, permissions[]}` |
| PATCH | `/v1/auth/me/password` | sesión | `{current_password, new_password}` → revoca todas las sesiones y devuelve una nueva |
| POST | `/v1/auth/otp` | público | Fase 3b. `{otp_session_token}` → valida en `otp/session.php` y emite JWT si el celular pertenece a un usuario activo |

**Sesión** (respuesta de login, refresh y cambio de contraseña):
```json
{"data": {"access_token": "<jwt>", "expires_in": 900, "refresh_token": "<43 caracteres>",
          "user": {"id": 1, "username": "…", "full_name": "…", "role": "CAJERO", "permissions": ["…"]}}}
```
- El access token (JWT HS256, 15 min) va en `X-Auth-Token` en cada petición. El refresh token dura 7 días
  y **es de un solo uso**: cada refresh devuelve uno nuevo.
- **Reusar un refresh token ya usado revoca todas las sesiones del usuario** (se asume robo). La app debe
  hacer un solo refresh a la vez y reintentar las peticiones en espera con el token nuevo.
- Contraseñas: 8 a 72 caracteres (límite de bcrypt).

| Error | HTTP | Cuándo |
|---|---|---|
| `INVALID_CREDENTIALS` | 401 | Usuario inexistente o contraseña incorrecta (mismo mensaje y tiempo en ambos casos) |
| `USER_INACTIVE` | 403 en login / 401 en el resto | Cuenta desactivada |
| `TOO_MANY_ATTEMPTS` | 429 | 5 fallos por usuario (desde su último login correcto) o 20 por IP en 15 min |
| `INVALID_REFRESH_TOKEN` | 401 | Refresh token inexistente, expirado, revocado o reutilizado |
| `UNAUTHENTICATED` | 401 | Falta `X-Auth-Token`, o es inválido o expiró → hacer refresh |
| `FORBIDDEN` | 403 | El rol no tiene el permiso de la ruta |
| `WRONG_PASSWORD` | 400 | `current_password` incorrecta |
| `INVALID_JSON` · `PAYLOAD_TOO_LARGE` | 400 · 413 | Cuerpo que no es un objeto JSON, o de más de 64 KB |

## Usuarios y roles

| Método | Ruta | Permiso |
|---|---|---|
| GET | `/v1/users?active=true\|false&role=CAJERO&page=1&per_page=20` (máx. 100) | `users.manage` |
| POST | `/v1/users` `{username, full_name, phone?, role_code, password}` → 201 | `users.manage` |
| GET | `/v1/users/{id}` | `users.manage` |
| PATCH | `/v1/users/{id}` `{full_name?, phone?, role_code?}` | `users.manage` |
| PATCH | `/v1/users/{id}/status` `{is_active}` — desactivar revoca sus sesiones | `users.manage` |
| PATCH | `/v1/users/{id}/password` `{new_password}` — revoca sus sesiones | `users.manage` |
| GET | `/v1/roles` (con permisos) · `/v1/permissions` | `roles.manage` |
| PUT | `/v1/roles/{id}/permissions` `{permissions: [códigos]}` (reemplaza el conjunto) | `roles.manage` |

Usuario: `{id, username, full_name, phone, role, is_active, last_login_at, created_at, updated_at}`
(nunca incluye la contraseña ni su hash).
Errores propios: `USERNAME_TAKEN` y `PHONE_TAKEN` (409); `CANNOT_DEACTIVATE_SELF` y
`CANNOT_CHANGE_OWN_ROLE` (409); `LAST_ADMIN` (409, siempre debe quedar un ADMIN activo);
`ADMIN_PERMISSIONS_REQUIRED` (409, el rol ADMIN conserva `users.manage` y `roles.manage`).

## Catálogo

| Método | Ruta | Permiso |
|---|---|---|
| GET | `/v1/menu` — cartilla: categorías activas con sus productos activos, incluidos los agotados (`is_available: false`) | `catalog.read` |
| GET | `/v1/categories?active=` | `catalog.read` |
| POST | `/v1/categories` `{name, sort_order?}` → 201 | `catalog.manage` |
| PATCH | `/v1/categories/{id}` `{name?, sort_order?, is_active?}` | `catalog.manage` |
| GET | `/v1/products?category_id&active&available&q&page&per_page` (`q` busca en nombre y descripción) | `catalog.read` |
| GET | `/v1/products/{id}` | `catalog.read` |
| POST | `/v1/products` `{category_id, name, description?, price}` → 201 | `catalog.manage` |
| PATCH | `/v1/products/{id}` `{category_id?, name?, description?}` (el precio **no** va aquí) | `catalog.manage` |
| PATCH | `/v1/products/{id}/price` `{price}` → guarda historial | `catalog.manage` |
| PATCH | `/v1/products/{id}/status` `{is_active}` | `catalog.manage` |
| PATCH | `/v1/products/{id}/availability` `{is_available}` (agotado hoy) | `products.availability` (ADMIN y CAJERO) |
| POST | `/v1/products/{id}/image` multipart, campo `image` (JPG/PNG/WEBP, ≤ 8 MB, ≤ 25 MP); reemplaza la anterior | `catalog.manage` |
| GET | `/v1/products/{id}/price-history` → `[{old_price, new_price, changed_at, changed_by: {id, full_name}}]` | `catalog.manage` |

Producto:
```json
{"id": 1, "category": {"id": 2, "name": "Hamburguesas"}, "name": "Clásica", "description": "…",
 "price": "25.00", "image_url": "…/media/p/2026/11/ab12….jpg", "thumb_url": "…/media/p/2026/11/ab12…_t.jpg",
 "is_active": true, "is_available": true, "created_at": "…", "updated_at": "…"}
```
- **Los importes son texto con 2 decimales** (`"25.00"`), nunca números JSON: así no se pierde
  precisión. Al enviar se acepta `"25.50"`, `25.5` o `25`. El precio debe ser mayor que 0.
- La imagen se guarda en 800 px y una miniatura de 300 px (`thumb_url`), siempre como JPEG nuevo, sin EXIF.
- Errores: `CATEGORY_NAME_TAKEN` · `PRODUCT_NAME_TAKEN` (409, sin distinguir mayúsculas; el mismo nombre
  en otra categoría sí vale) · `CATEGORY_INACTIVE` (409) · `UNSUPPORTED_IMAGE` (415) · `IMAGE_TOO_LARGE` (413).

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
