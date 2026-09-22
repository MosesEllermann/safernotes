#!/usr/bin/env bash
set -euo pipefail

for required in SPANEL_HOST SPANEL_USER SPANEL_SSH_KEY SPANEL_LANDING_PATH SPANEL_KNOWN_HOSTS; do
  if [[ -z "${!required:-}" ]]; then
    echo "::error::Missing GitHub secret: $required"
    exit 1
  fi
done

deploy_port="${SPANEL_PORT:-22}"
if [[ ! "$SPANEL_HOST" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]] ||
   [[ ! "$SPANEL_USER" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$ ]] ||
   [[ ! "$deploy_port" =~ ^[0-9]{1,5}$ ]] ||
   (( 10#$deploy_port < 1 || 10#$deploy_port > 65535 )); then
  echo '::error::Invalid deployment host, user or SSH port.'
  exit 1
fi
if [[ ! "$SPANEL_LANDING_PATH" =~ ^/[a-zA-Z0-9_./-]+$ ]] ||
   [[ "$SPANEL_LANDING_PATH" == *'..'* ]] ||
   [[ "$SPANEL_LANDING_PATH" == *'/./'* ]] ||
   [[ "$SPANEL_LANDING_PATH" == *'/.' ]] ||
   [[ "$SPANEL_LANDING_PATH" =~ ^/+$ ]]; then
  echo '::error::SPANEL_LANDING_PATH must be the absolute website directory, not the server root.'
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
site_dir="$script_dir/../website"
test -s "$site_dir/index.html"
test -s "$site_dir/docs.html"
upload_filters=(--include='/site.webmanifest' --include='/assets/***')
if [[ "${DEPLOY_ANDROID_APK:-false}" == 'true' ]]; then
  if [[ ! -s "$site_dir/downloads/safernotes-android.apk" ]]; then
    echo '::error::Signed Android APK is missing; nothing will be uploaded.'
    exit 1
  fi
  upload_filters+=(--include='/downloads/' --include='/downloads/safernotes-android.apk')
fi
command -v rsync >/dev/null
command -v ssh >/dev/null

umask 077
deploy_tmp="$(mktemp -d)"
trap 'rm -f "$deploy_tmp/key" "$deploy_tmp/known_hosts"; rmdir "$deploy_tmp"' EXIT
printf '%s\n' "$SPANEL_SSH_KEY" > "$deploy_tmp/key"
printf '%s\n' "$SPANEL_KNOWN_HOSTS" > "$deploy_tmp/known_hosts"

# Use a pinned host key, never an unverified ssh-keyscan result during deployment.
export RSYNC_RSH="ssh -p $deploy_port -i '$deploy_tmp/key' -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile='$deploy_tmp/known_hosts' -o ConnectTimeout=20"

# No --delete: unrelated downloads, .htaccess, ACME files and hosted apps stay intact.
rsync -az --checksum --delay-updates --protect-args --chmod=D755,F644 \
  --include='/*.html' --include='/*.css' --include='/*.js' \
  "${upload_filters[@]}" --exclude='*' \
  "$site_dir/" "$SPANEL_USER@$SPANEL_HOST:${SPANEL_LANDING_PATH%/}/"
