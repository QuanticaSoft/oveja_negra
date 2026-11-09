# Decisiones

Formato: fecha, decisión y por qué. Las decisiones nuevas van arriba.

## 2026-11-08: Anular una compra revierte en la fecha de la compra
El reverso del `EGRESO` usa `purchase_date`, no el día de la anulación. **Por qué:** anular una compra
suele corregir un error de carga, y los reportes de ese día deben quedar como si no hubiera existido. Los
pagos, en cambio, revierten el día de la anulación (caja). (Aprobado por el usuario.)

## 2026-11-08: Ajustes y consumos sin Idempotency-Key
No tienen columna para la clave y agregarla exigía una migración. Son manuales y poco frecuentes: un
duplicado se ve en el kardex y se corrige con otro ajuste. (Aprobado por el usuario.)

## 2026-11-08: Compras: fecha no futura y total mayor que 0
`purchase_date` acepta cualquier fecha pasada (boletas atrasadas), nunca futura en hora de La Paz. Se
admiten líneas de precio 0 (bonificación), pero no una compra de Bs 0: `financial_transactions.amount`
debe ser mayor que 0. (Aprobado por el usuario.)

## 2026-11-08: Stock y costo solo por InventoryLedger
`InventoryLedger` es el único que escribe `inventory_movements` y actualiza `current_stock` y
`avg_unit_cost`, en la misma sentencia y bajo `FOR UPDATE`. Los insumos se bloquean siempre en orden de
id para evitar interbloqueos. Un ajuste no cambia el costo, porque no tiene precio. Las cantidades se
calculan en milésimas enteras (`Quantity`), igual que el dinero en centavos.

## 2026-11-08: Estados del pedido: solo hacia adelante, con saltos
`PENDIENTE → EN_PREPARACION → LISTO → ENTREGADO`; se puede saltar, por ejemplo PENDIENTE → ENTREGADO
para una bebida en el mostrador, pero nunca volver atrás. CANCELADO tiene su propio endpoint y pide un
motivo. (Aprobado por el usuario.)

## 2026-11-08: Solo se entrega un pedido pagado
Pasar a ENTREGADO exige saldo 0 (422 `UNPAID_ORDER`). En WhatsApp con pago contra entrega se cobra y
después se marca la entrega. **Por qué:** que ningún pedido salga sin cobrar. (Aprobado por el usuario.)

## 2026-11-08: El ingreso cuenta el día en que se cobra
`financial_transactions.business_date` de un pago es el día operativo en que se cobró, no el del pedido;
el reverso cuenta el día en que se anuló. Los reportes de ventas por pedido usan `orders.business_date`.
**Por qué:** la caja de cada día debe cuadrar con el dinero que entró ese día. (Aprobado por el usuario.)

## 2026-11-08: Idempotencia sin columna de huella
Sin migración nueva: un reintento se compara con lo guardado. En un pedido se comparan el usuario, el
canal y los ítems; en un pago, el pedido, el método, el importe y el usuario. Si dos reintentos llegan a
la vez, el `UNIQUE` de la clave hace fallar al segundo, que entonces devuelve el registro del primero.

## 2026-11-08: Número diario con reintento, sin advisory locks
`daily_number = max + 1` del día, dentro de un savepoint. Si dos cajas toman el mismo número, el UNIQUE
rechaza a una, que reintenta (hasta 3 veces). **Por qué:** los advisory locks son de toda la BD `gyros`
y podrían chocar con las claves de otra app; una tabla contador requería una migración.

## 2026-11-08: Editar ítems reemplaza el conjunto
`PATCH /orders/{id}/items` borra y vuelve a insertar los ítems con los precios actuales. Solo se puede
mientras el pedido está PENDIENTE y sin pagos; en ese momento todavía no es histórico (el trigger
`guard_order_items_change` lo garantiza) y `audit_logs` guarda el antes y el después.

## 2026-11-08: Pagos en efectivo sin vuelto
Se guarda el importe aplicado al pedido, no el entregado por el cliente; el vuelto lo calcula la app.

## 2026-11-08: Imágenes: código propio y siempre re-codificadas
`ImageProcessor` (escrito para este proyecto, sin reutilizar código de Hobby-Store por pedido del
usuario) valida el tipo real, decodifica con GD y escribe un JPEG nuevo en 800 px y 300 px. Así un
archivo disfrazado no sobrevive y se borran los metadatos EXIF, incluido el GPS. La BD guarda solo
`image_path`: la miniatura se deriva con el sufijo `_t`, sin columna nueva. Al reemplazar una imagen
se borra la anterior (una imagen no es un dato histórico), pero solo bajo `p/`: la media de demo
(`demo/`) nunca se borra desde la API.

## 2026-11-08: Carpeta de media con tipo SELinux de escritura
`/webs/quanticasoft/oveja_negra/media(-staging)` necesita `chcon -t httpd_sys_rw_content_t` antes de
escribir nada: la carpeta padre es `httpd_sys_content_t`, de solo lectura para PHP-FPM. Lo hace
`scripts/setup-media.sh`, que además instala un `.htaccess` sin listado y sin ejecución de scripts.

## 2026-11-08: Importes como texto en JSON
La API devuelve `"25.00"` (como lo entrega `NUMERIC`), no `25`. Un número JSON lo leería la app como
`double` y podría redondear mal al sumar.

## 2026-11-08: Precio de venta mayor que 0 y separado de la edición
La API rechaza precio 0 (casi seguro un error de carga; la BD lo admite). El precio solo cambia con
`PATCH /products/{id}/price`, que guarda el historial; `PATCH /products/{id}` lo rechaza.

## 2026-11-08: Cartilla de demo con fotos libres
`seeds/demo.sql` + `seeds/media/` (8 fotos de Wikimedia Commons, todas CC0 o dominio público, sin
marcas visibles; ver `seeds/media/CREDITS.md`). El repo es público, por eso solo licencias libres.
`seed.sh` se niega a correr en prod. Las categorías y productos reales los carga el usuario.

## 2026-11-08: `ErrorHandler` respeta `@`
Solo convierte en excepción los errores que `error_reporting()` incluye. GD emite warnings al leer
archivos inválidos y esos casos ya se manejan devolviendo 415.

## 2026-11-07: Refresh tokens de un solo uso con detección de reuso
Cada refresh revoca el token usado y emite otro (`replaced_by` los encadena). Si llega un token ya
revocado, se revocan **todas** las sesiones del usuario y queda en `error_log`.
**Por qué:** un token reutilizado significa que dos partes lo tienen (copia o robo); no se puede saber
cuál es la legítima. **Consecuencia para la app (Fase 8):** un solo refresh a la vez.

## 2026-11-07: Usuario y permisos se leen de la BD en cada petición
El JWT solo lleva `sub`, `iat` y `exp`; rol y permisos no van en el token.
**Por qué:** desactivar a alguien o quitarle un permiso rige al instante, no 15 minutos después. Cuesta
una consulta indexada por petición.

## 2026-11-07: Login sin enumeración de usuarios
Usuario inexistente y contraseña incorrecta devuelven el mismo error, y en ambos casos se ejecuta
`password_verify` (contra un hash ficticio si el usuario no existe), así que tardan lo mismo. "Cuenta
desactivada" solo se informa si la contraseña es correcta.

## 2026-11-07: Protecciones contra quedarse sin administrador
- Siempre queda al menos un ADMIN activo (`LAST_ADMIN`, con `SELECT … FOR UPDATE` para que dos
  peticiones simultáneas no se lo salten).
- Nadie puede desactivarse ni cambiarse el rol a sí mismo.
- El rol ADMIN conserva siempre `users.manage` y `roles.manage`.

## 2026-11-07: Primer ADMIN por CLI (`bin/create-admin.php`)
No hay endpoint de registro. El primer ADMIN se crea en el servidor con un script interactivo que pide
la contraseña sin mostrarla, y que se niega si ya existe un ADMIN. Los demás se crean desde la API.
**Por qué:** la contraseña del primer administrador nunca pasa por git, por el chat ni por el historial del shell.

## 2026-11-07: `logout` es público
Revoca el refresh token recibido. Tener ese token ya prueba que se es dueño de la sesión, y así la app
puede cerrar sesión aunque su access token haya expirado.

## 2026-11-07: Secreto JWT de dev fijo y rechazado fuera de dev
`config.php` trae `App::DEV_JWT_SECRET` para que dev funcione sin configurar nada. Fuera de dev, si
`jwt_secret` falta, tiene menos de 64 caracteres o es el de dev, la API no autentica a nadie y
`/v1/health` muestra `auth.jwt_secret_ok: false` (HTTP 503).

## 2026-11-07: `Db::transaction` anidable con savepoints
Si ya hay una transacción abierta, usa `SAVEPOINT`. Permite que los tests corran cada caso dentro de una
transacción con rollback, y que un service llame a otro sin romper la atomicidad.

## 2026-11-07: Tests con runner propio, sin PHPUnit
`backend_api/tests/run.php` (decisión del usuario). Tests unitarios y de BD (`DbTestCase`, cada test
en transacción con rollback). Corren en el contenedor dev; `deploy.sh` excluye `tests/`.
**Por qué:** sin composer en flamenco y sin sumar dependencias; alcanza para lo que necesitamos.

## 2026-11-07: Reglas históricas reforzadas con triggers
Además de la API, la BD rechaza DELETE en tablas históricas (`forbid_delete`) y UPDATE/DELETE en los
libros (`inventory_movements`, `financial_transactions`, `audit_logs`, `product_price_history`,
`purchase_items`; `forbid_change`). Los ítems de un pedido solo cambian si está PENDIENTE y sin pagos.
**Por qué:** "no eliminar registros históricos" es la regla más importante para la consistencia
financiera; un bug o una consulta manual no debe poder romperla.

## 2026-11-07: Sin migraciones "down"
Las migraciones solo avanzan. En dev se vuelve a cero con `reset-dev.sh`; en staging/prod un error se
corrige con una migración nueva.
**Por qué:** con históricos que no se borran, un "down" en prod perdería datos.

## 2026-11-07: Compras y gastos sin `business_date` propio
Se reportan por `purchase_date` / `expense_date` (la fecha real que elige el usuario, que puede ser
anterior al registro); esa fecha se copia a `financial_transactions.business_date`.
El precio unitario de compra es en Bs con 2 decimales y `line_total = round(cantidad · precio, 2)`.

## 2026-11-07: Puertos dev 5444 / 8082
5432–5442 y 8080 ya los usan otros proyectos locales (gyros, Hobby-Store, etc.).

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
