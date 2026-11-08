# Progreso

## Estado actual
**Fase 3 (auth, JWT, RBAC, usuarios):** integrada y en staging, con el primer ADMIN creado.

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

- 2026-11-08: Fase 3 integrada (PR #3) y **desplegada en staging**: health `0.3.0` con
  `jwt_secret_ok: true`; rutas protegidas responden 401 sin sesión; `bin/` no es accesible desde la web
  (404). El usuario creó el primer ADMIN de staging (`admin`, id 1) con `create-admin.php`.
  Problema encontrado: el comando documentado no llevaba comillas y el Mac expandía `~` a su propio
  home; corregido en `INSTALL.md` y en el script.

- 2026-11-08: login del ADMIN de staging verificado (intento correcto en `auth_attempts`) y contraseña
  cambiada con `PATCH /v1/auth/me/password` (auditada; la sesión anterior quedó revocada). Se cambió
  porque la contraseña inicial quedó escrita en el chat: el comando de verificación usaba `read -p`,
  que no funciona en zsh. `INSTALL.md` ahora tiene la versión para zsh. **Fase 3 cerrada.**

## Próximo
- Fase 4 (catálogo) o Fase 3b (login por OTP), según decida el usuario.
