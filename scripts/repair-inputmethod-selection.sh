#!/usr/bin/env bash
set -euo pipefail

DEFAULT_BUNDLE_PATH="$HOME/Library/Input Methods/KnowType.app"
BUNDLE_PATH="${KNOWTYPE_BUNDLE_PATH:-$DEFAULT_BUNDLE_PATH}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"

PARENT_ID="com.knowtype.inputmethod.KnowType"
MODE_ID="com.knowtype.inputmethod.KnowType.Mode"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

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

usage() {
  cat <<'EOF'
Usage: scripts/repair-inputmethod-selection.sh [--path /path/to/KnowType.app]

Repairs local Text Input Source selection state for development installs.

The script keeps the installed KnowType bundle in ~/Library/Input Methods,
unregisters stale LaunchServices records for older KnowType build paths,
deduplicates KnowType entries in Text Input Source preferences, restarts the
Text Input menu agents, relaunches the installed input method app, and prints a
fresh diagnostic summary.

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

canonical_installed_bundle_path="$(canonical_bundle_path "$BUNDLE_PATH")"
backup_dir="$HOME/Library/Application Support/KnowType"
timestamp="$(date +%Y%m%d%H%M%S)"
mkdir -p "$backup_dir"

for plist in "$HOME/Library/Preferences/com.apple.HIToolbox.plist" "$HOME/Library/Preferences/com.apple.inputsources.plist"; do
  if [[ -f "$plist" ]]; then
    cp "$plist" "$backup_dir/$(basename "$plist" .plist)-before-selection-repair-$timestamp.plist"
  fi
done

if [[ -x "$LSREGISTER" ]]; then
  stale_paths="$(
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
    '
  )"

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    canonical_path="$(canonical_bundle_path "$path")"
    if [[ "$canonical_path" != "$canonical_installed_bundle_path" ]]; then
      unregister_path="$(expand_home_path "$(strip_lsregister_suffix "$path")")"
      "$LSREGISTER" -u "$unregister_path" 2>/dev/null || true
      echo "Unregistered stale LaunchServices record: $unregister_path"
    fi
  done <<<"$stale_paths"

  "$LSREGISTER" -f "$BUNDLE_PATH" 2>/dev/null || true
fi

INPUTSOURCE_TOOL="$(knowtype_inputsource_tool "$ROOT_DIR")"
"$INPUTSOURCE_TOOL" dedupe-preferences --bundle-id "$PARENT_ID" --mode-id "$MODE_ID"

killall cfprefsd 2>/dev/null || true
killall TextInputMenuAgent 2>/dev/null || true
killall TextInputSwitcher 2>/dev/null || true
killall KnowTypeInputMethodApp 2>/dev/null || true
sleep 1

open -n "$BUNDLE_PATH" --args --knowtype-install-activate >/dev/null 2>&1 || true
sleep 1.5

echo
echo "Selection repair finished for: $BUNDLE_PATH"
echo "Backups are in: $backup_dir"
echo
"$ROOT_DIR/scripts/diagnose-inputmethod.sh" --strict --path "$BUNDLE_PATH"
