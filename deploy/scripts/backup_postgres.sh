#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/safernotes/app}"
ENV_FILE="${SAFERNOTES_ENV_FILE:-/opt/safernotes/.env.production}"
COMPOSE_FILE="${SAFERNOTES_COMPOSE_FILE:-$PROJECT_DIR/deploy/docker-compose.prod.yml}"
BACKUP_DIR="${SAFERNOTES_BACKUP_DIR:-/opt/safernotes/backups/db}"
RETENTION_DAYS="${SAFERNOTES_BACKUP_RETENTION_DAYS:-14}"
REMOTE_TARGET="${SAFERNOTES_BACKUP_REMOTE_TARGET:-}"
REMOTE_SSH_PORT="${SAFERNOTES_BACKUP_SSH_PORT:-}"
REMOTE_SSH_KEY="${SAFERNOTES_BACKUP_SSH_KEY:-}"

read_env() {
  local key="$1"
  local fallback="$2"
  local value
  value="$(awk -F= -v key="$key" '$1 == key {print substr($0, length(key) + 2)}' "$ENV_FILE" | tail -n 1)"
  value="${value%\"}"
  value="${value#\"}"
  if [ -z "$value" ]; then
    value="$fallback"
  fi
  printf '%s' "$value"
}

POSTGRES_USER="${POSTGRES_USER:-$(read_env POSTGRES_USER safernotes)}"
POSTGRES_DB="${POSTGRES_DB:-$(read_env POSTGRES_DB safernotes)}"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_file="$BACKUP_DIR/safernotes-$timestamp.sql.gz"

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres \
  pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip -9 > "$backup_file"

chmod 600 "$backup_file"
find "$BACKUP_DIR" -type f -name "safernotes-*.sql.gz" -mtime +"$RETENTION_DAYS" -delete

if [ -n "$REMOTE_TARGET" ]; then
  rsync_ssh="ssh"
  if [ -n "$REMOTE_SSH_PORT" ]; then
    rsync_ssh="$rsync_ssh -p $REMOTE_SSH_PORT"
  fi
  if [ -n "$REMOTE_SSH_KEY" ]; then
    rsync_ssh="$rsync_ssh -i $REMOTE_SSH_KEY -o IdentitiesOnly=yes"
  fi
  rsync -az -e "$rsync_ssh" "$backup_file" "$REMOTE_TARGET/"
fi

echo "$backup_file"
