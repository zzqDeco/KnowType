#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/inputsource-ids.sh"
source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"
DEFAULT_BUNDLE_PATH="$HOME/Library/Input Methods/KnowType.app"
BUNDLE_PATH="${KNOWTYPE_BUNDLE_PATH:-$DEFAULT_BUNDLE_PATH}"
RUN_DIAGNOSTIC=1
REQUIRE_SELECTED=0

usage() {
  cat <<'EOF'
Usage: scripts/select-inputmethod.sh [--require-selected] [--no-diagnose] [--path /path/to/KnowType.app]

Requests KnowType as the current macOS input source, then optionally runs the
read-only local input-method diagnostic.

Activate the target text app before running this helper. This is a selection
preflight only; final acceptance still requires typing a probe in that app.
macOS input source selection is scoped to text input context, so a helper or
diagnostic process cannot prove another app will use KnowType.

Options:
  --path              Installed KnowType.app path. Defaults to ~/Library/Input Methods/KnowType.app.
  --require-selected  Fail if KnowType is not selected in this preflight TIS context.
  --no-diagnose       Only send the selection request.
  --no-diagnostic     Alias for --no-diagnose.
  -h, --help          Show this help.
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
    --require-selected)
      REQUIRE_SELECTED=1
      shift
      ;;
    --no-diagnose|--no-diagnostic)
      RUN_DIAGNOSTIC=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -x "$BUNDLE_PATH/Contents/MacOS/KnowTypeInputMethodApp" ]]; then
  echo "error: installed KnowType executable is missing: $BUNDLE_PATH/Contents/MacOS/KnowTypeInputMethodApp" >&2
  echo "Run ./scripts/install-inputmethod.sh first." >&2
  exit 1
fi

INPUTSOURCE_TOOL="$(knowtype_inputsource_tool "$ROOT_DIR")"
bootstrap_args=(
  bootstrap
  --path "$BUNDLE_PATH"
  --parent-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID"
  --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID"
  --select
)
for legacy_mode_id in "${KNOWTYPE_LEGACY_INPUT_MODE_IDS[@]}"; do
  bootstrap_args+=(--legacy-mode-id "$legacy_mode_id")
done
if (( REQUIRE_SELECTED == 1 )); then
  bootstrap_args+=(--require-selected)
fi

if ! SELECT_OUTPUT="$("$INPUTSOURCE_TOOL" "${bootstrap_args[@]}" 2>&1)"; then
  printf '%s\n' "$SELECT_OUTPUT"
  exit 1
fi
printf '%s\n' "$SELECT_OUTPUT"

if (( REQUIRE_SELECTED == 1 )) && ! grep -qx "select.current=$KNOWTYPE_ACTIVE_INPUT_MODE_ID" <<<"$SELECT_OUTPUT"; then
  echo "error: input-source helper did not report KnowType as selected in its TIS context" >&2
  exit 1
fi

if (( RUN_DIAGNOSTIC == 1 )); then
  diagnostic_args=(--strict)
  echo
  echo "Running read-only install diagnostics. Input-source state below is the diagnostic process context, not target-app acceptance."
  "$ROOT_DIR/scripts/diagnose-inputmethod.sh" "${diagnostic_args[@]}" --path "$BUNDLE_PATH"
fi
