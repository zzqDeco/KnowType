#!/usr/bin/env bash
set -euo pipefail

DEFAULT_BUNDLE_PATH="$HOME/Library/Input Methods/KnowType.app"
BUNDLE_PATH="${KNOWTYPE_BUNDLE_PATH:-$DEFAULT_BUNDLE_PATH}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/inputsource-ids.sh"
source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"
source "$ROOT_DIR/scripts/lib/inputmethod-installation.sh"

usage() {
  cat <<'EOF'
Usage: scripts/repair-inputmethod-selection.sh [--path /path/to/KnowType.app]

Repairs local Text Input Source selection state for development installs.

The script keeps the installed KnowType bundle in ~/Library/Input Methods,
unregisters stale LaunchServices records for older KnowType build paths,
disables legacy TIS modes when they are still visible, repairs stale KnowType
rows in local input-source preferences, refreshes the Text Input menu agents,
requests KnowType selection through the input-source helper, and prints a fresh
diagnostic summary. It does not directly approve or add KnowType to the protected
third-party input-source list; if KnowType is missing from System Settings, add
it there.

The default install path avoids launching the input method host and uses the
dedicated TIS helper. This script is the explicit local development fallback for
  poisoned .Hans/.Mode caches or stale selected input-source rows; it may require
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

canonical_installed_bundle_path="$(knowtype_canonical_bundle_path "$BUNDLE_PATH")"
backup_dir="$HOME/Library/Application Support/KnowType"
timestamp="$(date +%Y%m%d%H%M%S)"
mkdir -p "$backup_dir"

for plist in "$HOME/Library/Preferences/com.apple.HIToolbox.plist" "$HOME/Library/Preferences/com.apple.inputsources.plist"; do
  if [[ -f "$plist" ]]; then
    cp "$plist" "$backup_dir/$(basename "$plist" .plist)-before-selection-repair-$timestamp.plist"
  fi
done

knowtype_cleanup_local_duplicate_bundles_except "$canonical_installed_bundle_path" 0
knowtype_unregister_launchservices_records_except "$canonical_installed_bundle_path" 0
knowtype_register_launchservices_path "$BUNDLE_PATH" 0

INPUTSOURCE_TOOL="$(knowtype_inputsource_tool "$ROOT_DIR")"
"$INPUTSOURCE_TOOL" purge-legacy \
  --path "$BUNDLE_PATH" \
  --parent-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
  --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID"
if ! "$BUNDLE_EXECUTABLE" --knowtype-register-input-source --knowtype-enable-input-source; then
  echo "warning: installed app input-source register/enable failed; continuing with helper repair and diagnostics" >&2
fi
"$INPUTSOURCE_TOOL" repair-preferences \
  --bundle-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
  --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" \
  --include-history \
  --add-active

killall cfprefsd 2>/dev/null || true
killall TextInputMenuAgent 2>/dev/null || true
killall TextInputSwitcher 2>/dev/null || true
sleep 1

set +e
selection_output="$("$BUNDLE_EXECUTABLE" --knowtype-select-input-source 2>&1)"
bootstrap_select_status=$?
set -e
printf '%s\n' "$selection_output"
if (( bootstrap_select_status != 0 )); then
  echo "warning: installed app KnowType selection returned $bootstrap_select_status; continuing with enabled/history repair, menu refresh, and diagnostics" >&2
fi

repair_args=(
  repair-preferences
  --bundle-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID"
  --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID"
  --include-history
  --add-active
)
if (( bootstrap_select_status == 0 )); then
  repair_args+=(--include-selected)
fi
"$INPUTSOURCE_TOOL" "${repair_args[@]}"

killall cfprefsd 2>/dev/null || true
killall TextInputMenuAgent 2>/dev/null || true
killall TextInputSwitcher 2>/dev/null || true
sleep 0.75

echo
echo "Selection repair finished for: $BUNDLE_PATH"
echo "Input source activation used the installed app context: register, enable, and select through TIS."
echo "macOS may still prelaunch the input method host; KnowType keeps Rime/user data lazy until real input."
echo "Local repair restored the visible KnowType input mode."
if (( bootstrap_select_status == 0 )); then
  echo "History and selected preferences are repaired to point at KnowType's visible .Hans input mode."
else
  echo "History preferences were repaired to keep KnowType available; selected preferences were not rewritten because installed app selection failed."
fi
echo "If KnowType is still missing from the input menu, remove and add it once in System Settings > Keyboard > Text Input > Input Sources."
echo "If the menu still shows an old state, log out/in to clear macOS TIS cache."
echo
"$ROOT_DIR/scripts/diagnose-inputmethod.sh" --strict --path "$BUNDLE_PATH"
