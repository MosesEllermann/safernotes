#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FRONTEND_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$FRONTEND_DIR"

SIGNING_DIRECTORY="${SAFERNOTES_SIGNING_DIRECTORY:-${XDG_DATA_HOME:-$HOME/.local/share}/safernotes/signing}"
KEYSTORE_PATH="$SIGNING_DIRECTORY/upload-keystore.jks"
KEY_PROPERTIES_PATH="$SIGNING_DIRECTORY/key.properties"
KEY_ALIAS="${KEY_ALIAS:-upload}"
KEY_DNAME="${KEY_DNAME:-CN=Safernotes Upload Key, O=Safernotes}"

if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool was not found. Install a JDK before generating the Android upload key." >&2
  exit 127
fi

if [ -f "$KEYSTORE_PATH" ] || [ -f "$KEY_PROPERTIES_PATH" ]; then
  echo "Refusing to overwrite existing Android signing files." >&2
  echo "Existing files:" >&2
  [ -f "$KEYSTORE_PATH" ] && echo "  $KEYSTORE_PATH" >&2
  [ -f "$KEY_PROPERTIES_PATH" ] && echo "  $KEY_PROPERTIES_PATH" >&2
  exit 1
fi

read -r -s -p "Keystore password: " STORE_PASSWORD
echo
read -r -s -p "Key password (leave empty to reuse keystore password): " KEY_PASSWORD
echo

KEY_PASSWORD="${KEY_PASSWORD:-$STORE_PASSWORD}"

if [ "${#STORE_PASSWORD}" -lt 6 ] || [ "${#KEY_PASSWORD}" -lt 6 ]; then
  echo "Android keystore passwords must be at least 6 characters." >&2
  exit 1
fi

umask 077
mkdir -p "$SIGNING_DIRECTORY"

keytool -genkeypair \
  -v \
  -keystore "$KEYSTORE_PATH" \
  -storepass "$STORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -alias "$KEY_ALIAS" \
  -dname "$KEY_DNAME"

{
  echo "storePassword=$STORE_PASSWORD"
  echo "keyPassword=$KEY_PASSWORD"
  echo "keyAlias=$KEY_ALIAS"
  echo "storeFile=upload-keystore.jks"
} > "$KEY_PROPERTIES_PATH"

echo
echo "Android upload signing is configured."
echo "Keystore: $KEYSTORE_PATH"
echo "Gradle properties: $KEY_PROPERTIES_PATH"
echo "Set SAFERNOTES_SIGNING_PROPERTIES to the Gradle properties path for release builds."
echo "Back up both the keystore and passwords securely."
