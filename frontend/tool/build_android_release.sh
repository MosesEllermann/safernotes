#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FRONTEND_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$FRONTEND_DIR"

API_BASE_URL="${API_BASE_URL:-https://api.safernotes.com}"

case "$API_BASE_URL" in
  http://127.0.0.1:*|http://localhost:*|http://10.0.2.2:*|http://192.168.*)
    echo "Refusing to build a release APK against local API_BASE_URL=$API_BASE_URL" >&2
    echo "Use https://api.safernotes.com for release builds." >&2
    exit 1
    ;;
esac

ORG_GRADLE_PROJECT_usesCleartextTraffic="${ORG_GRADLE_PROJECT_usesCleartextTraffic:-false}" \
  ./tool/flutterw build apk --release --dart-define=API_BASE_URL="$API_BASE_URL"
