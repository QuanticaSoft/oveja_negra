# Progreso

## Estado actual
**Fase 3 (auth, JWT, RBAC, usuarios):** lista en `feature/f3-auth-rbac`, pendiente de PR y de staging.

## Hecho
- 2026-11-07: repo creado; `main` y `develop` publicados en GitHub (`QuanticaSoft/oveja_negra`).
- 2026-11-07: verificado en flamenco (solo lectura): PHP 8.2.35 con `pdo_pgsql`, `gd`, `intl`,
  `mbstring`, `openssl`, `fileinfo`; **sin** Argon2id, `bcmath` ni `sodium`. Postgres 18.6 con zona
  `America/La_Paz`. No existen aún schemas `oveja_negra*` ni `~/oveja_negra`.
- 2026-11-07: Fase 1 (PR #1, integrado en `develop`): arquitectura, modelo, API, decisiones, plan.
- 2026-11-07: Fase 2:
  - Docker dev (PHP 8.2 + Postgres 18, puertos 5444/8082).
  - Core PHP: `App`, `Router` (con permiso por ruta), `Db` (search_path, zona horaria,
    statement_timeout, transacciones), `Response`, `ApiException`, `ErrorHandler`, `Validation`, `Money`.
  - `GET /v1/health` (estado de BD, migraciones, zona horaria; fuera de prod, PHP y extensiones).
  - Migraciones 001–006: todo el modelo de `DATA_MODEL.md`, semilla de 3 roles, 28 permisos y
    unidades; triggers que impiden borrar o modificar históricos.
  - Scripts `migrate.sh`, `deploy.sh`, `backup.sh`, `reset-dev.sh`.
  - Runner de tests propio: 25 tests (Money, Validation, Router y reglas de la BD) en verde.
    Los tests detectaron un CHECK que dejaba pasar una entrada de compra sin origen (NULL); corregido.
  - `docs/INSTALL.md`, `config.local.php.example`.

- 2026-11-07: Fase 2 integrada (PR #2) y **staging desplegado**: schema `gyros.oveja_negra_staging`
  con las 6 migraciones; `/oveja_negra/api-staging/v1/health` → ok, PHP 8.2.35 `fpm-fcgi` sin
  extensiones faltantes, `America/La_Paz`. Hobby-Store staging sigue sano y no se tocó ningún otro schema.
  Problema encontrado: el password copiado al `config.local.php` no coincidía con el del rol `marco`
  (lo corrigió el usuario); queda la nota en `INSTALL.md`.

- 2026-11-07: Fase 3 (API `0.3.0`):
  - Login por usuario o celular (bcrypt costo 12), JWT HS256 de 15 min en `X-Auth-Token`, refresh
    token de un solo uso (7 días) con detección de reuso, logout y cambio de contraseña propia.
  - `AuthMiddleware`: aplica el permiso de cada ruta, leyendo usuario y permisos de la BD en cada petición.
  - Límite de intentos: 5 fallos por usuario o 20 por IP en 15 min → 429.
  - Usuarios (CRUD, activar/desactivar, reset de contraseña) y roles (listar, reemplazar permisos), con
    protecciones contra quedarse sin ADMIN y auditoría sin contraseñas.
  - `bin/create-admin.php` para el primer ADMIN; `/v1/health` informa si `jwt_secret` es válido.
  - 68 tests en verde (25 de Fase 2 + 43 nuevos) y verificación de punta a punta por HTTP en dev.

## Próximo
- PR `feature/f3-auth-rbac` → `develop`; con OK del usuario, `deploy.sh staging` y que el usuario cree
  el primer ADMIN de staging con `create-admin.php`.
- Fase 3b (login por OTP) o Fase 4 (catálogo), según decida el usuario.
