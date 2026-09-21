#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FRONTEND_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$FRONTEND_DIR"

API_BASE_URL="${API_BASE_URL:-}"
KEY_PROPERTIES="$FRONTEND_DIR/android/key.properties"

case "$API_BASE_URL" in
  http://127.0.0.1:*|http://localhost:*|http://10.0.2.2:*|http://192.168.*)
    echo "Refusing to build a Play Store bundle against local API_BASE_URL=$API_BASE_URL" >&2
    echo "Use an HTTPS self-hosted API for release builds." >&2
    exit 1
    ;;
esac

if [ ! -f "$KEY_PROPERTIES" ]; then
  echo "Missing Android upload signing config: $KEY_PROPERTIES" >&2
  echo "Create it from android/key.properties.example before building a Play Store bundle." >&2
  exit 1
fi

ORG_GRADLE_PROJECT_usesCleartextTraffic="${ORG_GRADLE_PROJECT_usesCleartextTraffic:-false}" \
  ./tool/flutterw build appbundle --release --dart-define=API_BASE_URL="$API_BASE_URL"
