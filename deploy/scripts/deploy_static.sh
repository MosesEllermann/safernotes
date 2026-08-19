#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <ssh-key-file> <user@host> <landing-path> <app-path>" >&2
  exit 1
fi

SSH_KEY="$1"
TARGET="$2"
LANDING_PATH="$3"
APP_PATH="$4"

rsync -az --delete -e "ssh -i $SSH_KEY" website/ "$TARGET:$LANDING_PATH/"
rsync -az --delete -e "ssh -i $SSH_KEY" frontend/build/web/ "$TARGET:$APP_PATH/"
