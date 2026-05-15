#!/usr/bin/env bash
set -u -o pipefail

DEFAULT_BUNDLE_PATH="$HOME/Library/Input Methods/KnowType.app"
BUNDLE_PATH="${KNOWTYPE_BUNDLE_PATH:-$DEFAULT_BUNDLE_PATH}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"
STRICT=0
REQUIRE_SELECTED=0

usage() {
  cat <<'EOF'
Usage: scripts/diagnose-inputmethod.sh [--strict] [--require-selected] [--path /path/to/KnowType.app]

Checks the local KnowType input-method installation without changing system state.

Options:
  --strict            Exit non-zero when critical install, signing, registration, or enabled-state checks fail.
  --require-selected  Treat this diagnostic process's current input source as a failure when it is not KnowType.
                      Manual acceptance still requires typing a probe in the target app.
  --path              Inspect a specific KnowType.app bundle path.
  -h, --help          Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
    --strict)
      STRICT=1
      shift
      ;;
    --require-selected)
      REQUIRE_SELECTED=1
      shift
      ;;
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

failures=0
warnings=0

ok() {
  printf '[ok] %s\n' "$1"
}

warn() {
  warnings=$((warnings + 1))
  printf '[warn] %s\n' "$1"
}

fail() {
  failures=$((failures + 1))
  printf '[fail] %s\n' "$1"
}

info() {
  printf '[info] %s\n' "$1"
}

plist_value() {
  local key="$1"
  local plist="$2"
  /usr/bin/plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true
}

expect_plist_value() {
  local key="$1"
  local expected="$2"
  local plist="$3"
  local actual
  actual="$(plist_value "$key" "$plist")"
  if [[ "$actual" == "$expected" ]]; then
    ok "Info.plist $key = $expected"
  else
    fail "Info.plist $key expected '$expected' but found '${actual:-<missing>}'"
  fi
}

echo "KnowType input-method diagnostics"
echo "Bundle: $BUNDLE_PATH"
echo

if [[ -d "$BUNDLE_PATH" ]]; then
  ok "bundle directory exists"
else
  fail "bundle directory is missing; run ./scripts/install-inputmethod.sh"
fi

INFO_PLIST="$BUNDLE_PATH/Contents/Info.plist"
EXECUTABLE="$BUNDLE_PATH/Contents/MacOS/KnowTypeInputMethodApp"
CORE_RESOURCE_BUNDLE="$BUNDLE_PATH/Contents/Resources/KnowType_KnowTypeCore.bundle"
ICON_RESOURCE="$BUNDLE_PATH/Contents/Resources/KnowTypeInputMethodIcon.tiff"
PARENT_ID="com.knowtype.inputmethod.KnowType"
MODE_ID="com.knowtype.inputmethod.KnowType.Mode"

if [[ -f "$INFO_PLIST" ]]; then
  ok "Info.plist exists"
  expect_plist_value "CFBundleIdentifier" "$PARENT_ID" "$INFO_PLIST"
  expect_plist_value "CFBundleExecutable" "KnowTypeInputMethodApp" "$INFO_PLIST"
  expect_plist_value "TISInputSourceID" "$PARENT_ID" "$INFO_PLIST"
  expect_plist_value "InputMethodServerControllerClass" "KnowTypeInputController" "$INFO_PLIST"
  expect_plist_value "InputMethodServerDelegateClass" "KnowTypeInputController" "$INFO_PLIST"
else
  fail "Info.plist is missing"
fi

if [[ -x "$EXECUTABLE" ]]; then
  ok "input-method executable exists and is executable"
else
  fail "input-method executable is missing or not executable"
fi

if [[ -d "$CORE_RESOURCE_BUNDLE" ]]; then
  ok "SwiftPM core resource bundle is packaged"
else
  fail "SwiftPM core resource bundle is missing; bundled lexicon may not load"
fi

if [[ -f "$ICON_RESOURCE" ]]; then
  ok "input-source icon resource is packaged"
else
  warn "input-source icon resource is missing"
fi

if command -v codesign >/dev/null 2>&1; then
  if codesign --verify --deep --strict "$BUNDLE_PATH" >/dev/null 2>&1; then
    ok "codesign verification passes"
  else
    fail "codesign verification failed"
  fi
  CODESIGN_SUMMARY="$(codesign -dv "$BUNDLE_PATH" 2>&1 | awk '/^(Identifier|Authority|TeamIdentifier)=/ {print}' | paste -sd ', ' -)"
  if [[ -n "$CODESIGN_SUMMARY" ]]; then
    info "codesign: $CODESIGN_SUMMARY"
  fi
else
  warn "codesign command is unavailable"
fi

echo
echo "Text Input Source state"

TIS_OUTPUT="$(
  INPUTSOURCE_TOOL="$(knowtype_inputsource_tool "$ROOT_DIR")"
  "$INPUTSOURCE_TOOL" status --parent-id "$PARENT_ID" --mode-id "$MODE_ID"
)"

if [[ -z "$TIS_OUTPUT" ]]; then
  if (( REQUIRE_SELECTED == 1 )); then
    fail "could not query Text Input Source state"
  else
    warn "could not query Text Input Source state"
  fi
else
  while IFS='=' read -r key value; do
    case "$key" in
      current.id)
        if [[ -n "$value" ]]; then
          info "current input source in this diagnostic context: $value"
        else
          warn "current input source id is unavailable"
        fi
        ;;
      parent.found)
        [[ "$value" == "true" ]] && ok "KnowType parent input source is registered" || fail "KnowType parent input source is not registered"
        ;;
      parent.enabled)
        [[ "$value" == "true" ]] && ok "KnowType parent input source is enabled" || fail "KnowType parent input source is not enabled"
        ;;
      mode.found)
        [[ "$value" == "true" ]] && ok "KnowType input mode is registered" || fail "KnowType input mode is not registered"
        ;;
      mode.enabled)
        [[ "$value" == "true" ]] && ok "KnowType input mode is enabled" || fail "KnowType input mode is not enabled"
        ;;
      mode.selected)
        if [[ "$value" == "true" ]]; then
          ok "KnowType input mode is selected in this diagnostic context"
        elif (( REQUIRE_SELECTED == 1 )); then
          fail "KnowType input mode is not selected in this diagnostic context; select KnowType from the target app's input menu and type a real probe"
        else
          warn "KnowType input mode is not selected in this diagnostic context"
        fi
        ;;
      mode.name)
        if [[ -z "$value" ]]; then
          warn "KnowType input mode localized name is unavailable"
        elif [[ "$value" == "$MODE_ID" ]]; then
          warn "KnowType input mode localized name is unresolved; reinstall after packaging InfoPlist.strings"
        else
          ok "KnowType input mode localized name = $value"
        fi
        ;;
      mode.count)
        if [[ "$value" =~ ^[0-9]+$ && "$value" -gt 1 ]]; then
          warn "TIS reports $value KnowType input mode registrations; log out or reboot if the input menu shows stale duplicates"
        fi
        ;;
      preference.selected.mode)
        if [[ -n "$value" ]]; then
          info "HIToolbox selected input-mode preference: $value"
        else
          warn "HIToolbox selected input-mode preference is unavailable"
        fi
        ;;
      preference.selected.knowtype)
        if [[ "$value" == "true" ]]; then
          ok "HIToolbox selected preference is KnowType"
        else
          warn "HIToolbox selected preference is not KnowType; choose KnowType from the input menu/System Settings before typing"
        fi
        ;;
      preference.enabled.knowtype)
        if [[ "$value" == "true" ]]; then
          ok "HIToolbox enabled preferences include KnowType"
        else
          fail "HIToolbox enabled preferences do not include KnowType; enable KnowType in System Settings > Keyboard > Input Sources"
        fi
        ;;
    esac
  done <<<"$TIS_OUTPUT"
fi

if pgrep -x KnowTypeInputMethodApp >/dev/null 2>&1; then
  ok "KnowTypeInputMethodApp process is running"
else
  warn "KnowTypeInputMethodApp process is not running; it may start after selecting/using the input source"
fi

echo
echo "KnowType user data paths"

APP_SUPPORT="$HOME/Library/Application Support/KnowType"
PROVIDER_JSON="$APP_SUPPORT/providers.json"
HISTORY_JSON="$APP_SUPPORT/user-selection-history.json"
LEXICON_DIR="$APP_SUPPORT/Lexicons"

if [[ -f "$PROVIDER_JSON" ]]; then
  ok "provider profile file exists: $PROVIDER_JSON"
else
  warn "provider profile file is missing; runtime will use seeded local defaults"
fi

if [[ -f "$HISTORY_JSON" ]]; then
  ok "local candidate history file exists"
else
  info "local candidate history file has not been created yet"
fi

if [[ -d "$LEXICON_DIR" ]]; then
  LEXICON_COUNT="$(find "$LEXICON_DIR" -maxdepth 1 -type f \( -name '*.json' -o -name '*.tsv' \) | wc -l | tr -d ' ')"
  ok "local lexicon directory exists with $LEXICON_COUNT JSON/TSV resource(s)"
else
  warn "local lexicon directory is missing; bundled seed lexicon will be used"
fi

echo
echo "Summary: $failures failure(s), $warnings warning(s)"

if (( failures > 0 && (STRICT == 1 || REQUIRE_SELECTED == 1) )); then
  exit 1
fi
