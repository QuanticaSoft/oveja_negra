# Progreso

## Estado actual
**Fase 1 (arquitectura y diseño):** documentación lista en `feature/f1-arquitectura`, pendiente de PR a `develop`.

## Hecho
- 2026-11-07: repo creado; `main` y `develop` publicados en GitHub (`QuanticaSoft/oveja_negra`).
- 2026-11-07: verificado en flamenco (solo lectura): PHP 8.2.35 con `pdo_pgsql`, `gd`, `intl`,
  `mbstring`, `openssl`, `fileinfo`; **sin** Argon2id, `bcmath` ni `sodium`. Postgres 18.6 con zona
  `America/La_Paz`. No existen aún schemas `oveja_negra*` ni `~/oveja_negra`.
- 2026-11-07: Fase 1: `ARCHITECTURE.md`, `DATA_MODEL.md`, `API.md`, `DECISIONS.md`, `PLAN.md`,
  `README.md`, `CLAUDE.md`.

## Próximo
- Fase 2 (`feature/f2-db-base`), previa aprobación. Pendiente comprobar en el pool `gyros.sock` (no en
  CLI) la versión y extensiones de PHP con `/v1/health`.
- Crear los schemas en flamenco requiere confirmación del usuario (escribe en `gyros`).
