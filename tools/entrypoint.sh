#!/usr/bin/env sh
set -eu

APP_DIR="${APP_DIR:-/app}"
APP_ENTRY="${APP_ENTRY:-tools/serve.py}"

cd "$APP_DIR"

if [ ! -e "$APP_ENTRY" ]; then
  echo "[entrypoint] APP_ENTRY not found: $APP_ENTRY" >&2
  echo "[entrypoint] Current dir: $(pwd)" >&2
  ls -la >&2 || true
  exit 64
fi

echo "[entrypoint] Starting: python3 $APP_ENTRY (HOST=${HOST:-0.0.0.0}, PORT=${PORT:-8000})"
exec python3 -u "$APP_ENTRY"
