#!/usr/bin/env bash
set -euo pipefail

# Packages lambda_app/ into build/lambda_pkg.zip (including deps if requirements.txt exists)

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)
APP_DIR="$ROOT_DIR/lambda_app"
BUILD_DIR="$ROOT_DIR/build/lambda_pkg"
ZIP_PATH="$ROOT_DIR/build/lambda.zip"

rm -rf "$BUILD_DIR" "$ZIP_PATH"
mkdir -p "$BUILD_DIR"

if [[ -f "$ROOT_DIR/requirements.txt" ]]; then
  echo "[package] Installing requirements into build dir..."
  python3 -m pip install --upgrade pip >/dev/null
  python3 -m pip install --no-cache-dir -r "$ROOT_DIR/requirements.txt" -t "$BUILD_DIR"
fi

echo "[package] Copying lambda_app sources..."
if command -v rsync >/dev/null 2>&1; then
  rsync -a --exclude "__pycache__" "$APP_DIR/" "$BUILD_DIR/"
else
  cp -R "$APP_DIR"/. "$BUILD_DIR"/
  find "$BUILD_DIR" -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
fi

echo "[package] Zipping to $ZIP_PATH ..."
mkdir -p "$ROOT_DIR/build"
(cd "$BUILD_DIR" && zip -qr "$ZIP_PATH" .)

echo "[package] Done: $ZIP_PATH"
