#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${1:-/opt/safernotes/app}"
ENV_FILE="${SAFERNOTES_ENV_FILE:-/opt/safernotes/.env.production}"
COMPOSE_FILE="${SAFERNOTES_COMPOSE_FILE:-$PROJECT_DIR/deploy/docker-compose.prod.yml}"

cd "$PROJECT_DIR"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing production env file: $ENV_FILE" >&2
  exit 1
fi

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

API_PORT="${SAFERNOTES_API_PORT:-$(read_env SAFERNOTES_API_PORT 8000)}"

git fetch origin main
git checkout main
git pull --ff-only origin main

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" build api
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d postgres redis
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" run --rm api python manage.py migrate --noinput
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d api

for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:$API_PORT/api/v1/health/live" >/dev/null; then
    echo "Safernotes API is healthy."
    exit 0
  fi
  sleep 2
done

echo "Safernotes API did not become healthy in time." >&2
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" logs --tail=100 api
exit 1
