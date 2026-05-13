#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_PATH="$("$ROOT_DIR/scripts/build-inputmethod-bundle.sh" | tail -n 1)"
TARGET_DIR="$HOME/Library/Input Methods"
TARGET_PATH="$TARGET_DIR/KnowType.app"

mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_PATH"
cp -R "$BUNDLE_PATH" "$TARGET_PATH"

echo "Installed KnowType to: $TARGET_PATH"
echo "Enable it in System Settings > Keyboard > Text Input > Input Sources."
