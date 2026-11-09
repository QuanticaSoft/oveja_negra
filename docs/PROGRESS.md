# Progreso

## Estado actual
**Fase 8 completa** (PR #14–#17). Prueba del usuario en su teléfono con un APK contra staging; corrección de fechas de madrugada en `fix/fechas-jornada`.

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

- 2026-11-08: Fase 4 (API `0.4.0`):
  - Categorías y productos con nombres únicos, categorías inactivas protegidas y nada se borra.
  - Cambio de precio con `product_price_history` y auditoría; un test confirma que **no altera
    `order_items`**.
  - Disponibilidad ("agotado") la puede marcar el CAJERO; cartilla `GET /v1/menu`.
  - Imágenes con `ImageProcessor` propio: re-codificadas en 800 y 300 px, sin EXIF, con una carpeta
    de media que no ejecuta scripts.
  - Cartilla de demo con 8 fotos CC0 o de dominio público (`seeds/`).
  - Test que obliga a cada ruta a declarar un permiso existente.
  - 83 tests en verde y prueba de punta a punta por HTTP en dev.

- 2026-11-08: Fase 4 integrada (PR #6) y **desplegada en staging**:
  - `setup-media.sh staging` dejó `media-staging` con contexto `httpd_sys_rw_content_t`.
  - Health `0.4.0` y `/v1/menu` sin sesión → 401.
  - Demo cargada (3 categorías, 8 productos con foto); las fotos se sirven como `image/jpeg`.
  - `.htaccess` y un `.php` en media → 403.
  - Pedir la carpeta sin archivo no lista nada: el servidor redirige al login de gyros, por su
    `ErrorDocument 403` global, que no es nuestro.

- 2026-11-08: Fase 5 (API `0.5.0`), sin migraciones ni dependencias nuevas:
  - Pedidos con precios siempre desde la BD, número diario, descuento con permiso y pagos iniciales,
    todo en una sola transacción.
  - Edición de ítems mientras el pedido está PENDIENTE y sin pagos.
  - Estados solo hacia adelante, con saltos; ENTREGADO exige pago completo.
  - Cancelación con motivo que anula los pagos y crea sus reversos (neto 0).
  - Pagos efectivo/QR sin sobrepago; cada uno es un `INGRESO`, y anularlo crea el `EGRESO` de reverso.
  - `Idempotency-Key` en pedidos y pagos: un reintento no duplica, y otra petición con la misma clave da 409.
  - `FinanceLedger`, que reutilizarán compras y gastos.
  - 97 tests en verde y prueba de punta a punta por HTTP en dev.
  - Al probar por HTTP apareció un 500 en `GET /orders/{id}` inexistente (faltaba un helper); se corrigió
    y se agregó el test de 404.
  - Dos tests anteriores insertaban el pedido #1 de una fecha fija y chocaban con los pedidos reales de
    dev; ahora usan fechas que nunca son reales.

- 2026-11-08: Fase 5 integrada (PR #8) y **desplegada en staging**: health `0.5.0`, las rutas de pedidos
  y pagos responden 401 sin sesión y DELETE da 405. El flujo con sesión en staging lo prueba el usuario
  (solo él tiene la contraseña del ADMIN).

- 2026-11-08: Fase 6 (API `0.6.0`), sin migraciones ni dependencias nuevas:
  - Proveedores, categorías de insumo, unidades e insumos (stock mínimo, unidad bloqueada si hay movimientos).
  - Compras con Idempotency-Key en una transacción: entrada por ítem, costo promedio ponderado y
    `EGRESO` en su fecha.
  - Anulación con reverso de stock, costo y egreso (en la fecha de la compra); se rechaza si lo comprado ya se usó.
  - Ajustes (±, con motivo) y consumos manuales; kardex y stock bajo; nunca stock negativo.
  - `InventoryLedger`; `Quantity`, `DateRange` y `Validation::date/quantity/looseOptionalPhone` en Core.
  - Demo: 6 categorías de insumo, 9 insumos y un proveedor.
  - 112 tests en verde. Se verificó que los tests de costo promedio fallan si se rompe la fórmula.
  - Prueba de punta a punta por HTTP en dev.

- 2026-11-08: Fase 6 integrada (PR #10) y **desplegada en staging**:
  - Health `0.6.0`; las rutas de compras, insumos e inventario responden 401 sin sesión.
  - Demo cargada: 6 categorías de insumo, 9 insumos y 1 proveedor. La cartilla sigue con 8 productos
    (idempotente) y el inventario empieza sin movimientos.

- 2026-11-08: Fase 7 (API `0.7.0`), sin migraciones ni dependencias nuevas:
  - Categorías de gasto (solo ADMIN) y gastos con Idempotency-Key, cuyo `EGRESO` y reverso van en la
    fecha del gasto.
  - Libro financiero paginado y resumen (cuadre): cobrado (efectivo/QR) − compras − gastos = resultado,
    todo neto de reversos.
  - Dashboard: resumen, pedidos (vendido, ticket promedio, cancelados, por canal y estado), top 5 y stock bajo.
  - Reportes: ventas diarias y mensuales (con días y meses vacíos), compras por proveedor e insumo,
    gastos por categoría, productos más vendidos y flujo diario con acumulado.
  - `QueryParams` en Core reemplaza a los helpers duplicados de los controllers.
  - Demo: 6 categorías de gasto.
  - 118 tests en verde. Un test de cuadre con pedidos, cancelación, compras y gastos anulados; se verificó
    que falla si las compras no se calculan netas.
  - Prueba de punta a punta por HTTP en dev.

- 2026-11-08: Fase 7 integrada (PR #12) y **desplegada en staging**: health `0.7.0`; las 12 rutas de
  gastos, finanzas, dashboard y reportes responden 401 sin sesión. Demo con 6 categorías de gasto (la
  cartilla, los insumos y el proveedor no se duplicaron).

- 2026-11-08: Fase 8a (app `0.8.0+1`):
  - Proyecto Flutter solo para Android (`com.quanticasoft.ovejanegra`) con las 6 dependencias aprobadas,
    en versiones de al menos dos semanas, verificadas en pub.dev y en Context7.
  - `AuthInterceptor` con un solo refresh a la vez; refresh token cifrado y access token en memoria.
  - `ApiException` con errores por campo; `Money` idéntico al backend; `IdempotencyKey`; hora de La Paz.
  - Login, restauración de la sesión (con reintento sin red), mi cuenta, cambio de contraseña y logout.
  - Tema negro, blanco y naranja; menú según permisos, fijo en tablet y desplegable en teléfono. Las
    secciones de 8b–8d muestran "Disponible en la parte …".
  - HTTP sin cifrar solo en debug; un build de release exige `https`.
  - `flutter analyze` limpio y 16 tests. Se verificó que el test del refresh único falla si se quita.
  - Build en el emulador Pixel 6a: la app llega al API de dev (intento registrado en `auth_attempts`).
  - Docs: `ARCHITECTURE.md` decía que dev usa el puerto 8080; es el 8082.

- 2026-11-08: Fase 8a integrada (PR #14).
- 2026-11-08: Fase 8b (app `0.8.1+2`, dependencia nueva aprobada: `image_picker ^1.2.4`, de flutter.dev):
  - **Nueva venta:**
    - Cartilla en grilla con fotos; los agotados no se pueden tocar.
    - Carrito fijo a la derecha en tablet y desplegable en teléfono.
    - Canal, cliente (WhatsApp), notas y descuento (con permiso).
    - Cobro efectivo, QR o mixto, con vuelto en pantalla (no se envía), o "Guardar sin cobrar".
    - Confirmación con el #N.
  - **Pedidos:** vista de cocina (abiertos de hoy, filtros, se actualiza cada 20 s) y detalle con
    acciones según permisos: avanzar el estado (ENTREGADO bloqueado con saldo), cobrar, editar ítems,
    cancelar y anular pagos con motivo.
  - **Cartilla:** interruptor de agotado (`products.availability`).
  - **Productos:** alta y edición, cambio de precio con historial, activar o desactivar, y foto desde la
    galería o la cámara. Categorías: alta, edición, orden y activación.
  - **Idempotencia:** la clave depende del contenido (`IdempotentOperation`). En un cobro mixto, cada
    pago conserva su clave hasta que se registran todos.
  - `httpAdapterProvider` permite probar pantallas completas contra un servidor falso.
  - `flutter analyze` limpio y 30 tests. Se verificó que el test del reintento falla si cada intento
    genera una clave nueva.
  - Errores encontrados y corregidos:
    - En el cobro mixto, reintentar después de que fallara el segundo pago duplicaba el primero.
    - El indicador de carga seguía girando detrás de la confirmación.
    - Los controladores de texto podían crearse durante el `dispose`.
  - Emulador: la app abre en Nueva venta con la cartilla y las fotos de la demo, servidas por el API de dev.

- 2026-11-08: Fase 8b integrada (PR #15).
- 2026-11-08: Fase 8c (app `0.8.2+3`, sin dependencias nuevas):
  - **Compras:**
    - Listado de los últimos 30 días, detalle y anulación con motivo. Si lo comprado ya se usó, el 409
      se muestra legible ("hay 0,5 kg, se necesitan 2,5 kg") y sugiere registrar un ajuste.
    - Nueva compra: fecha de la boleta (no futura), proveedor, comprobante y forma de pago.
    - Las líneas eligen el insumo con un buscador; el total se calcula como el backend y la compra
      lleva Idempotency-Key.
  - **Proveedores** (pestaña visible solo con `suppliers.manage`).
  - **Insumos:** lista con stock, mínimo, costo promedio, marca de stock bajo y filtro. Detalle con kardex,
    ajuste (sumar o restar, con motivo), edición y activación. Alta con creación de categoría.
  - **Movimientos:** kardex general por tipo. **Consumo:** varios insumos en una sola operación.
  - `Quantity` en milésimas, espejo del backend. Flecha de "volver" en las pantallas de detalle.
  - `flutter analyze` limpio y 38 tests. Se verificó que el test del redondeo de la línea falla sin
    el redondeo de Postgres.
  - Emulador propio (Medium Phone), para no interferir con el del usuario: login como ENCARGADO, menú
    con sus 6 secciones, insumos y kardex con los datos reales de dev (4,5 kg y Bs 48,50, como en la Fase 6).

- 2026-11-08: Fase 8c integrada (PR #16).
- 2026-11-09: Fase 8d (app `0.8.3+4`, sin dependencias nuevas; `fl_chart` revisado en Context7):
  - **Dashboard:** atajos de fecha (hoy, ayer, 7 días, este mes, personalizado ≤ 92 días); caja (cobrado
    en efectivo y QR, compras, gastos, resultado en rojo o verde); pedidos (vendido, ticket, cancelados,
    canal, estado); top 5 y stock bajo.
  - **Gastos:** listado, nuevo gasto con Idempotency-Key, anulación y categorías (solo ADMIN).
  - **Reportes:** ventas diarias y mensuales (barras vendido/cobrado), compras, gastos por categoría,
    productos más vendidos, flujo con línea del acumulado y libro financiero (`finance.read`).
  - **Usuarios:** alta, edición, activación y restablecimiento de contraseña, con mensajes claros para
    `LAST_ADMIN` y similares. Matriz de permisos por rol: casillas del ADMIN bloqueadas y confirmación
    antes de guardar; si cambia el rol propio, la sesión se recarga.
  - Se quitó la pantalla provisoria "Disponible en la parte…": ya no queda ninguna sección pendiente.
  - Error encontrado por los tests: las etiquetas largas del menú desbordaban con letra más ancha (o
    texto agrandado). El menú usa ahora `ListTile`, que recorta con "…".
  - `flutter analyze` limpio y 45 tests. Se verificó que el test de la matriz falla si se quita el bloqueo.
  - Emulador propio: dashboard con datos reales de dev, idéntico al API (cobrado 25 − compras 315,25 −
    gastos 22,50 = −312,75). Ventas diarias con gráfico y días vacíos; fechas pasadas a `dd/MM/yyyy`.

- 2026-11-09: Fase 8d integrada (PR #17). **Fase 8 completa.**
- 2026-11-09: APK de release apuntando a staging (`~/Desktop/oveja_negra_apk/`, firma de debug de la plantilla).
  El usuario lo instaló en un ZTE Blade A34 (Android 13):
  - **"No hay conexión":** se diagnosticó por USB. El certificado de staging (Let's Encrypt YE2/ISRG X2)
    valida en el teléfono y una prueba con la configuración de la app responde 200 en debug y en release.
    El intento del usuario no llegó al servidor porque el WiFi del teléfono se reconectó minutos después.
    Sin cambios de código.
  - **"Gastos y compras no aparecen en reportes":** lo registrado de madrugada quedaba con fecha de
    calendario, fuera de los rangos por jornada. Corregido en la app (ver `DECISIONS.md`), con tests
    que simulan las 00:56 y las 15:00. App `0.8.4+5`.

## Próximo
- PR `fix/fechas-jornada` → `develop` y APK nuevo para el usuario.
- Propuesta: APK de prueba apuntando a staging para que el usuario lo instale en su teléfono.
  Después, Fase 9 (revisión de seguridad, validaciones y documentación).
