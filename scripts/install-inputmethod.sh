#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/inputsource-ids.sh"
source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"

usage() {
  cat <<'EOF'
Usage: scripts/install-inputmethod.sh

Builds and installs KnowType.app into ~/Library/Input Methods, installs
KnowType.prefPane into ~/Library/PreferencePanes, then asks the installed app
to register and enable the input source.

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

LOCAL_BUILD_VERSION="${KNOWTYPE_BUNDLE_BUILD_VERSION:-$(date +%Y%m%d%H%M%S)}"
BUNDLE_PATH="$(KNOWTYPE_BUNDLE_BUILD_VERSION="$LOCAL_BUILD_VERSION" "$ROOT_DIR/scripts/build-inputmethod-bundle.sh" | tail -n 1)"
PREFPANE_PATH="$("$ROOT_DIR/scripts/build-preference-pane.sh" | tail -n 1)"
TARGET_DIR="$HOME/Library/Input Methods"
TARGET_PATH="$TARGET_DIR/KnowType.app"
PREFPANE_TARGET_DIR="$HOME/Library/PreferencePanes"
PREFPANE_TARGET_PATH="$PREFPANE_TARGET_DIR/KnowType.prefPane"
INSTALLED_EXECUTABLE="$TARGET_PATH/Contents/MacOS/KnowTypeInputMethodApp"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

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
rm -rf "$TARGET_PATH"
cp -R "$BUNDLE_PATH" "$TARGET_PATH"
rm -rf "$BUNDLE_PATH"
rm -rf "$PREFPANE_TARGET_PATH"
cp -R "$PREFPANE_PATH" "$PREFPANE_TARGET_PATH"
rm -rf "$PREFPANE_PATH"

if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$TARGET_PATH" "$PREFPANE_TARGET_PATH" 2>/dev/null || true
fi

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$TARGET_PATH" >/dev/null 2>&1 || true
fi

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

echo "Installed KnowType to: $TARGET_PATH"
echo "Installed KnowType System Settings pane to: $PREFPANE_TARGET_PATH"
echo "Installed KnowType local build version: $LOCAL_BUILD_VERSION"
echo "Requested input source activation from installed app: $KNOWTYPE_ACTIVE_INPUT_MODE_ID"
echo "Run ./scripts/diagnose-inputmethod.sh --strict for the read-only install status check."
echo "Activate the target text app, run ./scripts/select-inputmethod.sh --require-selected, then type a real probe before manual acceptance."
echo "If System Settings asks to allow 知键/KnowType as an input method, click Allow before testing selection."
echo "If diagnostics show HIToolbox selected preference is still another source, choose KnowType from the active app's input menu/System Settings."
