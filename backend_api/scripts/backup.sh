#!/usr/bin/env bash
# Respaldo solo del schema de OVEJA_NEGRA (nunca del resto de gyros).
# Uso: backend_api/scripts/backup.sh staging|prod
source "$(dirname "$0")/lib.sh"

ENV="${1:-}"
[[ "$ENV" == "staging" || "$ENV" == "prod" ]] || { echo "Uso: backup.sh staging|prod" >&2; exit 1; }
SCHEMA="$(schema_for_env "$ENV")"

exists="$(echo "SELECT 1 FROM pg_namespace WHERE nspname = '$SCHEMA';" | run_psql "$ENV" -At)"
if [[ "$exists" != "1" ]]; then
  echo "El schema $SCHEMA aún no existe: no hay nada que respaldar."
  exit 0
fi

mkdir -p "$REPO_ROOT/backups"
out="$REPO_ROOT/backups/${SCHEMA}-$(date +%Y%m%d-%H%M%S).dump"
remote pg_dump -d "$REMOTE_DB" -n "$SCHEMA" -Fc > "$out"
echo "Backup: $out"
