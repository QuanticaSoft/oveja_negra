#!/usr/bin/env bash
# Carga la cartilla de demostración (seeds/demo.sql) y sus fotos. Nunca en prod.
# Las fotos se procesan en el contenedor dev con el mismo ImageProcessor de la API;
# para staging, después se copian a la carpeta de media de flamenco.
# Uso: backend_api/scripts/seed.sh dev|staging
source "$(dirname "$0")/lib.sh"

ENV="${1:-}"
case "$ENV" in
  dev|staging) ;;
  prod) echo "seed.sh no se ejecuta en prod: prod nunca lleva datos de demo." >&2; exit 1 ;;
  *) echo "Uso: seed.sh dev|staging" >&2; exit 1 ;;
esac
SCHEMA="$(schema_for_env "$ENV")"
require_git_ref_for_env "$ENV"

echo "→ procesando fotos de demo (contenedor dev)"
"$BACKEND_DIR/scripts/setup-media.sh" dev >/dev/null
docker compose -f "$COMPOSE_FILE" exec -T api php scripts/process-demo-media.php public/media

if [[ "$ENV" == "staging" ]]; then
  MEDIA_DIR="$(media_dir_for_env staging)"
  remote "test -f $MEDIA_DIR/.htaccess" || {
    echo "Falta preparar $MEDIA_DIR: ejecuta antes scripts/setup-media.sh staging" >&2; exit 1;
  }
  echo "→ copiando fotos a $MEDIA_DIR/demo"
  rsync -az -e "ssh ${SSH_OPTS[*]}" "$BACKEND_DIR/public/media/demo/" "$REMOTE_HOST:$MEDIA_DIR/demo/"
fi

echo "→ [$ENV/$SCHEMA] cargando seeds/demo.sql"
{
  echo "BEGIN;"
  echo "SET LOCAL search_path TO $SCHEMA;"
  cat "$BACKEND_DIR/seeds/demo.sql"
  echo "COMMIT;"
} | run_psql "$ENV"

echo "Demo cargada en $ENV ($SCHEMA)."
