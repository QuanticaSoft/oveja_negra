#!/usr/bin/env bash
# Aplica las migraciones pendientes de backend_api/sql/ al schema del entorno.
# Uso: backend_api/scripts/migrate.sh dev|staging|prod
source "$(dirname "$0")/lib.sh"

ENV="${1:-}"
SCHEMA="$(schema_for_env "$ENV")"
require_git_ref_for_env "$ENV"
confirm_prod "$ENV"

if [[ "$ENV" == "prod" ]]; then
  "$BACKEND_DIR/scripts/backup.sh" prod
fi

run_psql "$ENV" <<SQL
SET client_min_messages TO warning;
CREATE SCHEMA IF NOT EXISTS $SCHEMA;
CREATE TABLE IF NOT EXISTS $SCHEMA.schema_migrations (
    version    text        PRIMARY KEY,
    applied_at timestamptz NOT NULL DEFAULT now()
);
SQL

applied="$(echo "SELECT version FROM $SCHEMA.schema_migrations;" | run_psql "$ENV" -At)"

pending=0
for file in "$BACKEND_DIR"/sql/[0-9][0-9][0-9]_*.sql; do
  version="$(basename "$file" .sql)"
  grep -qx "$version" <<<"$applied" && continue

  echo "→ [$ENV/$SCHEMA] aplicando $version"
  # Cada migración va en su propia transacción y con search_path fijo: los
  # .sql nunca nombran el schema, así jamás pueden caer en public de gyros.
  {
    echo "BEGIN;"
    echo "SET LOCAL search_path TO $SCHEMA;"
    echo "SET LOCAL client_min_messages TO warning;"
    cat "$file"
    echo "INSERT INTO schema_migrations (version) VALUES ('$version');"
    echo "COMMIT;"
  } | run_psql "$ENV"
  pending=$((pending + 1))
done

echo "Listo: $pending migración(es) aplicada(s) en $ENV ($SCHEMA)."
