# OVEJA_NEGRA 🍔

Sistema de gestión para la hamburguesería OVEJA_NEGRA: ventas y pedidos (local y WhatsApp), cartilla,
compras de insumos, inventario, gastos, usuarios y reportes. Moneda: bolivianos (Bs). Zona horaria:
America/La_Paz.

- **Plan del MVP:** [`docs/PLAN.md`](docs/PLAN.md)
- **Estado y próximos pasos:** [`docs/PROGRESS.md`](docs/PROGRESS.md)
- **Arquitectura y entornos:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- **Modelo de datos:** [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md)
- **API:** [`docs/API.md`](docs/API.md)
- **Decisiones:** [`docs/DECISIONS.md`](docs/DECISIONS.md)

## Stack
- `app_ovejanegra/`: Flutter (Android), Riverpod.
- `backend_api/`: PHP 8.2 + PDO, sin composer, desplegado en flamenco (`www.quanticasoft.com`).
- PostgreSQL 18, schemas `oveja_negra` / `oveja_negra_staging` dentro de la BD `gyros`.

La instalación y el entorno de desarrollo se documentan en la Fase 2, cuando exista el código.

## Ramas y versiones
- `main` = producción (solo por PR + tag `vX.Y.Z`).
- `develop` = staging.
- `feature/fN-nombre` = trabajo diario; `fix/*`, `hotfix/X.Y.Z`.
- Detalle en `CLAUDE.md`.
