#!/usr/bin/env bash
# Crea la carpeta de imágenes del entorno y le pone el .htaccess de seguridad.
# En flamenco además le da a la carpeta el tipo SELinux de escritura para PHP-FPM
# (httpd_sys_rw_content_t). chcon no necesita root si la carpeta es de marco, pero
# debe ir ANTES de escribir archivos: no re-etiqueta los que ya existen.
# Uso: backend_api/scripts/setup-media.sh dev|staging|prod
source "$(dirname "$0")/lib.sh"

ENV="${1:-}"
case "$ENV" in
  dev)
    mkdir -p "$BACKEND_DIR/public/media"
    cp "$BACKEND_DIR/scripts/media.htaccess" "$BACKEND_DIR/public/media/.htaccess"
    echo "Media de dev lista en backend_api/public/media"
    exit 0 ;;
  staging|prod) ;;
  *) echo "Uso: setup-media.sh dev|staging|prod" >&2; exit 1 ;;
esac

MEDIA_DIR="$(media_dir_for_env "$ENV")"
confirm_prod "$ENV"

remote "mkdir -p $MEDIA_DIR && chcon -t httpd_sys_rw_content_t $MEDIA_DIR"
scp -q "${SSH_OPTS[@]}" "$BACKEND_DIR/scripts/media.htaccess" "$REMOTE_HOST:$MEDIA_DIR/.htaccess"
remote "chmod 644 $MEDIA_DIR/.htaccess && ls -dZ $MEDIA_DIR"
echo "Media de $ENV lista en $MEDIA_DIR"
