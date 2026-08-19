#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FRONTEND_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$FRONTEND_DIR"

if [ ! -d web ] || [ ! -d android ] || [ ! -d ios ]; then
  ./tool/flutterw create --project-name safernotes_app --platforms=web,android,ios .
fi

./tool/flutterw pub get
./tool/flutterw run -d web-server --web-hostname=localhost --web-port=3000 --dart-define=API_BASE_URL="${API_BASE_URL:-http://127.0.0.1:8000}"
