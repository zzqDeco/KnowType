#!/usr/bin/env bash
set -euo pipefail

DEFAULT_BUNDLE_PATH="$HOME/Library/Input Methods/KnowType.app"
BUNDLE_PATH="${KNOWTYPE_BUNDLE_PATH:-$DEFAULT_BUNDLE_PATH}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/inputsource-ids.sh"
source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"

usage() {
  cat <<'EOF'
Usage: scripts/repair-inputmethod-selection.sh [--path /path/to/KnowType.app]

Repairs local Text Input Source selection state for development installs.

The script keeps the installed KnowType bundle in ~/Library/Input Methods,
unregisters stale LaunchServices records for older KnowType build paths,
disables legacy TIS modes when they are still visible, repairs stale KnowType
rows in local input-source preferences, restarts the Text Input menu agents,
relaunches the installed input method app, and prints a fresh diagnostic
summary. It does not directly approve or add KnowType to the protected
third-party input-source list; if KnowType is missing from System Settings, add
it there.

The default install path follows mature IMK installers and uses TIS APIs from
KnowType.app. This script is the explicit local development fallback for
poisoned .Mode caches or missing third-party parent anchors; it may require
Full Disk Access for the terminal/Codex process that runs it.

Options:
  --path      Installed KnowType.app path. Defaults to ~/Library/Input Methods/KnowType.app.
  -h, --help  Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
    --path)
      if (($# < 2)); then
        echo "error: --path requires a value" >&2
        exit 2
      fi
      BUNDLE_PATH="$2"
      shift 2
      ;;
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

if [[ ! -d "$BUNDLE_PATH" ]]; then
  echo "error: bundle is missing: $BUNDLE_PATH" >&2
  echo "Run ./scripts/install-inputmethod.sh first." >&2
  exit 1
fi

BUNDLE_EXECUTABLE="$BUNDLE_PATH/Contents/MacOS/KnowTypeInputMethodApp"
if [[ ! -x "$BUNDLE_EXECUTABLE" ]]; then
  echo "error: installed KnowType executable is missing: $BUNDLE_EXECUTABLE" >&2
  exit 1
fi

"$BUNDLE_EXECUTABLE" --knowtype-purge-legacy
INPUTSOURCE_TOOL="$(knowtype_inputsource_tool "$ROOT_DIR")"
"$INPUTSOURCE_TOOL" repair-preferences \
  --bundle-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
  --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" \
  --include-history \
  --add-active

killall cfprefsd 2>/dev/null || true
killall TextInputMenuAgent 2>/dev/null || true
killall TextInputSwitcher 2>/dev/null || true
killall KnowTypeInputMethodApp 2>/dev/null || true
sleep 1

if ! "$BUNDLE_EXECUTABLE" --knowtype-install-activate; then
  echo "warning: installed app could not select KnowType in this process context; continuing so diagnostics can report the persisted state" >&2
fi

"$INPUTSOURCE_TOOL" repair-preferences \
  --bundle-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
  --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" \
  --include-history \
  --add-active

sleep 0.75
open -g "$BUNDLE_PATH" >/dev/null 2>&1 || true
sleep 0.5

killall cfprefsd 2>/dev/null || true
killall TextInputMenuAgent 2>/dev/null || true
killall TextInputSwitcher 2>/dev/null || true
sleep 0.75
open -g "$BUNDLE_PATH" >/dev/null 2>&1 || true
sleep 0.5

echo
echo "Selection repair finished for: $BUNDLE_PATH"
echo "Installed app activation used the mature IMK path: register, enable, and select through TIS from the installed app context."
echo "Local repair removed stale HIToolbox parent/.Mode rows and restored .Hans plus the third-party parent anchor."
echo "If KnowType is still missing from the input menu, remove and add it once in System Settings > Keyboard > Text Input > Input Sources."
echo "If the menu still shows an old state, log out/in to clear macOS TIS cache."
echo
"$ROOT_DIR/scripts/diagnose-inputmethod.sh" --strict --path "$BUNDLE_PATH"
