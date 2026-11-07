# Plan del MVP

Objetivo: administrar ventas, pedidos, compras de insumos, gastos, inventario, usuarios y reportes
de OVEJA_NEGRA (hamburguesería), con una base que permita después calcular el costo real por
hamburguesa y su margen.

Cada fase: analizar lo existente → proponer → **aprobación del usuario** → implementar solo esa fase
→ pruebas → documentar en `PROGRESS.md` y `DECISIONS.md`.

| Fase | Rama | Entregable | Validación |
|---|---|---|---|
| 1 | `feature/f1-arquitectura` | `docs/` (arquitectura, modelo, API, decisiones, plan), `README.md`, `CLAUDE.md` | revisión del usuario |
| 2 | `feature/f2-db-base` | Esqueleto PHP (Core: Router, Db, Response, ErrorHandler, Validation, Money), `/v1/health`, Docker dev, `migrate.sh`/`deploy.sh`/`backup.sh`/`reset-dev.sh`, **todas las migraciones del modelo** + semilla de roles/permisos/unidades, `config.local.php.example`, runner de tests, `INSTALL.md` | migraciones limpias en dev desde cero; tests verdes; health en dev y staging |
| 3 | `feature/f3-auth-rbac` | Login, JWT + refresh, middleware de permisos, usuarios, roles, auditoría, rate limit | tests de API por rol |
| 3b | `feature/f3b-otp` | Login por OTP vía `otp/session.php`, copia de `otp_auth` | prueba con SMS real |
| 4 | `feature/f4-catalogo` | Categorías, productos, precios + historial, disponibilidad, imágenes, cartilla | cambio de precio no altera pedidos |
| 5 | `feature/f5-ventas` | Pedidos, ítems, estados, pagos, cancelación con reverso, idempotencia | transacción, idempotencia, cancelado ≠ ingreso |
| 6 | `feature/f6-compras-inventario` | Insumos, proveedores, compras, anulación, movimientos, ajustes, consumo, stock bajo | stock, costo promedio, anulación |
| 7 | `feature/f7-finanzas-reportes` | Gastos, transacciones, resumen, dashboard, reportes | cuadre ventas − compras − gastos |
| 8 | `feature/f8-app-*` | App Flutter por módulos (puede dividirse en subramas) | `flutter analyze` limpio, widget tests |
| 9 | `feature/f9-hardening` | Revisión de seguridad, validaciones, documentación de instalación y despliegue | checklist + prueba de punta a punta |

## Etapa 2 (después del MVP)

Recetas por producto → descuento automático de insumos al vender → costo real por hamburguesa →
márgenes de rentabilidad. El modelo ya guarda `unit_cost` y `avg_unit_cost` para esto.

## Fuera de alcance del MVP

Modo offline, apertura/cierre de caja, integración bancaria del QR, facturación, multi-sucursal.
