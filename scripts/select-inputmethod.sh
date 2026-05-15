#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"
RUN_DIAGNOSTIC=1
REQUIRE_SELECTED=0

usage() {
  cat <<'EOF'
Usage: scripts/select-inputmethod.sh [--require-selected] [--no-diagnose]

Requests KnowType as the current macOS input source, then optionally runs the
read-only local input-method diagnostic.

Activate the target text app before running this helper. This is a selection
preflight only; final acceptance still requires typing a probe in that app.
macOS input source selection is scoped to text input context, so a helper or
diagnostic process cannot prove another app will use KnowType.

Options:
  --require-selected  Fail if KnowType is not selected in this preflight TIS context.
  --no-diagnose       Only send the selection request.
  --no-diagnostic     Alias for --no-diagnose.
  -h, --help          Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
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

INPUTSOURCE_TOOL="$(knowtype_inputsource_tool "$ROOT_DIR")"
select_args=(select)
if (( REQUIRE_SELECTED == 1 )); then
  select_args+=(--require-selected)
fi
"$INPUTSOURCE_TOOL" "${select_args[@]}"

if (( RUN_DIAGNOSTIC == 1 )); then
  diagnostic_args=(--strict)
  echo
  echo "Running read-only install diagnostics. Input-source state below is the diagnostic process context, not target-app acceptance."
  "$ROOT_DIR/scripts/diagnose-inputmethod.sh" "${diagnostic_args[@]}"
fi
