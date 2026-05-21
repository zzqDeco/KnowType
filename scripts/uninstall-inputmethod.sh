#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"
source "$ROOT_DIR/scripts/lib/inputmethod-installation.sh"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: scripts/uninstall-inputmethod.sh [--dry-run]

Removes all local KnowType input method bundles from ~/Library/Input Methods
and removes the optional compatibility KnowType PreferencePane when installed.

Options:
  --dry-run   Print removal actions without changing files or preferences.
  -h, --help  Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
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

PREFPANE_TARGET_PATH="$(knowtype_preferencepane_target_path)"

if (( DRY_RUN == 0 )); then
  INPUTSOURCE_TOOL="$(knowtype_inputsource_tool "$ROOT_DIR")"
  "$INPUTSOURCE_TOOL" switch-away \
    --prefix "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
    --fallback-id "$KNOWTYPE_FALLBACK_INPUT_SOURCE_ID" >/dev/null 2>&1 || true
  killall KnowTypeInputMethodApp 2>/dev/null || true
fi

bundle_count=0
while IFS= read -r bundle_path; do
  [[ -n "$bundle_path" ]] || continue
  bundle_count=$((bundle_count + 1))
  knowtype_unregister_launchservices_path "$bundle_path" "$DRY_RUN"
  knowtype_remove_local_inputmethod_bundle_if_safe "$bundle_path" "$DRY_RUN"
done < <(knowtype_find_local_inputmethod_bundle_paths)

knowtype_unregister_launchservices_records_except "" "$DRY_RUN"

if [[ -d "$PREFPANE_TARGET_PATH" ]]; then
  if (( DRY_RUN == 1 )); then
    echo "[dry-run] Would remove KnowType compatibility PreferencePane: $PREFPANE_TARGET_PATH"
  else
    rm -rf -- "$PREFPANE_TARGET_PATH"
    echo "Removed KnowType compatibility PreferencePane: $PREFPANE_TARGET_PATH"
  fi
fi

if (( DRY_RUN == 0 )); then
  INPUTSOURCE_TOOL="$(knowtype_inputsource_tool "$ROOT_DIR")"
  "$INPUTSOURCE_TOOL" repair-preferences \
    --bundle-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
    --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" \
    --include-history >/dev/null 2>&1 || true
fi

if (( bundle_count == 0 )); then
  echo "No local KnowType input method bundles were found."
elif (( DRY_RUN == 1 )); then
  echo "Would remove $bundle_count local KnowType input method bundle(s)."
else
  echo "Removed $bundle_count local KnowType input method bundle(s)."
fi
