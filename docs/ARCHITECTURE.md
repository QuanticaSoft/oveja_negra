# Arquitectura

## Visión general

```
┌──────────────────────────┐  HTTPS + X-Auth-Token (JWT)  ┌───────────────────────────────────────────────┐
│ App Flutter              │ ───────────────────────────▶ │ flamenco: /oveja_negra/api/v1/*  (PHP 8.2)    │
│ (Android: tel. y tablet) │                              │  código en ~/oveja_negra/<env>/               │
│  Riverpod · go_router    │                              │  PDO (TCP 127.0.0.1) ─▶ Postgres 18, BD gyros │
│  dio · secure_storage    │                              │        schema oveja_negra(_staging)           │
│  otp_auth (Fase 3b) ─────┼──┐                           │  media ─▶ /webs/quanticasoft/oveja_negra/media│
└──────────────────────────┘  │                           └───────────────────┬───────────────────────────┘
                              │ HTTPS                                         │ valida token OTP (Fase 3b)
                              ▼                                               ▼
                   ┌──────────────────────────────┐            ┌──────────────────────────────┐
                   │ flamenco: /otp/*.php         │ ◀───────── │ session.php → {status,phone} │
                   └──────────────┬───────────────┘            └──────────────────────────────┘
                                  │ túnel SSH inverso
                                  ▼
                   Raspberry Pi nas-meteo (gateway OTP) ─▶ Android smsbridge ─▶ SMS
```

El OTP es **opcional**: el login principal es usuario/celular + contraseña, para que la caja
nunca dependa de la Raspberry Pi.

## Principio central: cuatro registros separados

| Registro | Responde | Tablas |
|---|---|---|
| Comercial | ¿Qué se vendió / compró? | `orders`, `order_items`, `purchases`, `purchase_items`, `expenses` |
| Físico | ¿Cuánto insumo entró/salió y a qué costo? | `inventory_movements` |
| Financiero | ¿Cuánto dinero entró/salió? | `financial_transactions` |
| Auditoría | ¿Quién cambió qué y cuándo? | `audit_logs` |

- Los movimientos de inventario y financieros guardan `source_type` + `source_id` (la operación
  que los originó) con restricción `UNIQUE`: es imposible duplicar un ingreso, egreso o entrada
  de stock aunque se reintente una petición.
- Nada histórico se borra ni se edita en sitio: se **anula** (estado) y se genera un **reverso**
  (fila nueva con signo contrario), más una fila en `audit_logs`.
- `unit_cost` en cada entrada y `avg_unit_cost` (promedio ponderado) en `ingredients` dejan lista la
  base para la Etapa 2: recetas → costo real por hamburguesa → margen.

Detalle de tablas: [`DATA_MODEL.md`](DATA_MODEL.md). Endpoints: [`API.md`](API.md).

## Backend (`backend_api/`)

PHP 8.2 plano + PDO, **sin composer ni framework** (flamenco no tiene sudo; mismo patrón que
Hobby-Store).

```
backend_api/
├── public/        index.php (front controller), .htaccess
├── src/
│   ├── Core/      Router, Db, Response, Validation, Jwt, AuthMiddleware, Permissions,
│   │              Audit, Idempotency, ErrorHandler, Money
│   └── Modules/   Auth, Users, Catalog, Orders, Purchasing, Inventory, Finance, Reports
│                  (cada uno: Controller → Service → Repository)
├── sql/           NNN_*.sql — migraciones, inmutables una vez aplicadas
├── seeds/         datos de demo (solo dev/staging)
├── scripts/       migrate.sh, deploy.sh, backup.sh, seed.sh, lib.sh
├── config.php     valores por defecto
└── config.local.php.example
```

Pipeline de una petición:

```
index.php → ErrorHandler → Router (ruta + permiso requerido)
          → AuthMiddleware (JWT en X-Auth-Token) → Permissions (permiso del rol)
          → Controller (valida entrada) → Service (reglas, transacción) → Repository (SQL)
          → Response JSON
```

- **Controller**: parsea y valida la entrada, llama al service. Sin SQL.
- **Service**: reglas de negocio; abre la transacción (`Db::transaction(fn)`) en ventas, compras,
  anulaciones y ajustes.
- **Repository**: SQL con parámetros (nunca interpolación).
- Las rutas declaran su permiso: `['POST', '/v1/orders', [OrdersController::class, 'create'], 'orders.create']`.

### Reglas técnicas

- **Dinero**: `NUMERIC(12,2)` en la BD. Totales calculados en SQL o en PHP con enteros en
  centavos. Nunca `float` (flamenco no tiene `bcmath`).
- **Conexión**: TCP a `127.0.0.1` con password (SELinux bloquea el socket a PHP-FPM). Al conectar:
  `SET search_path TO <schema>`, `SET TIME ZONE 'America/La_Paz'`, `SET statement_timeout`.
- **Concurrencia de stock**: `SELECT … FOR UPDATE` sobre cada insumo dentro de la transacción.
- **Idempotencia**: header `Idempotency-Key` (UUID generado por la app) en `POST /orders`,
  `/purchases`, `/expenses`, `/orders/:id/payments`; columna `UNIQUE` en la tabla. Reintentar con la
  misma clave devuelve la operación ya creada.
- **Errores**: formato único `{"error": {"code", "message", "details"}}`; nunca trazas al cliente.
  Éxito: `{"data": …}` (+ `"meta"` en listados paginados).
- **Reportes**: rango de fechas obligatorio y paginación, para no cargar la BD compartida con gyros.

## Seguridad

- **Contraseñas**: `password_hash(PASSWORD_BCRYPT, cost 12)`; máx. 72 caracteres (límite de bcrypt).
  Argon2id no está compilado en el PHP de flamenco.
- **JWT HS256** implementado con `hash_hmac` (sin librerías). Access token 15 min; refresh token
  opaco de 32 bytes, rotativo, ~7 días, guardado como `sha256` en `refresh_tokens`.
  Desactivar un usuario revoca todos sus refresh tokens; el access token también se rechaza porque
  el middleware comprueba `users.is_active`.
- **Header `X-Auth-Token`** en lugar de `Authorization` (PHP-FPM no reenvía `Authorization` sin
  `CGIPassAuth`).
- **RBAC por permisos**: `roles` → `role_permissions` → `permissions`. El código solo conoce
  permisos, nunca nombres de rol. La app oculta pantallas según los permisos de `/v1/auth/me`,
  pero el backend valida siempre.
- **Rate limit** en `/v1/auth/*` (tabla `auth_attempts` por IP y usuario).
- **Trazabilidad**: `created_by` en cada operación; `audit_logs` (before/after JSONB) en cambios de
  precio, anulaciones, ajustes, cambios de estado y de usuarios.

## App Flutter (`app_ovejanegra/`)

```
lib/
├── main.dart
├── app/            router (go_router), tema (negro/blanco/naranja), app.dart
├── core/
│   ├── config/     API_BASE_URL vía --dart-define
│   ├── network/    dio + AuthInterceptor (X-Auth-Token, un solo refresh a la vez), ApiException,
│   │               IdempotencyKey (UUID v4 con Random.secure)
│   ├── storage/    refresh token en flutter_secure_storage; access token solo en memoria
│   ├── utils/      formato Bs, fechas America/La_Paz
│   └── widgets/    componentes comunes
└── features/<feature>/
    ├── data/          api + repository
    ├── domain/        modelos
    └── presentation/  screens + providers (Riverpod)
```

Sesión: `SessionController` (`AsyncNotifier<AuthUser?>`) restaura la sesión con el refresh token
al abrir la app; `go_router` redirige según ese estado (`redirectFor`) y según el permiso de cada
sección (`app/destinations.dart`). En tablet (≥ 900 px) el menú queda fijo; en teléfono es un drawer.

Features: `auth`, `dashboard`, `catalog`, `orders`, `purchases`, `inventory`, `expenses`,
`reports`, `users`. Solo en línea (sin modo offline en el MVP).

## Entornos

| Entorno | Rama | API | Código | BD |
|---|---|---|---|---|
| dev | `feature/*` | `http://localhost:8082/v1` (emulador Android: `http://10.0.2.2:8082/v1`) | repo local (Docker) | Postgres Docker, schema `oveja_negra` |
| staging | `develop` | `https://www.quanticasoft.com/oveja_negra/api-staging/v1` | `~/oveja_negra/staging` | `gyros.oveja_negra_staging` |
| prod | tag en `main` | `https://www.quanticasoft.com/oveja_negra/api/v1` | `~/oveja_negra/prod` | `gyros.oveja_negra` |
