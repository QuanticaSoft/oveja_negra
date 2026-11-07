#!/usr/bin/env bash
# Borra el schema de dev para volver a migrar desde cero. Las migraciones no tienen
# "down": en staging/prod una corrección es siempre una migración nueva.
# Uso: backend_api/scripts/reset-dev.sh
source "$(dirname "$0")/lib.sh"

[[ $# -eq 0 ]] || { echo "reset-dev.sh no acepta argumentos: solo actúa sobre dev." >&2; exit 1; }

printf '%s\n' "SET client_min_messages TO warning;" "DROP SCHEMA IF EXISTS oveja_negra CASCADE;" | run_psql dev
echo "Schema oveja_negra de dev borrado. Ejecuta: backend_api/scripts/migrate.sh dev"
