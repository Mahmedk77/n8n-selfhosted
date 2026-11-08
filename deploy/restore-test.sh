#!/usr/bin/env bash
# Restore a dump into a scratch database, count workflows, drop the scratch DB.
# Proves a backup is restorable without touching the live n8n database.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
COMPOSE=(docker compose -f "$SCRIPT_DIR/docker-compose.yml")

log() { printf '%s [restore-test] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/n8n-YYYYmmdd-HHMMSS.dump" >&2
  echo "Restores the dump into a temporary database, prints the workflow_entity row count, then drops it." >&2
  exit 1
fi

DUMP="$1"
if [[ ! -s "$DUMP" ]]; then
  echo "Dump not found or empty: $DUMP" >&2
  exit 1
fi

SCRATCH="restore_test_$(date +%Y%m%d%H%M%S)"

cleanup() {
  log "dropping scratch database $SCRATCH"
  "${COMPOSE[@]}" exec -T postgres sh -c 'dropdb -U "$POSTGRES_USER" --if-exists "$1"' _ "$SCRATCH" || true
}

log "creating scratch database $SCRATCH"
"${COMPOSE[@]}" exec -T postgres sh -c 'createdb -U "$POSTGRES_USER" "$1"' _ "$SCRATCH"
trap cleanup EXIT

log "restoring $DUMP"
"${COMPOSE[@]}" exec -T postgres sh -c 'pg_restore -U "$POSTGRES_USER" -d "$1" --no-owner' _ "$SCRATCH" < "$DUMP"

COUNT="$("${COMPOSE[@]}" exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$1" -tA -c "SELECT count(*) FROM workflow_entity"' _ "$SCRATCH")"
log "workflow_entity rows: $COUNT"
