# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# OVEJA_NEGRA: instrucciones del proyecto

Sistema POS y de gestión para una hamburguesería (Flutter + API PHP + PostgreSQL). El plan está en
`docs/PLAN.md` y el estado en `docs/PROGRESS.md`: **leerlos al empezar cada sesión** y actualizar
`PROGRESS.md` (y `DECISIONS.md` si aplica) al cerrar cada tarea, en el mismo commit.

## Forma de trabajo
- Se trabaja **por fases**. Antes de cada fase: analizar lo existente, explicar qué se implementará,
  identificar dependencias, y **esperar la aprobación del usuario**. Implementar solo la fase acordada.
- No agregar dependencias sin aprobación. No inventar funcionalidades fuera de los requisitos.

## Estructura
- `app_ovejanegra/`: app Flutter por feature (`lib/core`, `lib/features/<feature>/{data,domain,presentation}`), Riverpod.
- `backend_api/`: PHP 8.2 plano + PDO, **sin composer**. `src/Core` (Router, Db, Jwt, Permissions…) y
  `src/Modules/<Modulo>` (Controller → Service → Repository). Migraciones en `backend_api/sql/NNN_*.sql`,
  **inmutables una vez aplicadas**; nunca nombran el schema.
- `docs/`: ARCHITECTURE, DATA_MODEL, API, DECISIONS, PLAN, PROGRESS.

## Reglas de dominio (no romper)
- Cuatro registros separados: comercial (`orders`/`purchases`/`expenses`), físico
  (`inventory_movements`), financiero (`financial_transactions`) y auditoría (`audit_logs`).
  Ver `docs/ARCHITECTURE.md`.
- **Históricos sin DELETE ni edición en sitio**: anular por estado + fila de reverso + `audit_logs`.
- Movimientos de inventario y financieros llevan `source_type`/`source_id` con `UNIQUE`: nunca duplicar.
- Ventas, compras, anulaciones y ajustes van **en una transacción**; stock con `SELECT … FOR UPDATE`.
- El ingreso se registra con cada **pago** confirmado, no con el estado del pedido.
- Precios de venta siempre desde la BD; `order_items` guarda snapshot de nombre y precio.
- **Dinero nunca en `float`**: `NUMERIC(12,2)` y cálculo en SQL o en centavos (flamenco no tiene `bcmath`).
- Reportes por `business_date` (La Paz, corte 04:00).
- El código verifica **permisos** (`orders.create`), nunca nombres de rol.

## Reglas duras (flamenco)
- **Sin sudo.** Nada de docker, systemd, node ni paquetes del sistema en flamenco.
- La BD de producción es `gyros`, de **otra app en producción**. OVEJA_NEGRA vive **solo** en los
  schemas `oveja_negra` (prod) y `oveja_negra_staging`. Nunca crear, alterar ni borrar nada en
  `public` ni en otros schemas (incluidos `hobbystore*`). Toda conexión fija `search_path`.
- PHP corre en el pool compartido `gyros.sock` como `marco`; conexión a Postgres por TCP `127.0.0.1`
  con password (SELinux bloquea el socket). El password solo en `~/oveja_negra/<env>/config.local.php`.
- Código fuera del docroot en `~/oveja_negra/<env>/`; en `/webs/quanticasoft/oveja_negra/` solo lo público.
- PHP sin Argon2id: contraseñas con bcrypt (costo 12, máx. 72 caracteres).
- Auth por header `X-Auth-Token` (PHP-FPM no reenvía `Authorization`).
- La Raspberry Pi (`nas-meteo`) es solo el gateway OTP; no se toca desde este proyecto.
- **Cualquier escritura en flamenco (deploy, migración, schema) se confirma antes con el usuario.**

## Flujo de trabajo
- Ramas: `main` (prod, solo por PR + tag), `develop` (staging), `feature/fN-nombre`, `fix/*`, `hotfix/X.Y.Z`.
- Commits con Conventional Commits: `feat(scope): descripción en español`.
- Versionado de la app: `0.N.x+BUILD`, con N = fase terminada. BUILD siempre crece.
- La API usa el prefijo `/v1`.

## Comandos
```bash
docker compose -f infra/docker-compose.dev.yml up -d --build   # Postgres :5444 + API :8082
backend_api/scripts/migrate.sh dev                             # aplica sql/ pendientes
backend_api/scripts/reset-dev.sh                               # borra el schema de dev (solo dev)
curl localhost:8082/v1/health
docker compose -f infra/docker-compose.dev.yml exec api php bin/create-admin.php   # primer ADMIN (interactivo)
backend_api/scripts/seed.sh dev                                # cartilla de demo con fotos (nunca en prod)
backend_api/scripts/setup-media.sh staging                     # carpeta de imágenes + chcon (una vez, con OK del usuario)

docker compose -f infra/docker-compose.dev.yml exec api php tests/run.php              # todos los tests
docker compose -f infra/docker-compose.dev.yml exec api php tests/run.php MoneyTest    # filtra por "Clase::metodo"

backend_api/scripts/migrate.sh staging && backend_api/scripts/deploy.sh staging   # desde develop, con OK del usuario

cd app_ovejanegra && flutter analyze && flutter test                # app: análisis y tests
flutter run                                                         # emulador Android contra el API de dev (10.0.2.2:8082)
backend_api/scripts/backup.sh staging|prod
```
Instalación y flamenco: `docs/INSTALL.md`.

## App: convenciones del código
- Riverpod 3 **sin generación de código** (`Notifier`/`AsyncNotifier` y providers a mano).
- Toda llamada al API pasa por `apiCall()` y lanza `ApiException` (con `details` por campo); las que
  requieren sesión usan `apiDioProvider`. Nunca leer ni escribir tokens fuera de `TokenStore`.
- Dinero en centavos `int` con `Money` (nunca `double`); hacia el API, `Money.toApi()`.
- Cada creación (pedido, pago, compra, gasto) genera su `IdempotencyKey` una vez y la reutiliza en reintentos.
- Lo que se muestra depende de `user.can('permiso')`, nunca del nombre del rol. Una sección nueva se
  agrega en `app/destinations.dart` con su permiso.
- Tests: dobles a mano en `test/support/fakes.dart` (`FakeAdapter` para Dio, `MemoryRefreshTokenStorage`).
  Pantallas completas con sesión: `pumpLoggedIn()` de `test/support/app_harness.dart` (reemplaza
  `httpAdapterProvider`).
- Lo que se agrega al carrito o se cobra pasa por `CartController`/`IdempotentOperation`; nunca generar
  una `IdempotencyKey` nueva en un reintento.

## Backend: convenciones del código
- Sin namespaces: el autoloader de `src/bootstrap.php` busca `src/Core/<Clase>.php` y
  `src/Modules/*/<Clase>.php`, así que los nombres de clase deben ser únicos.
- Rutas en `src/routes.php` con su permiso: `$router->post('/v1/orders', [OrdersController::class, 'create'], 'orders.create')`.
  `null` = pública; `Router::SESSION` = solo sesión. `AuthMiddleware` lo aplica y deja el usuario en `App::user()`.
  **Toda ruta nueva de negocio debe declarar un permiso** que exista en la tabla `permissions`.
- Capas: Controller (lee `Request`, llama al service, `Response::ok()`) → Service (recibe `PDO` y el
  `AuthUser` actor; reglas, `Db::transaction`, `Audit::log`; lanza `ApiException`, nunca usa `Response`)
  → Repository (SQL con parámetros). Así los services se prueban sin HTTP.
- Dinero en PHP como **centavos `int`** (`Money`, `Validation::money`); hacia la BD con `Money::fromCents()`.
  En las respuestas JSON los importes van como **texto** (`"25.00"`), tal cual los devuelve `NUMERIC`.
- Creaciones que la app puede reintentar (pedidos, pagos; después compras y gastos): header
  `Idempotency-Key` con `Idempotency::key()`. Si la clave ya existe, se devuelve lo creado (200) o
  `Idempotency::reused()` si el contenido no coincide. La carrera se resuelve con el `UNIQUE`
  (`Db::isUniqueViolation`).
- Todo movimiento de stock pasa por `InventoryLedger` (`lockAndCheck` y luego `move`); cantidades en
  milésimas `int` (`Quantity`, `Validation::quantity`), como el dinero en centavos.
- Todo asiento en `financial_transactions` pasa por `FinanceLedger` (`record` / `reverse`); el día
  operativo sale de `config['business_day_cutoff']`.
- Tests con pedidos insertados a mano: usar fechas que nunca sean reales (p. ej. `2000-01-01`), porque
  la BD dev tiene pedidos reales de hoy y `(business_date, daily_number)` es UNIQUE. En los reportes,
  compras y gastos van en fechas de 2001; los pedidos (siempre de hoy) se comparan antes y después.
- Controllers: los filtros de query se leen con `QueryParams::only([...])`.
- Imágenes: siempre por `ImageProcessor::store()` (re-codifica, sin EXIF) y URLs con `Media::url()`.
  Las subidas van bajo `p/`; nunca borrar fuera de ese prefijo (`demo/` es la media de demo).
- Comandos para el usuario: su Mac usa **zsh** (`read -p` no sirve; usar `read -s "VAR?Prompt: "`) y las
  contraseñas solo se escriben en un prompt oculto, nunca en la línea de comandos ni en el chat.
- Tests: runner propio `backend_api/tests/run.php` (sin PHPUnit). `tests/Db/*` heredan de `DbTestCase`
  (cada test en transacción con rollback; `insertUser(rol, usuario)`, `authUser(id)`,
  `assertApiError(código, http, fn)`, `assertDbRejects(SQLSTATE, sql)`).
- Ojo en los `CHECK` con columnas NULL: `col = 'X'` con NULL da NULL y el CHECK **pasa**; usar
  `IS NOT DISTINCT FROM` o `IS NOT NULL` explícito.
