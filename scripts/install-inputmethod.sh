#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"

usage() {
  cat <<'EOF'
Usage: scripts/install-inputmethod.sh

Builds and installs KnowType.app into ~/Library/Input Methods, then asks the
installed app to register and enable the input source.

Options:
  -h, --help  Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

BUNDLE_PATH="$("$ROOT_DIR/scripts/build-inputmethod-bundle.sh" | tail -n 1)"
TARGET_DIR="$HOME/Library/Input Methods"
TARGET_PATH="$TARGET_DIR/KnowType.app"
INPUTSOURCE_TOOL="$(knowtype_inputsource_tool "$ROOT_DIR")"

mkdir -p "$TARGET_DIR"

"$INPUTSOURCE_TOOL" switch-away >/dev/null 2>&1 || true

killall KnowTypeInputMethodApp 2>/dev/null || true
for _ in {1..30}; do
  if ! pgrep -x KnowTypeInputMethodApp >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
rm -rf "$TARGET_PATH"
cp -R "$BUNDLE_PATH" "$TARGET_PATH"
rm -rf "$BUNDLE_PATH"

open -n "$TARGET_PATH" --args --knowtype-install-activate >/dev/null 2>&1 || true
sleep 1.25
"$INPUTSOURCE_TOOL" status >/dev/null 2>&1 || true

echo "Installed KnowType to: $TARGET_PATH"
echo "Run ./scripts/diagnose-inputmethod.sh --strict for the read-only install status check."
echo "Activate the target text app, run ./scripts/select-inputmethod.sh --require-selected, then type a real probe before manual acceptance."
echo "If System Settings asks to allow 知键/KnowType as an input method, click Allow before testing selection."
echo "If diagnostics show HIToolbox selected preference is still another source, choose KnowType from the active app's input menu/System Settings."
