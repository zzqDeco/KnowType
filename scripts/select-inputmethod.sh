#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIAGNOSTIC=1
REQUIRE_SELECTED=0

usage() {
  cat <<'EOF'
Usage: scripts/select-inputmethod.sh [--require-selected] [--no-diagnose]

Requests KnowType as the current macOS input source, then optionally runs the
read-only local input-method diagnostic.

Options:
  --require-selected  Make the follow-up diagnostic fail if KnowType is not selected.
  --no-diagnose       Only send the selection request.
  -h, --help          Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
    --require-selected)
      REQUIRE_SELECTED=1
      shift
      ;;
    --no-diagnose)
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

swift - <<'SWIFT'
import Carbon
import Foundation

let parentID = "com.knowtype.inputmethod.KnowType"
let modeID = "com.knowtype.inputmethod.KnowType.Mode"

func inputSource(id: String) -> TISInputSource? {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
    return sources?.first
}

func enableInputSource(_ source: TISInputSource, label: String) {
    let status = TISEnableInputSource(source)
    if status != noErr {
        fputs("Warning: TISEnableInputSource(\(label)) returned \(status)\n", stderr)
    }
}

if let parent = inputSource(id: parentID) {
    enableInputSource(parent, label: "parent")
}

guard let mode = inputSource(id: modeID) else {
    fputs("KnowType input mode was not found. Run ./scripts/install-inputmethod.sh first.\n", stderr)
    exit(1)
}

enableInputSource(mode, label: "mode")

let selectStatus = TISSelectInputSource(mode)
if selectStatus == noErr {
    print("Requested KnowType input source selection: \(modeID)")
} else {
    fputs("TISSelectInputSource(mode) returned \(selectStatus). Enable or select KnowType from System Settings if macOS did not switch automatically.\n", stderr)
    exit(Int32(selectStatus))
}
SWIFT

if (( RUN_DIAGNOSTIC == 1 )); then
  diagnostic_args=(--strict)
  if (( REQUIRE_SELECTED == 1 )); then
    diagnostic_args+=(--require-selected)
  fi
  "$ROOT_DIR/scripts/diagnose-inputmethod.sh" "${diagnostic_args[@]}"
fi
