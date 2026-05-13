#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
DIST_DIR="$ROOT_DIR/dist"
BUNDLE_DIR="$DIST_DIR/KnowType.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

swift build --configuration "$CONFIGURATION" --product KnowTypeInputMethodApp >&2
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path 2>/dev/null)"

rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$CONTENTS_DIR/Resources"
cp "$BIN_DIR/KnowTypeInputMethodApp" "$MACOS_DIR/KnowTypeInputMethodApp"
cp "$ROOT_DIR/Resources/InputMethod/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/KnowTypeInputMethodApp"

echo "$BUNDLE_DIR"
