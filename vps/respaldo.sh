#!/usr/bin/env bash
# LoEntrego · Respaldo diario de la base de datos
# Guarda 14 días en el servidor y sube una copia cifrada al almacenamiento de objetos (rclone).
# Remoto de rclone esperado: "respaldo" (rclone config → p. ej. Cloudflare R2 o Backblaze B2, con capa crypt).
set -euo pipefail
source /srv/loentrego/.env
DIR=/srv/loentrego/respaldos
ARCHIVO="$DIR/loentrego-$(date +%F-%H%M).dump"
pg_dump --format=custom --no-owner "$DATABASE_URL" -f "$ARCHIVO"
find "$DIR" -name 'loentrego-*.dump' -mtime +14 -delete
if rclone listremotes | grep -q '^respaldo:'; then
  rclone copy "$ARCHIVO" respaldo:loentrego-db/ --quiet
fi
echo "$(date -Is) respaldo ok: $(du -h "$ARCHIVO" | cut -f1)"
# Restaurar:  pg_restore --clean --no-owner -d "$DATABASE_URL" archivo.dump
