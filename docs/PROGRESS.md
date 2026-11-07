# Progreso

## Estado actual
**Fase 3 (auth, JWT, RBAC, usuarios):** en curso en `feature/f3-auth-rbac`.

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

## Próximo
- Fase 3: PR `feature/f3-auth-rbac` → `develop`, deploy a staging y creación del primer ADMIN.
