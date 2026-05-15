#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"
BUNDLE_PATH="$("$ROOT_DIR/scripts/build-inputmethod-bundle.sh" | tail -n 1)"
TARGET_DIR="$HOME/Library/Input Methods"
TARGET_PATH="$TARGET_DIR/KnowType.app"
INPUTSOURCE_TOOL="$(knowtype_inputsource_tool "$ROOT_DIR")"

mkdir -p "$TARGET_DIR"

"$INPUTSOURCE_TOOL" switch-away >/dev/null 2>&1 || true

killall KnowTypeInputMethodApp 2>/dev/null || true
rm -rf "$TARGET_PATH"
cp -R "$BUNDLE_PATH" "$TARGET_PATH"
rm -rf "$BUNDLE_PATH"

open "$TARGET_PATH" >/dev/null 2>&1 || true
sleep 0.25

"$INPUTSOURCE_TOOL" register --path "$TARGET_PATH" --select

echo "Installed KnowType to: $TARGET_PATH"
echo "Run ./scripts/diagnose-inputmethod.sh --strict for the read-only install status check."
echo "Activate the target text app, run ./scripts/select-inputmethod.sh --require-selected, then type a real probe before manual acceptance."
echo "If diagnostics show HIToolbox selected preference is still Apple Pinyin, choose KnowType from the active app's input menu/System Settings."
