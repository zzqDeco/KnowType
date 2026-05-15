#!/usr/bin/env bash
set -u -o pipefail

DEFAULT_BUNDLE_PATH="$HOME/Library/Input Methods/KnowType.app"
BUNDLE_PATH="${KNOWTYPE_BUNDLE_PATH:-$DEFAULT_BUNDLE_PATH}"
STRICT=0
REQUIRE_SELECTED=0

usage() {
  cat <<'EOF'
Usage: scripts/diagnose-inputmethod.sh [--strict] [--require-selected] [--path /path/to/KnowType.app]

Checks the local KnowType input-method installation without changing system state.

Options:
  --strict            Exit non-zero when critical install, signing, registration, or enabled-state checks fail.
  --require-selected  Treat a non-KnowType current input source as a failure.
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
  PARENT_ID="$PARENT_ID" MODE_ID="$MODE_ID" swift - 2>/dev/null <<'SWIFT' || true
import Carbon
import Foundation

let parentID = ProcessInfo.processInfo.environment["PARENT_ID"]!
let modeID = ProcessInfo.processInfo.environment["MODE_ID"]!

func stringProperty(_ source: TISInputSource?, _ key: CFString) -> String? {
    guard let source, let raw = TISGetInputSourceProperty(source, key) else {
        return nil
    }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
}

func boolProperty(_ source: TISInputSource?, _ key: CFString) -> Bool {
    guard let source, let raw = TISGetInputSourceProperty(source, key) else {
        return false
    }
    return CFBooleanGetValue(unsafeBitCast(raw, to: CFBoolean.self))
}

func source(id: String) -> TISInputSource? {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
    return sources?.first
}

let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
let currentID = stringProperty(current, kTISPropertyInputSourceID) ?? ""
let parent = source(id: parentID)
let mode = source(id: modeID)

print("current.id=\(currentID)")
print("parent.found=\(parent != nil)")
print("parent.enabled=\(boolProperty(parent, kTISPropertyInputSourceIsEnabled))")
print("mode.found=\(mode != nil)")
print("mode.enabled=\(boolProperty(mode, kTISPropertyInputSourceIsEnabled))")
print("mode.selected=\(currentID == modeID)")
SWIFT
)"

if [[ -z "$TIS_OUTPUT" ]]; then
  warn "could not query Text Input Source state"
else
  while IFS='=' read -r key value; do
    case "$key" in
      current.id)
        if [[ -n "$value" ]]; then
          info "current input source: $value"
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
          ok "KnowType input mode is selected"
        elif (( REQUIRE_SELECTED == 1 )); then
          fail "KnowType input mode is not currently selected"
        else
          warn "KnowType input mode is not currently selected"
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
