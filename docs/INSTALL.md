# Instalación

## Dev local

Requisitos: Docker y Flutter (la app llega en la Fase 8). No hace falta PHP ni `psql` en el Mac.

```bash
docker compose -f infra/docker-compose.dev.yml up -d --build   # Postgres :5444 + API :8082
backend_api/scripts/migrate.sh dev
curl localhost:8082/v1/health        # status "ok", migrations = n.º de archivos en sql/
docker compose -f infra/docker-compose.dev.yml exec api php tests/run.php
```

- Puertos 5444/8082: los 5432–5442 y 8080 ya los usan otros proyectos locales.
- Conectarse a la BD dev: `psql -h localhost -p 5444 -U oveja oveja_negra_dev` (password `oveja`),
  o `docker compose -f infra/docker-compose.dev.yml exec db psql -U oveja oveja_negra_dev`.
- Volver a empezar desde cero: `backend_api/scripts/reset-dev.sh && backend_api/scripts/migrate.sh dev`.
- La configuración de dev son los valores por defecto de `backend_api/config.php`; no hace falta
  `config.local.php`.
- Primer ADMIN de dev: `docker compose -f infra/docker-compose.dev.yml exec api php bin/create-admin.php`.
- Cartilla de demo (8 productos con fotos): `backend_api/scripts/seed.sh dev`. Es idempotente.
  Las imágenes quedan en `backend_api/public/media/` (fuera de git) y se sirven en `http://localhost:8082/media/`.

## PostgreSQL

- Producción y staging usan la BD **`gyros`** de flamenco (Postgres 18), compartida con otra app en
  producción. OVEJA_NEGRA vive solo en los schemas `oveja_negra` (prod) y `oveja_negra_staging`.
  Nunca se toca `public` ni otro schema.
- Los schemas los crea `migrate.sh` (`CREATE SCHEMA IF NOT EXISTS`); la tabla `schema_migrations`
  de cada schema registra lo aplicado.
- Cada migración corre en su propia transacción con `SET LOCAL search_path`. Los `.sql` nunca nombran
  el schema. **Una migración aplicada en staging/prod no se edita**: se corrige con una nueva.
- La API, al conectar, fija `search_path`, `TIME ZONE 'America/La_Paz'` y `statement_timeout`
  (10 s por defecto, `db.statement_timeout` en la config). `Db.php` rechaza cualquier schema que no sea
  `oveja_negra` u `oveja_negra_staging`.
- PHP-FPM conecta por **TCP a 127.0.0.1 con password**: SELinux (Enforcing) bloquea el socket Unix.
  Los scripts, que corren por SSH como `marco`, sí usan el socket y no necesitan password.
- Backups: `backend_api/scripts/backup.sh staging|prod` → `backups/<schema>-<fecha>.dump`
  (`pg_dump -n <schema> -Fc`). `migrate.sh prod` hace un backup antes de migrar.

## flamenco (staging / prod)

Sin sudo: todo corre como `marco`. El host `flamenco` debe estar en `~/.ssh/config`
(`HostName flamenco.cnb.net`, `User marco`).

| | staging | prod |
|---|---|---|
| Rama | `develop` | tag `vX.Y.Z` en `main` |
| Código | `~/oveja_negra/staging` | `~/oveja_negra/prod` |
| Público | `/webs/quanticasoft/oveja_negra/api-staging` | `/webs/quanticasoft/oveja_negra/api` |
| Media | `/webs/quanticasoft/oveja_negra/media-staging` | `/webs/quanticasoft/oveja_negra/media` |
| Schema | `gyros.oveja_negra_staging` | `gyros.oveja_negra` |

### Primera vez en un entorno

1. Crear la configuración (el password del rol `marco` nunca va a git ni al chat):
   Estos tres comandos se ejecutan **desde el Mac**, en la raíz del repo, no dentro de flamenco
   (el `scp` copia el archivo del repo local):
   ```bash
   ssh flamenco 'mkdir -p ~/oveja_negra/staging && chmod 700 ~/oveja_negra'
   scp backend_api/config.local.php.example flamenco:oveja_negra/staging/config.local.php
   ssh -t flamenco 'chmod 600 ~/oveja_negra/staging/config.local.php && vi ~/oveja_negra/staging/config.local.php'
   ```
   Completar `db.password`, `db.schema` y `jwt_secret`:
   - El password tiene que ser **idéntico** al del rol `marco`. Lo más seguro es copiar la línea
     `'password' => …` de `~/hobbystore/<env>/config.local.php`; así también llegan bien escapados
     los `'` o `\` que tenga. **No cambiar el password del rol** con `\password`: lo usan gyros y Hobby-Store.
   - `jwt_secret`: `php -r 'echo bin2hex(random_bytes(48)), PHP_EOL;'`, distinto en cada entorno.
   - Para probar la conexión sin mostrar el password:
     `cd ~/oveja_negra/staging && php -r 'require "src/bootstrap.php"; App::db(); echo "OK\n";'`
2. Desde `develop` (staging) o desde el tag (prod), sin cambios pendientes:
   ```bash
   backend_api/scripts/migrate.sh staging
   backend_api/scripts/deploy.sh staging
   curl https://www.quanticasoft.com/oveja_negra/api-staging/v1/health
   ```
   Fuera de prod, health informa la versión de PHP y las extensiones que faltan **del pool PHP-FPM
   real** (`gyros.sock`), que puede no ser el mismo PHP de la terminal.

3. Crear el **primer ADMIN** (lo ejecuta una persona; la contraseña se escribe sin que se vea y
   no queda en ningún lado). Se niega si ya existe un ADMIN; los demás usuarios se crean desde la API.
   ```bash
   ssh -t flamenco 'php ~/oveja_negra/staging/bin/create-admin.php'
   ```
   Las comillas simples son necesarias: sin ellas, el `~` lo expande el Mac a `/Users/mark` y flamenco
   no encuentra el script.
4. Comprobar el login desde el Mac (zsh). La contraseña se escribe en el prompt de la terminal, sin que se
   vea, y el JSON se arma con Python para no ponerla en la línea de comandos:
   ```zsh
   S=https://www.quanticasoft.com/oveja_negra/api-staging/v1
   read -s "PW?Contraseña: "; echo; export PW
   AT=$(python3 -c 'import json,os; print(json.dumps({"identifier":"admin","password":os.environ["PW"]}))' \
     | curl -s -X POST $S/auth/login -H 'Content-Type: application/json' -d @- \
     | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"]["access_token"])')
   curl -s $S/auth/me -H "X-Auth-Token: $AT" | python3 -m json.tool | head -6
   unset PW AT
   ```
   En zsh `read -p` no sirve (significa "coprocess"); se usa `read -s "VAR?Prompt: "`.
   **Nunca escribas una contraseña en un mensaje, ticket o chat.** Si pasa, cámbiala con
   `PATCH /v1/auth/me/password`.

5. Preparar la carpeta de imágenes (una vez por entorno, **antes** de subir ninguna imagen):
   ```zsh
   backend_api/scripts/setup-media.sh staging
   ```
   Crea `/webs/quanticasoft/oveja_negra/media-staging`, le aplica `chcon -t httpd_sys_rw_content_t`
   (sin eso PHP-FPM no puede escribir; no necesita root) e instala el `.htaccess` sin listado ni
   ejecución de scripts. En staging se puede cargar después la demo: `backend_api/scripts/seed.sh staging`.

### Despliegues siguientes
`migrate.sh <env>` (si hay migraciones nuevas) y `deploy.sh <env>`. En prod ambos piden escribir
`prod` para confirmar.
