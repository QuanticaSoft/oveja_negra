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

| Método | Ruta | Permiso |
|---|---|---|
| POST | `/v1/orders` (Idempotency-Key) → 201, o 200 si es un reintento | `orders.create` |
| GET | `/v1/orders?from&to&status&channel&sort&page&per_page` | `orders.read` |
| GET | `/v1/orders/{id}` (incluye pagos) | `orders.read` |
| PATCH | `/v1/orders/{id}/items` `{items, discount?}`: reemplaza todos los ítems | `orders.create` |
| PATCH | `/v1/orders/{id}/status` `{status}` | `orders.update_status` |
| POST | `/v1/orders/{id}/cancel` `{reason}` | `orders.cancel` (solo ADMIN por defecto) |
| POST | `/v1/orders/{id}/payments` (Idempotency-Key) `{method, amount}` → 201, o 200 si es un reintento | `payments.create` |
| POST | `/v1/payments/{id}/void` `{reason}` | `payments.void` (solo ADMIN por defecto) |

Crear pedido:
```json
{"channel": "WHATSAPP", "items": [{"product_id": 3, "quantity": 2}], "discount": "5.00",
 "customer_name": "Ana", "customer_phone": "+59170000000", "notes": "sin cebolla",
 "payments": [{"method": "EFECTIVO", "amount": "20"}, {"method": "QR", "amount": "26"}]}
```
- **Los precios salen siempre de la BD**; si el cliente envía un precio, se ignora. Cada ítem guarda
  una copia del nombre y del precio, así que un cambio de precio posterior no altera el pedido.
- 1 a 50 líneas, cantidad de 1 a 99, un producto por línea. El producto debe estar activo, disponible y
  en una categoría activa.
- `discount` es un monto fijo, exige `orders.discount` y no puede superar el subtotal.
- `payments` es opcional (hasta 5, para pagos mixtos) y exige `payments.create`. Si algo falla, no se
  guarda nada: ni el pedido, ni sus ítems, ni sus pagos.
- `customer_phone` acepta de 7 a 15 dígitos con `+` opcional (puede ser extranjero); se guarda sin espacios.

**Idempotency-Key** (UUID, obligatoria en `POST /orders` y `POST /orders/{id}/payments`): la app genera una
por operación y la repite en cada reintento. Repetir la misma petición devuelve lo ya creado, con 200.
Si la clave se repite con otro canal o ítems, otro pedido, método o importe, o la usa otro usuario,
responde 409 `IDEMPOTENCY_KEY_REUSED`.

Pedido:
```json
{"id": 184, "number": 3, "business_date": "2026-11-08", "channel": "LOCAL", "status": "PENDIENTE",
 "customer_name": null, "customer_phone": null, "notes": null,
 "items": [{"id": 1, "product_id": 39, "name": "Bacon", "unit_price": "32.00", "quantity": 1, "line_total": "32.00"}],
 "subtotal": "32.00", "discount": "0.00", "total": "32.00", "paid": "10.00", "balance": "22.00",
 "payment_status": "PARCIAL", "created_by": {"id": 2, "full_name": "…"}, "cancelled": null,
 "created_at": "…", "updated_at": "…", "payments": [ … ]}
```
- `number` es el número del día (#1, #2…); reinicia cada día operativo (corte a las 04:00).
- `payment_status` = `SIN_PAGAR` | `PARCIAL` | `PAGADO`, calculado con los pagos confirmados. Un pedido
  de total 0 queda `PAGADO`.
- `payments` (solo en el detalle): `{id, order_id, method, amount, status, received_by, created_at,
  voided: null | {by, at, reason}}`.

Listado: `from`/`to` son días operativos (`YYYY-MM-DD`, por defecto hoy, rango máximo de 92 días);
`status` admite varios separados por coma (`PENDIENTE,EN_PREPARACION` para la cocina); `sort=asc|desc`
(por defecto `desc`). Incluye los ítems, no los pagos.

Estados: `PENDIENTE → EN_PREPARACION → LISTO → ENTREGADO`, siempre hacia adelante y **se pueden saltar
pasos**. Para pasar a ENTREGADO el pedido tiene que estar pagado por completo. CANCELADO solo se pone
con `/cancel`, desde cualquier estado salvo ENTREGADO, y anula todos los pagos confirmados (cada uno con
su reverso).

Cada pago confirmado genera un `INGRESO` (categoría `VENTA`) en el día operativo en que se cobra. Al
anularlo se genera un `EGRESO` de reverso en el día de la anulación. Un pedido cancelado deja un neto de 0.

| Error | HTTP | Cuándo |
|---|---|---|
| `IDEMPOTENCY_KEY_REQUIRED` | 400 | Falta el header en una creación |
| `IDEMPOTENCY_KEY_REUSED` | 409 | Misma clave con otro contenido o de otro usuario |
| `PRODUCT_UNAVAILABLE` | 409 | Producto agotado o desactivado; `details.products = [{id, name}]` |
| `DISCOUNT_EXCEEDS_SUBTOTAL` | 422 | Descuento mayor que el subtotal (también al editar ítems) |
| `OVERPAYMENT` | 422 | El pago supera el saldo; `details.balance` |
| `UNPAID_ORDER` | 422 | Pasar a ENTREGADO con saldo pendiente; `details.balance` |
| `INVALID_TRANSITION` | 409 | Volver a un estado anterior, o cancelar un pedido entregado |
| `ORDER_CANCELLED` | 409 | Cambiar el estado, cobrar o cancelar de nuevo un pedido cancelado |
| `ORDER_LOCKED` | 409 | Editar ítems de un pedido que no está PENDIENTE o que tiene pagos |
| `PAYMENT_ALREADY_VOIDED` | 409 | Anular un pago ya anulado |
| `FORBIDDEN` | 403 | Descuento sin `orders.discount` o pagos sin `payments.create` |

## Compras, insumos e inventario

| Método | Ruta | Permiso |
|---|---|---|
| GET | `/v1/suppliers?active` | `suppliers.manage` |
| POST | `/v1/suppliers` `{name, phone?, notes?}` → 201 | `suppliers.manage` |
| PATCH | `/v1/suppliers/{id}` `{name?, phone?, notes?, is_active?}` | `suppliers.manage` |
| GET | `/v1/units` · `/v1/ingredient-categories` | `ingredients.read` |
| POST | `/v1/ingredient-categories` `{name}` → 201 | `ingredients.manage` |
| GET | `/v1/ingredients?category_id&active&low_stock&q&page&per_page` · `/v1/ingredients/{id}` | `ingredients.read` |
| POST | `/v1/ingredients` `{name, category_id, unit_id, min_stock?}` → 201 | `ingredients.manage` |
| PATCH | `/v1/ingredients/{id}` `{name?, category_id?, unit_id?, min_stock?}` | `ingredients.manage` |
| PATCH | `/v1/ingredients/{id}/status` `{is_active}` | `ingredients.manage` |
| POST | `/v1/purchases` (Idempotency-Key) → 201, o 200 si es un reintento | `purchases.create` |
| GET | `/v1/purchases?from&to&supplier_id&status&page&per_page` · `/v1/purchases/{id}` | `purchases.read` |
| POST | `/v1/purchases/{id}/void` `{reason}` | `purchases.void` |
| GET | `/v1/inventory/movements?ingredient_id&type&from&to&page&per_page` | `inventory.read` |
| POST | `/v1/inventory/adjustments` `{ingredient_id, quantity (±), reason}` → 201 | `inventory.adjust` |
| POST | `/v1/inventory/consumptions` `{items: [{ingredient_id, quantity}], reason}` → 201 | `inventory.consume` |

Por defecto, ENCARGADO y ADMIN tienen todos estos permisos; CAJERO, ninguno.

- **Cantidades** con hasta 3 decimales, como texto (`"6.500"`), en la unidad del insumo. Se acepta
  `"6.5"`, `6.5` o `6`.
- **Insumo:** `{id, name, category: {id, name}, unit: {id, code, name}, current_stock, min_stock,
  avg_unit_cost, is_low_stock, is_active, created_at, updated_at}`.
  - `current_stock` y `avg_unit_cost` solo cambian con movimientos; enviarlos en un PATCH da 400.
  - `is_low_stock` es `true` cuando el insumo está activo y `current_stock ≤ min_stock`; `low_stock=true` filtra esos insumos.
  - La unidad solo se cambia si el insumo no tiene movimientos (409 `UNIT_LOCKED`).

**Compras:**
```json
{"purchase_date": "2026-11-08", "supplier_id": 13, "receipt_number": "F-001", "payment_method": "EFECTIVO",
 "items": [{"ingredient_id": 118, "quantity": "6.5", "unit_price": "48.50"}]}
```
- `purchase_date` es la fecha de la boleta: cualquier fecha pasada, nunca futura (hora de La Paz).
  `supplier_id` es opcional. Se admiten de 1 a 100 insumos distintos y el precio unitario va de 0 a 1 000 000.
- `line_total = round(cantidad × precio, 2)`; el total debe ser mayor que 0 (422 `PURCHASE_TOTAL_ZERO`).
- En una transacción: una `ENTRADA_COMPRA` por ítem, el stock, el **costo promedio ponderado**
  `(stock·prom + q·precio) / (stock + q)` y un `EGRESO` (`COMPRA_INSUMOS`) con `business_date = purchase_date`.
- `Idempotency-Key`: igual que en los pedidos. Si la misma clave llega con otra fecha, otro proveedor u
  otros ítems, o de otro usuario, responde 409 `IDEMPOTENCY_KEY_REUSED`.
- Respuesta: `{id, purchase_date, supplier: null | {id, name}, receipt_number, payment_method,
  items: [{id, ingredient: {id, name, unit}, quantity, unit_price, line_total}], total, status,
  created_by, voided: null | {by, at, reason}, created_at, updated_at}`. El listado cubre por defecto
  los últimos 30 días.
- **Anular** crea un `REVERSO` por ítem, descuenta el stock y revierte el costo promedio. Si el stock
  queda en 0, conserva el último costo. El reverso del egreso se asienta **en la fecha de la compra**. Si
  lo comprado ya se usó, responde 409 `INSUFFICIENT_STOCK`: primero hay que registrar un ajuste.

**Inventario:**
- Movimiento: `{id, ingredient: {id, name, unit}, type, quantity (con signo), unit_cost, stock_after,
  source: null | {type, id}, reason, created_by, created_at}`.
- `type` = `ENTRADA_COMPRA` | `SALIDA_CONSUMO` | `AJUSTE` | `REVERSO`.
- `from`/`to` son días operativos; por defecto los últimos 30 días; máximo 92.
- Un ajuste es positivo o negativo y exige motivo. No cambia el costo promedio.
- Un consumo registra todas sus salidas o ninguna.
- Ajustes y consumos **no llevan Idempotency-Key**: si se duplican, se ve en el kardex y se corrige con
  otro ajuste.

| Error | HTTP | Cuándo |
|---|---|---|
| `INSUFFICIENT_STOCK` | 409 | Un consumo, ajuste o anulación dejaría stock negativo; `details.ingredients = [{ingredient_id, name, unit, stock, required}]` |
| `INGREDIENT_INACTIVE` | 409 | Compra o consumo con un insumo desactivado; `details.ingredients` |
| `SUPPLIER_INACTIVE` | 409 | Compra con un proveedor desactivado |
| `PURCHASE_ALREADY_VOIDED` | 409 | Anular dos veces |
| `UNIT_LOCKED` | 409 | Cambiar la unidad de un insumo con movimientos |
| `SUPPLIER_NAME_TAKEN` · `INGREDIENT_NAME_TAKEN` · `INGREDIENT_CATEGORY_NAME_TAKEN` | 409 | Nombre repetido (sin distinguir mayúsculas) |

## Gastos y finanzas

| Método | Ruta | Permiso |
|---|---|---|
| GET | `/v1/expense-categories?active` | `expenses.read` |
| POST | `/v1/expense-categories` `{name}` → 201 | `expense_categories.manage` (solo ADMIN) |
| PATCH | `/v1/expense-categories/{id}` `{name?, is_active?}` | `expense_categories.manage` |
| POST | `/v1/expenses` (Idempotency-Key) → 201, o 200 si es un reintento | `expenses.create` |
| GET | `/v1/expenses?from&to&category_id&status&page&per_page` (por defecto, los últimos 30 días) | `expenses.read` |
| POST | `/v1/expenses/{id}/void` `{reason}` | `expenses.void` |
| GET | `/v1/finance/transactions?from&to&type&category&page&per_page` (por defecto, hoy) | `finance.read` |
| GET | `/v1/finance/summary?from&to` (por defecto, hoy) | `finance.read` |

**Gasto:** `{expense_date, category_id, description, amount, payment_method}`.
- `expense_date` es cualquier fecha pasada, nunca futura. `amount` debe ser mayor que 0 y la categoría
  estar activa (409 `EXPENSE_CATEGORY_INACTIVE`).
- Genera un `EGRESO` (`GASTO_OPERATIVO`) con `business_date = expense_date`. Al anularlo, el reverso va
  en la **misma fecha** (409 `EXPENSE_ALREADY_VOIDED` si ya estaba anulado).
- Respuesta: `{id, expense_date, category: {id, name}, description, amount, payment_method, status,
  created_by, voided: null | {by, at, reason}, created_at, updated_at}`.
- `Idempotency-Key`: si la misma clave llega con otra fecha, categoría, descripción, importe o forma de
  pago, o de otro usuario, responde 409 `IDEMPOTENCY_KEY_REUSED`.
- Error propio: `EXPENSE_CATEGORY_NAME_TAKEN` (409).

**Libro:** `{id, type, category, description, amount, business_date, occurred_at, source: {type, id},
is_reversal, reverses_id, created_by}`. `category` puede ser `VENTA`, `COMPRA_INSUMOS` o `GASTO_OPERATIVO`.

**Resumen (cuadre):** todos los totales son **netos de reversos**.
```json
{"from": "2026-11-08", "to": "2026-11-08",
 "sales_collected": {"total": "51.00", "cash": "30.00", "qr": "21.00"},
 "purchases": "100.00",
 "expenses": {"total": "15.00", "by_category": [{"category": {"id": 1, "name": "Gas"}, "total": "15.00"}]},
 "operating_result": "-64.00"}
```
`operating_result = sales_collected.total − purchases − expenses.total`, y es exactamente la suma con signo
del libro en el período.

## Dashboard y reportes

Hay **dos cifras de venta** con nombre propio:
- **`sold` (vendido):** total de los pedidos no cancelados, por el día operativo del pedido.
- **`collected` (cobrado):** dinero que entró según el libro, por el día en que se cobró.

Difieren cuando un pedido se paga otro día o queda pendiente. El resultado operativo usa "cobrado",
porque es lo que cuadra con la caja.

| Método | Ruta | Permiso |
|---|---|---|
| GET | `/v1/dashboard?from&to` (por defecto, hoy) | `dashboard.read` |
| GET | `/v1/reports/sales/daily?from&to` | `reports.read` |
| GET | `/v1/reports/sales/monthly?year` (por defecto, el año actual) | `reports.read` |
| GET | `/v1/reports/purchases?from&to` | `reports.read` |
| GET | `/v1/reports/expenses/by-category?from&to` | `reports.read` |
| GET | `/v1/reports/products/top?from&to&limit` (`limit` de 1 a 50, por defecto 10) | `reports.read` |
| GET | `/v1/reports/finance/movements?from&to` | `reports.read` |

Los reportes cubren por defecto los últimos 30 días; el máximo es de 92 días.

- **Dashboard:** `{from, to, finance: <resumen>, orders: {count, sold, average_ticket, cancelled,
  by_channel: [{channel, orders, sold}], by_status: {PENDIENTE: n, …}}, top_products (5),
  low_stock: {count, ingredients (hasta 10): [{id, name, unit, current_stock, min_stock}]}}`.
- **Ventas diarias y mensuales:** un renglón por día o por mes, **incluidos los que no tienen movimiento**:
  `{date | month, orders, sold, cancelled, collected, cash, qr}`.
- **Compras:** solo las confirmadas: `{purchases, total, by_supplier: [{supplier: null | {id, name},
  purchases, total}], by_ingredient: [{ingredient: {id, name, unit}, quantity, total, average_unit_price}]}`.
- **Gastos por categoría:** solo los confirmados: `{total, categories: [{category, expenses, total}]}`.
- **Productos más vendidos:** `[{product: {id, name}, quantity, total}]`, de pedidos no cancelados. El
  `total` es antes del descuento del pedido.
- **Flujo financiero:** `{days: [{date, income, outcome, net, cumulative}]}`, con todos los movimientos del
  libro, reversos incluidos. Una operación anulada el mismo día deja neto 0.
