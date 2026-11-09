#!/usr/bin/env bash
# Publica la API en flamenco.
#   código  → ~/oveja_negra/<env>/                          (fuera del docroot)
#   public/ → /webs/quanticasoft/oveja_negra/<api|api-staging>/
# Uso: backend_api/scripts/deploy.sh staging|prod
source "$(dirname "$0")/lib.sh"

ENV="${1:-}"
case "$ENV" in
  staging) WEB_DIR="$REMOTE_WEB_BASE/api-staging" ;;
  prod)    WEB_DIR="$REMOTE_WEB_BASE/api" ;;
  *) echo "Uso: deploy.sh staging|prod" >&2; exit 1 ;;
esac
APP_DIR="$REMOTE_APP_BASE/$ENV"

require_git_ref_for_env "$ENV"
confirm_prod "$ENV"

remote "test -f $APP_DIR/config.local.php" || {
  echo "Falta $APP_DIR/config.local.php en flamenco (ver config.local.php.example)." >&2; exit 1;
}

remote "mkdir -p $WEB_DIR"

rsync -az --delete -e "ssh ${SSH_OPTS[*]}" \
  --exclude config.local.php --exclude public/ --exclude scripts/ --exclude sql/ --exclude tests/ --exclude seeds/ \
  "$BACKEND_DIR/" "$REMOTE_HOST:$APP_DIR/"

rsync -az --delete -e "ssh ${SSH_OPTS[*]}" --exclude app_root.php --exclude media/ \
  "$BACKEND_DIR/public/" "$REMOTE_HOST:$WEB_DIR/"

remote \
  "printf '%s\n' '<?php' \"return '$APP_DIR';\" > $WEB_DIR/app_root.php"

echo "Desplegado $ENV → https://www.quanticasoft.com/oveja_negra/$(basename "$WEB_DIR")/v1/health"
