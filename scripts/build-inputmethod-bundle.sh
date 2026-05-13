#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
DIST_DIR="$ROOT_DIR/dist"
BUNDLE_DIR="$DIST_DIR/KnowType.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

swift build --package-path "$ROOT_DIR" --configuration "$CONFIGURATION" --product KnowTypeInputMethodApp >&2
BIN_DIR="$(swift build --package-path "$ROOT_DIR" --configuration "$CONFIGURATION" --show-bin-path 2>/dev/null)"

rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$CONTENTS_DIR/Resources"
cp "$BIN_DIR/KnowTypeInputMethodApp" "$MACOS_DIR/KnowTypeInputMethodApp"
cp "$ROOT_DIR/Resources/InputMethod/Info.plist" "$CONTENTS_DIR/Info.plist"
for resource_file in "$ROOT_DIR"/Resources/InputMethod/*; do
  [[ -f "$resource_file" ]] || continue
  [[ "$(basename "$resource_file")" == "Info.plist" ]] && continue
  cp "$resource_file" "$CONTENTS_DIR/Resources/"
done
chmod +x "$MACOS_DIR/KnowTypeInputMethodApp"

SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --deep --sign "$SIGN_IDENTITY" "$BUNDLE_DIR" >/dev/null

echo "$BUNDLE_DIR"
