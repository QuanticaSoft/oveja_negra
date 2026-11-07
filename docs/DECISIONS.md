# Decisiones

Formato: fecha, decisión y por qué. Las decisiones nuevas van arriba.

## 2026-11-07: Backend PHP 8.2 plano, sin composer ni framework
Se descarta NestJS + TypeORM. La API es PHP 8.2 + PDO, como Hobby-Store; las migraciones son SQL
numerado (`backend_api/sql/NNN_*.sql`) aplicado por `scripts/migrate.sh`.
**Por qué:** flamenco no tiene sudo: no se puede instalar Node ni dejar procesos persistentes. El PHP
corre en el pool existente `gyros.sock` como `marco`.

## 2026-11-07: BD en schemas dentro de `gyros`
`gyros.oveja_negra` (prod) y `gyros.oveja_negra_staging`. Toda conexión fija `search_path`.
**Por qué:** `marco` no tiene `CREATEDB` y es dueño de `gyros`. Mismo enfoque que Hobby-Store.
**Riesgo aceptado (usuario):** comparte instancia, BD y pool PHP-FPM con gyros, que está en producción.
Mitigación: nunca tocar `public` ni otros schemas, `statement_timeout` por conexión, reportes con
rango de fechas obligatorio y paginación, backups con `pg_dump -n <schema>`.

## 2026-11-07: URL pública
`https://www.quanticasoft.com/oveja_negra/api/v1` (prod) y `/oveja_negra/api-staging/v1`. Código fuera
del docroot en `~/oveja_negra/<env>/`; en el docroot solo `public/`. Media en
`/webs/quanticasoft/oveja_negra/media`, re-codificada con GD (sin EXIF/GPS).

## 2026-11-07: Contraseñas con bcrypt
`password_hash(PASSWORD_BCRYPT, ['cost' => 12])`, máx. 72 caracteres.
**Por qué:** verificado en flamenco (PHP 8.2.35 CLI): `PASSWORD_ARGON2ID` no está definido. bcrypt
ignora lo que pase de 72 bytes, así que se rechaza en la validación.

## 2026-11-07: Dinero sin `float`
`NUMERIC(12,2)` en la BD; cálculos en SQL o con enteros en centavos en PHP.
**Por qué:** flamenco no tiene `bcmath`. El `Money.php` de Hobby-Store usa `float` solo para formatear
y no se copia como base de cálculo.

## 2026-11-07: JWT propio en `X-Auth-Token`
HS256 con `hash_hmac` (sin librerías), access 15 min + refresh opaco rotativo (~7 días) guardado como
hash. El middleware comprueba también `users.is_active`.
**Por qué:** el requisito pide JWT; sin composer se implementa en pocas líneas. `Authorization` no llega a
PHP-FPM sin `CGIPassAuth` (problema ya visto en Hobby-Store).

## 2026-11-07: Login con contraseña; OTP como alternativa (Fase 3b)
El login principal es usuario o celular + contraseña. El OTP (gateway de celulares-platform) se agrega
después: la app obtiene el token OTP y la API lo valida contra `otp/session.php`; solo entra si el
celular pertenece a un usuario activo. No hay autoregistro: el ADMIN da de alta a los usuarios.
**Por qué:** el gateway depende de un teléfono en la Raspberry Pi; la caja no puede quedar bloqueada si falla.

## 2026-11-07: El ingreso se registra con el pago, no con el estado del pedido
Estado del pedido (cocina) y pago son independientes. Cada pago confirmado genera un `INGRESO`; se
admiten pagos mixtos (efectivo + QR) y pagos al entregar (WhatsApp). El QR se confirma a mano.
Cancelar un pedido anula sus pagos y crea reversos.
**Por qué:** "venta confirmada" no era un estado definido; el dinero real entra cuando se cobra.

## 2026-11-07: Día operativo con corte a las 04:00
`business_date` se calcula en La Paz con corte configurable (por defecto 04:00).
**Por qué:** las ventas después de medianoche pertenecen a la jornada anterior en los reportes.

## 2026-11-07: Número de pedido diario
Id global interno + `daily_number` que reinicia cada `business_date` (#1, #2…), único por día.
**Por qué:** número corto para cocina y clientes de WhatsApp.

## 2026-11-07: Una unidad base por insumo
La compra se registra en la unidad del insumo. Las conversiones (kg ↔ g) quedan para la etapa de recetas.

## 2026-11-07: Descuento por pedido en monto fijo
`0 ≤ discount ≤ subtotal`, requiere el permiso `orders.discount` (ADMIN y CAJERO por defecto).

## 2026-11-07: Permisos de casos ambiguos
ENCARGADO registra gastos operativos; CAJERO puede marcar productos como no disponibles. Cancelar
pedidos y anular pagos queda solo para ADMIN por defecto (el requisito no lo da al CAJERO). Como los
permisos son datos, se pueden reasignar sin tocar código.

## 2026-11-07: Sin borrado de históricos
Ventas, compras, gastos y movimientos se anulan con estado + reverso + `audit_logs`. Una compra
confirmada no se edita: se anula y se registra de nuevo.

## 2026-11-07: Stock nunca negativo
`CHECK (current_stock >= 0)`. Si una salida o anulación lo dejaría negativo se rechaza (409) y se usa
un ajuste manual con motivo.
**Por qué:** un stock negativo esconde errores de carga y ensucia el costo promedio.

## 2026-11-07: App Flutter
Android (teléfono y tablet) como objetivo principal; solo en línea. Riverpod (requisito), go_router,
dio, flutter_secure_storage, intl; fl_chart en dashboard/reportes. Dependencias aprobadas por el usuario.
Riesgo a revisar en la Fase 3b: `otp_auth` usa `Navigator` imperativo; se integrará como ruta de go_router.

## 2026-11-07: Dev local con Docker
PHP 8.2 + Postgres 18 en `infra/docker-compose.dev.yml`, misma versión que flamenco.

## 2026-11-07: Flujo de ramas igual que Hobby-Store
`main` (prod, solo por PR + tag `vX.Y.Z`), `develop` (staging), `feature/fN-nombre`, `fix/*`,
`hotfix/X.Y.Z`. Conventional Commits en español. Excepción única: el commit inicial de `main` y
`develop` se subieron directo porque el repo de GitHub estaba vacío.
