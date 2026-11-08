#!/usr/bin/env bash
# Nightly n8n backup: pg_dump -> verify -> upload to private Supabase bucket -> prune.
#
# Suggested cron (daily 03:00, as user "deploy"; edit with `crontab -e`).
# NOT installed by this script:
#   0 3 * * * /home/deploy/n8n/deploy/backup.sh >> /home/deploy/backups/backup.log 2>&1
#
# Secrets live in /home/deploy/.backup.env (never in this script):
#   chmod 600 /home/deploy/.backup.env
#   SUPABASE_URL=https://<project-ref>.supabase.co
#   SUPABASE_BUCKET=<private bucket name>
#   SUPABASE_SERVICE_KEY=<service role key>
#
# This backs up the database only. N8N_ENCRYPTION_KEY must be stored separately.

set -euo pipefail

BACKUP_DIR=/home/deploy/backups
BACKUP_ENV=/home/deploy/.backup.env
RETENTION_DAYS=7
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
COMPOSE=(docker compose -f "$SCRIPT_DIR/docker-compose.yml")

log() { printf '%s [backup] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
trap 'log "FAILED (line $LINENO)"' ERR

if [[ ! -f "$BACKUP_ENV" ]]; then
  log "missing $BACKUP_ENV"
  exit 1
fi
if [[ "$(stat -c %a "$BACKUP_ENV")" != "600" ]]; then
  log "$BACKUP_ENV must be chmod 600"
  exit 1
fi
# shellcheck disable=SC1090
source "$BACKUP_ENV"
: "${SUPABASE_URL:?SUPABASE_URL not set in $BACKUP_ENV}"
: "${SUPABASE_BUCKET:?SUPABASE_BUCKET not set in $BACKUP_ENV}"
: "${SUPABASE_SERVICE_KEY:?SUPABASE_SERVICE_KEY not set in $BACKUP_ENV}"

mkdir -p "$BACKUP_DIR"
NAME="n8n-$(date +%Y%m%d-%H%M%S).dump"
DUMP="$BACKUP_DIR/$NAME"

log "dumping database to $DUMP"
if ! "${COMPOSE[@]}" exec -T postgres sh -c 'pg_dump -Fc -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > "$DUMP"; then
  rm -f "$DUMP"
  log "pg_dump failed"
  exit 1
fi

log "verifying dump"
if [[ ! -s "$DUMP" ]]; then
  rm -f "$DUMP"
  log "dump is empty"
  exit 1
fi
if ! "${COMPOSE[@]}" exec -T postgres pg_restore --list < "$DUMP" > /dev/null; then
  rm -f "$DUMP"
  log "pg_restore --list failed; dump is not readable"
  exit 1
fi
log "dump OK ($(stat -c %s "$DUMP") bytes)"

# Auth headers go through a curl config on a pipe so the key never appears in `ps`.
log "uploading to bucket $SUPABASE_BUCKET"
curl --silent --show-error --fail-with-body \
  --config <(printf 'header = "Authorization: Bearer %s"\nheader = "apikey: %s"\n' \
    "$SUPABASE_SERVICE_KEY" "$SUPABASE_SERVICE_KEY") \
  -X POST \
  -H "Content-Type: application/octet-stream" \
  --data-binary "@$DUMP" \
  "${SUPABASE_URL%/}/storage/v1/object/${SUPABASE_BUCKET}/${NAME}" > /dev/null
log "upload OK"

log "removing local dumps older than $RETENTION_DAYS days"
find "$BACKUP_DIR" -maxdepth 1 -name 'n8n-*.dump' -type f -mtime +"$RETENTION_DAYS" -print -delete

log "done"
