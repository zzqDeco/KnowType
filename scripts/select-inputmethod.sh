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

Activate the target text app before running this helper. This is a selection
preflight only; final acceptance still requires typing a probe in that app.
macOS input source selection is scoped to text input context, so a helper or
diagnostic process cannot prove another app will use KnowType.

Options:
  --require-selected  Fail if KnowType is not selected in this preflight TIS context.
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

KNOWTYPE_REQUIRE_SELECTED="$REQUIRE_SELECTED" swift - <<'SWIFT'
import Carbon
import Foundation

let parentID = "com.knowtype.inputmethod.KnowType"
let modeID = "com.knowtype.inputmethod.KnowType.Mode"
let requireSelected = ProcessInfo.processInfo.environment["KNOWTYPE_REQUIRE_SELECTED"] == "1"

func inputSource(id: String) -> TISInputSource? {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
    return sources?.first
}

func inputSourceID(_ source: TISInputSource?) -> String? {
    guard let source,
          let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
        return nil
    }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
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

let deadline = Date().addingTimeInterval(2.0)
var currentID = inputSourceID(TISCopyCurrentKeyboardInputSource()?.takeRetainedValue())
while currentID != modeID && Date() < deadline {
    Thread.sleep(forTimeInterval: 0.1)
    currentID = inputSourceID(TISCopyCurrentKeyboardInputSource()?.takeRetainedValue())
}

if currentID == modeID {
    print("Verified KnowType in this preflight TIS context: \(modeID)")
    print("Type a real probe in the target app before accepting manual typing.")
} else {
    let observed = currentID ?? "<unavailable>"
    fputs("Warning: this preflight TIS context is \(observed), not \(modeID). Activate the target text app, rerun this helper, then type a real probe in that app.\n", stderr)
    if requireSelected {
        exit(1)
    }
}
SWIFT

if (( RUN_DIAGNOSTIC == 1 )); then
  diagnostic_args=(--strict)
  echo
  echo "Running read-only install diagnostics. Input-source state below is the diagnostic process context, not target-app acceptance."
  "$ROOT_DIR/scripts/diagnose-inputmethod.sh" "${diagnostic_args[@]}"
fi
