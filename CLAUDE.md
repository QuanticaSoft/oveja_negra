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
Se agregarán en la Fase 2, cuando exista el código (Docker dev, `migrate.sh`, `flutter test`).
