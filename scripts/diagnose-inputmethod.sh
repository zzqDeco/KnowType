#!/usr/bin/env bash
set -u -o pipefail

DEFAULT_BUNDLE_PATH="$HOME/Library/Input Methods/KnowType.app"
BUNDLE_PATH="${KNOWTYPE_BUNDLE_PATH:-$DEFAULT_BUNDLE_PATH}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"
STRICT=0
REQUIRE_SELECTED=0
SHOW_LOGS=0
LOG_LOOKBACK="${KNOWTYPE_LOG_LOOKBACK:-30m}"

usage() {
  cat <<'EOF'
Usage: scripts/diagnose-inputmethod.sh [--strict] [--require-selected] [--path /path/to/KnowType.app]

Checks the local KnowType input-method installation without changing system state.

Options:
  --strict            Exit non-zero when critical install, signing, registration, or enabled-state checks fail.
  --require-selected  Treat this diagnostic process's current input source as a failure when it is not KnowType.
                      Manual acceptance still requires typing a probe in the target app.
  --logs              Include recent KnowType, Gatekeeper, and input-source sandbox log hints.
  --log-lookback      Time window for --logs, such as 10m, 1h, or 2h. Defaults to 30m.
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
    --logs)
      SHOW_LOGS=1
      shift
      ;;
    --log-lookback)
      if (($# < 2)); then
        echo "error: --log-lookback requires a value" >&2
        exit 2
      fi
      LOG_LOOKBACK="$2"
      shift 2
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
gatekeeper_rejected=0
hitoolbox_enabled_knowtype=""
hitoolbox_selected_knowtype=""

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

strip_lsregister_suffix() {
  local value="$1"
  value="${value% (0x*)}"
  printf '%s' "$value"
}

expand_home_path() {
  local path="$1"
  case "$path" in
    "~")
      printf '%s' "$HOME"
      ;;
    "~/"*)
      printf '%s/%s' "$HOME" "${path#~/}"
      ;;
    *)
      printf '%s' "$path"
      ;;
  esac
}

canonical_bundle_path() {
  local path="$1"
  path="$(expand_home_path "$(strip_lsregister_suffix "$path")")"
  if [[ -e "$path" ]]; then
    printf '%s/%s' "$(cd "$(dirname "$path")" && pwd -P)" "$(basename "$path")"
  else
    printf '%s' "$path"
  fi
}

plist_value() {
  local key="$1"
  local plist="$2"
  local output
  if output="$(/usr/bin/plutil -extract "$key" raw -o - "$plist" 2>/dev/null)"; then
    printf '%s' "$output"
  fi
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
  expect_plist_value "InputMethodConnectionName" "com.knowtype.inputmethod.KnowType_Connection" "$INFO_PLIST"
  expect_plist_value "InputMethodServerControllerClass" "KnowTypeInputController" "$INFO_PLIST"
  expect_plist_value "InputMethodServerDelegateClass" "KnowTypeInputController" "$INFO_PLIST"
  expect_plist_value "LSBackgroundOnly" "false" "$INFO_PLIST"
  expect_plist_value "LSUIElement" "true" "$INFO_PLIST"
  expect_plist_value "LSHasLocalizedDisplayName" "true" "$INFO_PLIST"
  if [[ -n "$(plist_value "TISIconIsTemplate" "$INFO_PLIST")" ]]; then
    warn "Info.plist contains private/undocumented TISIconIsTemplate; rebuild from current sources"
  fi
else
  fail "Info.plist is missing"
fi

if [[ -d "$BUNDLE_PATH" ]]; then
  LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [[ -x "$LSREGISTER" ]]; then
    CANONICAL_BUNDLE_PATH="$(canonical_bundle_path "$BUNDLE_PATH")"
    STALE_LS_PATHS="$(
      "$LSREGISTER" -dump 2>/dev/null | awk -v id="$PARENT_ID" '
        /^bundle id:/ {
          path = ""
          matched = 0
        }
        /^[[:space:]]*path:/ {
          sub(/^[^:]*:[[:space:]]*/, "")
          path = $0
        }
        /^[[:space:]]*identifier:/ {
          value = $0
          sub(/^[^:]*:[[:space:]]*/, "", value)
          sub(/[[:space:]]*\(0x[[:xdigit:]]+\)$/, "", value)
          if (value == id) {
            matched = 1
          }
        }
        matched == 1 && path != "" {
          print path
          matched = 0
        }
      ' | while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        canonical_path="$(canonical_bundle_path "$path")"
        if [[ "$canonical_path" != "$CANONICAL_BUNDLE_PATH" ]]; then
          printf '%s\n' "$path"
        fi
      done
    )"
    if [[ -z "$STALE_LS_PATHS" ]]; then
      ok "LaunchServices has no stale KnowType bundle records"
    else
      fail "LaunchServices has stale KnowType bundle records outside the installed path; run ./scripts/repair-inputmethod-selection.sh"
      while IFS= read -r path; do
        [[ -n "$path" ]] && info "stale LaunchServices path: $path"
      done <<<"$STALE_LS_PATHS"
    fi
  else
    warn "lsregister command is unavailable; cannot check stale LaunchServices records"
  fi
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

if command -v spctl >/dev/null 2>&1; then
  SPCTL_OUTPUT="$(spctl --assess --type execute --verbose=4 "$BUNDLE_PATH" 2>&1)"
  SPCTL_STATUS=$?
  if (( SPCTL_STATUS == 0 )); then
    ok "Gatekeeper assessment accepts the installed bundle"
  else
    gatekeeper_rejected=1
    warn "Gatekeeper assessment rejects this local build: $SPCTL_OUTPUT"
    info "macOS 15 no longer supports spctl --add; for local Apple Development testing, generate a SystemPolicyRule profile with ./scripts/create-local-system-policy-profile.sh --open"
    info "Run this diagnostic with --logs to check for syspolicy GatekeeperPolicyScanError details"
  fi
else
  warn "spctl command is unavailable"
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
      parent.selectCapable)
        if [[ "$value" != "true" ]]; then
          info "KnowType parent record is not directly selectable; macOS should select the visible input mode instead"
        fi
        ;;
      parent.type)
        [[ -n "$value" ]] && info "KnowType parent TIS type: $value"
        ;;
      mode.found)
        [[ "$value" == "true" ]] && ok "KnowType input mode is registered" || fail "KnowType input mode is not registered"
        ;;
      mode.enabled)
        [[ "$value" == "true" ]] && ok "KnowType input mode is enabled" || fail "KnowType input mode is not enabled"
        ;;
      mode.selectCapable)
        [[ "$value" == "true" ]] && ok "KnowType input mode is select-capable" || fail "KnowType input mode is not select-capable"
        ;;
      mode.type)
        [[ -n "$value" ]] && info "KnowType mode TIS type: $value"
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
        hitoolbox_selected_knowtype="$value"
        if [[ "$value" == "true" ]]; then
          ok "HIToolbox selected preference is KnowType"
        else
          warn "HIToolbox selected preference is not KnowType; choose KnowType from the input menu/System Settings before typing"
          info "If macOS shows an authorization prompt to allow 知键/KnowType as an input method, click Allow; until it is allowed, the menu can list KnowType while normal switching still falls back to another source"
        fi
        ;;
      preference.enabled.knowtype)
        hitoolbox_enabled_knowtype="$value"
        if [[ "$value" == "true" ]]; then
          ok "HIToolbox enabled preferences include KnowType"
        else
          fail "HIToolbox enabled preferences do not include KnowType; enable KnowType in System Settings > Keyboard > Input Sources"
        fi
        ;;
    esac
  done <<<"$TIS_OUTPUT"
fi

if (( gatekeeper_rejected == 1 )) &&
   [[ "$hitoolbox_enabled_knowtype" == "true" ]] &&
   [[ "$hitoolbox_selected_knowtype" != "true" ]]; then
  warn "KnowType is enabled but not selected while Gatekeeper rejects the bundle; local Apple Development builds may need explicit user allowance or a Developer ID build before the input menu can select them reliably"
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

if (( SHOW_LOGS == 1 )); then
  echo
  echo "Recent system log hints"
  if command -v /usr/bin/log >/dev/null 2>&1; then
    LOG_PREDICATE='subsystem == "com.knowtype.inputmethod.KnowType" OR eventMessage CONTAINS[c] "GatekeeperPolicyScanError" OR eventMessage CONTAINS[c] "user-preference-write com.apple.inputsources"'
    if LOG_OUTPUT="$(/usr/bin/log show --style compact --last "$LOG_LOOKBACK" --predicate "$LOG_PREDICATE" 2>/dev/null | tail -80)"; then
      if [[ -n "$LOG_OUTPUT" ]]; then
        printf '%s\n' "$LOG_OUTPUT"
      else
        info "No recent KnowType, Gatekeeper, or input-source sandbox log hints found in the last $LOG_LOOKBACK"
      fi
    else
      warn "could not read unified logs for the last $LOG_LOOKBACK"
    fi
  else
    warn "log command is unavailable"
  fi
fi

echo
echo "Summary: $failures failure(s), $warnings warning(s)"

if (( failures > 0 && (STRICT == 1 || REQUIRE_SELECTED == 1) )); then
  exit 1
fi
