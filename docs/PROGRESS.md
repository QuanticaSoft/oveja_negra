# Progreso

## Estado actual
**Fase 2 (base del backend y migraciones):** lista en `feature/f2-db-base`, pendiente de PR a `develop`
y del primer despliegue a staging (requiere confirmación del usuario).

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

## Próximo
- PR `feature/f2-db-base` → `develop`.
- Con OK del usuario: crear `~/oveja_negra/staging/config.local.php`, `migrate.sh staging`,
  `deploy.sh staging` y comprobar `/oveja_negra/api-staging/v1/health` (PHP real del pool `gyros.sock`).
- Fase 3 (auth, JWT, RBAC, usuarios, auditoría), previa aprobación.
