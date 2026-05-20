#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/inputsource-ids.sh"
source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"
source "$ROOT_DIR/scripts/lib/inputmethod-installation.sh"
DRY_RUN=0
CONFIGURATION="${CONFIGURATION:-release}"

usage() {
  cat <<'EOF'
Usage: scripts/install-inputmethod.sh [--configuration debug|release] [--dry-run]

Builds and installs KnowType.app into ~/Library/Input Methods, installs
KnowType.prefPane into ~/Library/PreferencePanes, then asks the installed app
to register and enable the input source.

Options:
  --configuration  SwiftPM build configuration. Defaults to CONFIGURATION or release.
  --dry-run        Print local bundles and LaunchServices records that would be cleaned.
  -h, --help       Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
    --configuration)
      if (($# < 2)); then
        echo "error: --configuration requires a value" >&2
        exit 2
      fi
      CONFIGURATION="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
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

case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "error: --configuration must be debug or release" >&2
    exit 2
    ;;
esac

LOCAL_BUILD_VERSION="${KNOWTYPE_BUNDLE_BUILD_VERSION:-$(date +%Y%m%d%H%M%S)}"
TARGET_DIR="$(knowtype_inputmethod_target_dir)"
TARGET_PATH="$(knowtype_inputmethod_target_path)"
PREFPANE_TARGET_DIR="$(knowtype_preferencepane_target_dir)"
PREFPANE_TARGET_PATH="$(knowtype_preferencepane_target_path)"

if (( DRY_RUN == 1 )); then
  echo "KnowType input-method install dry run"
  echo "Target bundle: $TARGET_PATH"
  echo "Target System Settings pane: $PREFPANE_TARGET_PATH"
  echo
  echo "Local KnowType bundles that would be removed before install:"
  local_bundle_count=0
  while IFS= read -r bundle_path; do
    [[ -n "$bundle_path" ]] || continue
    local_bundle_count=$((local_bundle_count + 1))
    echo "  $bundle_path"
  done < <(knowtype_find_local_inputmethod_bundle_paths)
  if (( local_bundle_count == 0 )); then
    echo "  <none>"
  fi
  echo
  echo "LaunchServices records that would be unregistered:"
  ls_count=0
  while IFS= read -r bundle_path; do
    [[ -n "$bundle_path" ]] || continue
    ls_count=$((ls_count + 1))
    echo "  $(knowtype_expand_home_path "$(knowtype_strip_lsregister_suffix "$bundle_path")")"
  done < <(knowtype_launchservices_paths_for_identity)
  if (( ls_count == 0 )); then
    echo "  <none>"
  fi
  if [[ -d "$PREFPANE_TARGET_PATH" ]]; then
    echo
    echo "System Settings pane that would be replaced:"
    echo "  $PREFPANE_TARGET_PATH"
  fi
  echo
  echo "Text Input Source preference rows would be repaired and menu agents would be restarted."
  exit 0
fi

BUNDLE_PATH="$(KNOWTYPE_BUNDLE_BUILD_VERSION="$LOCAL_BUILD_VERSION" "$ROOT_DIR/scripts/build-inputmethod-bundle.sh" --configuration "$CONFIGURATION" | tail -n 1)"
PREFPANE_PATH="$("$ROOT_DIR/scripts/build-preference-pane.sh" --configuration "$CONFIGURATION" | tail -n 1)"
INSTALLED_EXECUTABLE="$TARGET_PATH/Contents/MacOS/KnowTypeInputMethodApp"

INPUTSOURCE_TOOL=""

inputsource_tool_path() {
  if [[ -z "$INPUTSOURCE_TOOL" ]]; then
    INPUTSOURCE_TOOL="$(knowtype_inputsource_tool "$ROOT_DIR")"
  fi
  printf '%s\n' "$INPUTSOURCE_TOOL"
}

switch_away_before_replace() {
  local switched=1
  if [[ -x "$INSTALLED_EXECUTABLE" ]]; then
    "$INSTALLED_EXECUTABLE" --knowtype-switch-away >/dev/null 2>&1 &
    local switch_pid=$!
    for _ in {1..20}; do
      if ! kill -0 "$switch_pid" >/dev/null 2>&1; then
        wait "$switch_pid" || true
        switched=0
        break
      fi
      sleep 0.1
    done
    if [[ "$switched" -ne 0 ]]; then
      kill "$switch_pid" >/dev/null 2>&1 || true
      wait "$switch_pid" 2>/dev/null || true
      echo "warning: installed app did not finish switch-away request; falling back to helper" >&2
    fi
  fi
  if [[ "$switched" -ne 0 ]]; then
    local tool
    tool="$(inputsource_tool_path)" || return 0
    "$tool" switch-away \
      --prefix "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
      --fallback-id "$KNOWTYPE_FALLBACK_INPUT_SOURCE_ID" >/dev/null 2>&1 || true
  fi
}

repair_preferences_best_effort() {
  local tool
  if ! tool="$(inputsource_tool_path)"; then
    echo "warning: input-source helper is unavailable; continuing so installed app activation and diagnostics can run" >&2
    return 0
  fi
  if ! "$tool" repair-preferences \
    --bundle-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
    --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" \
    --include-history \
    --add-active; then
    echo "warning: input-source preference repair failed; continuing so installed app activation and diagnostics can run" >&2
  fi
}

mkdir -p "$TARGET_DIR"
mkdir -p "$PREFPANE_TARGET_DIR"

switch_away_before_replace
sleep 0.2

killall KnowTypeInputMethodApp 2>/dev/null || true
for _ in {1..30}; do
  if ! pgrep -x KnowTypeInputMethodApp >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
if [[ -e "$TARGET_PATH" || -L "$TARGET_PATH" ]]; then
  knowtype_remove_local_inputmethod_bundle_if_safe "$TARGET_PATH" 0
fi
knowtype_cleanup_local_duplicate_bundles_except "" 0
cp -R "$BUNDLE_PATH" "$TARGET_PATH"
rm -rf "$BUNDLE_PATH"
rm -rf "$PREFPANE_TARGET_PATH"
cp -R "$PREFPANE_PATH" "$PREFPANE_TARGET_PATH"
rm -rf "$PREFPANE_PATH"

if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$TARGET_PATH" "$PREFPANE_TARGET_PATH" 2>/dev/null || true
fi

knowtype_unregister_launchservices_records_except "$TARGET_PATH" 0
knowtype_register_launchservices_path "$TARGET_PATH" 0

"$INSTALLED_EXECUTABLE" --knowtype-purge-legacy

repair_preferences_best_effort

if ! "$INSTALLED_EXECUTABLE" --knowtype-install-activate; then
  echo "warning: installed app could not select KnowType in this process context; continuing so diagnostics can report the persisted state" >&2
fi

repair_preferences_best_effort

sleep 0.75
killall cfprefsd 2>/dev/null || true
killall TextInputMenuAgent 2>/dev/null || true
killall TextInputSwitcher 2>/dev/null || true
sleep 0.5
open -g "$TARGET_PATH" >/dev/null 2>&1 || true
sleep 0.5

duplicate_count="$(knowtype_find_local_inputmethod_bundle_paths | knowtype_count_nonempty_lines)"
if [[ "$duplicate_count" =~ ^[0-9]+$ && "$duplicate_count" -gt 1 ]]; then
  echo "warning: found $duplicate_count local KnowType bundles after install:" >&2
  knowtype_find_local_inputmethod_bundle_paths | sed 's/^/  /' >&2
  echo "Run ./scripts/repair-inputmethod-selection.sh before testing selection." >&2
fi

echo "Installed KnowType to: $TARGET_PATH"
echo "Installed KnowType System Settings pane to: $PREFPANE_TARGET_PATH"
echo "Installed KnowType local build version: $LOCAL_BUILD_VERSION"
echo "Requested input source activation from installed app: $KNOWTYPE_ACTIVE_INPUT_MODE_ID"
echo "Run ./scripts/diagnose-inputmethod.sh --strict for the read-only install status check."
echo "Activate the target text app, run ./scripts/select-inputmethod.sh --require-selected, then type a real probe before manual acceptance."
echo "If System Settings asks to allow 知键/KnowType as an input method, click Allow before testing selection."
echo "If diagnostics show HIToolbox selected preference is still another source, choose KnowType from the active app's input menu/System Settings."
