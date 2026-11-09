# Funciones comunes de los scripts de backend_api. Se usa con "source".
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
BACKEND_DIR="$REPO_ROOT/backend_api"
COMPOSE_FILE="$REPO_ROOT/infra/docker-compose.dev.yml"
REMOTE_HOST="flamenco"
REMOTE_DB="gyros"
REMOTE_APP_BASE="/home/marco/oveja_negra"
REMOTE_WEB_BASE="/webs/quanticasoft/oveja_negra"

# Una sola conexión SSH reutilizada por todo el script: flamenco rechaza a
# veces conexiones nuevas seguidas (timeouts intermitentes en el puerto 22).
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=20 -o ControlMaster=auto
          -o "ControlPath=$HOME/.ssh/cm-ovejanegra-%r@%h:%p" -o ControlPersist=120)

remote() {
  local status=0
  ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "$@" || status=$?
  if [[ $status -eq 255 ]]; then
    echo "No se pudo conectar a $REMOTE_HOST por SSH. Reintenta." >&2; exit 1
  fi
  return $status
}

# Nunca devuelve otro schema: gyros (public) y hobbystore* son de otras apps.
schema_for_env() {
  case "$1" in
    dev|prod) echo "oveja_negra" ;;
    staging)  echo "oveja_negra_staging" ;;
    *) echo "Entorno inválido: $1 (dev|staging|prod)" >&2; exit 1 ;;
  esac
}

# Fuera de public/ de la API: deploy.sh hace rsync --delete y la borraría.
media_dir_for_env() {
  case "$1" in
    staging) echo "$REMOTE_WEB_BASE/media-staging" ;;
    prod)    echo "$REMOTE_WEB_BASE/media" ;;
    *) echo "Entorno sin media remota: $1" >&2; exit 1 ;;
  esac
}

# staging solo desde develop; prod solo desde un tag vX.Y.Z contenido en main.
require_git_ref_for_env() {
  local env="$1"
  [[ "$env" == "dev" ]] && return 0

  # Lo no trackeado solo importa dentro de backend_api: es lo que rsync publicaría.
  if [[ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no)" \
     || -n "$(git -C "$REPO_ROOT" ls-files --others --exclude-standard -- backend_api)" ]]; then
    echo "Hay cambios sin commitear. Abortando." >&2; exit 1
  fi

  if [[ "$env" == "staging" ]]; then
    local branch
    branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
    [[ "$branch" == "develop" ]] || { echo "staging se despliega desde develop (estás en $branch)." >&2; exit 1; }
  else
    local tag
    tag="$(git -C "$REPO_ROOT" describe --exact-match --tags HEAD 2>/dev/null || true)"
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "prod requiere HEAD en un tag vX.Y.Z." >&2; exit 1; }
    git -C "$REPO_ROOT" merge-base --is-ancestor HEAD main \
      || { echo "El tag $tag no está en main." >&2; exit 1; }
  fi
}

confirm_prod() {
  [[ "$1" == "prod" ]] || return 0
  read -r -p "Vas a modificar PRODUCCIÓN. Escribe 'prod' para continuar: " answer
  [[ "$answer" == "prod" ]] || { echo "Cancelado." >&2; exit 1; }
}

# Ejecuta psql leyendo el SQL de stdin; los argumentos extra son flags simples (p.ej. -At).
run_psql() {
  local env="$1"; shift
  if [[ "$env" == "dev" ]]; then
    docker compose -f "$COMPOSE_FILE" exec -T db \
      psql -X -q -v ON_ERROR_STOP=1 -U oveja -d oveja_negra_dev "$@"
  else
    remote psql -X -q -v ON_ERROR_STOP=1 -d "$REMOTE_DB" "$@"
  fi
}
