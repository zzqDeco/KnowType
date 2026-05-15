#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_PATH="$("$ROOT_DIR/scripts/build-inputmethod-bundle.sh" | tail -n 1)"
TARGET_DIR="$HOME/Library/Input Methods"
TARGET_PATH="$TARGET_DIR/KnowType.app"

mkdir -p "$TARGET_DIR"

swift - <<'SWIFT' >/dev/null 2>&1 || true
import Carbon

let knowTypePrefix = "com.knowtype.inputmethod.KnowType"
let fallbackID = "com.apple.keylayout.ABC"

func property(_ source: TISInputSource?, _ key: CFString) -> String? {
    guard let source, let raw = TISGetInputSourceProperty(source, key) else {
        return nil
    }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
}

func selectSource(id: String) {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
    if let source = sources?.first {
        TISSelectInputSource(source)
    }
}

let currentID = property(TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(), kTISPropertyInputSourceID)
if currentID?.hasPrefix(knowTypePrefix) == true {
    selectSource(id: fallbackID)
}
SWIFT

killall KnowTypeInputMethodApp 2>/dev/null || true
rm -rf "$TARGET_PATH"
cp -R "$BUNDLE_PATH" "$TARGET_PATH"
rm -rf "$BUNDLE_PATH"

open "$TARGET_PATH" >/dev/null 2>&1 || true
sleep 0.25

TARGET_PATH="$TARGET_PATH" swift - <<'SWIFT'
import Carbon
import Foundation

let targetPath = ProcessInfo.processInfo.environment["TARGET_PATH"]!
let targetURL = URL(fileURLWithPath: targetPath) as CFURL
let parentID = "com.knowtype.inputmethod.KnowType"
let modeID = "com.knowtype.inputmethod.KnowType.Mode"

@discardableResult
func registerInputSource() -> OSStatus {
    TISRegisterInputSource(targetURL)
}

func inputSource(id: String) -> TISInputSource? {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
    return sources?.first
}

func isEnabled(_ source: TISInputSource) -> Bool {
    guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else {
        return false
    }
    return CFBooleanGetValue(unsafeBitCast(raw, to: CFBoolean.self))
}

let registerStatus = registerInputSource()
if registerStatus != noErr {
    fputs("Warning: TISRegisterInputSource returned \\(registerStatus)\\n", stderr)
}

if let parent = inputSource(id: parentID) {
    let enableStatus = TISEnableInputSource(parent)
    if enableStatus != noErr {
        fputs("Warning: TISEnableInputSource(parent) returned \\(enableStatus)\\n", stderr)
    }
}

for _ in 0..<20 {
    if let parent = inputSource(id: parentID), isEnabled(parent) {
        break
    }
    Thread.sleep(forTimeInterval: 0.25)
}

if let mode = inputSource(id: modeID) {
    let enableStatus = TISEnableInputSource(mode)
    if enableStatus != noErr {
        fputs("Warning: TISEnableInputSource(mode) returned \\(enableStatus)\\n", stderr)
    }
    let selectStatus = TISSelectInputSource(mode)
    if selectStatus == noErr {
        print("Requested KnowType input source selection: \(modeID)")
    } else {
        fputs("Warning: TISSelectInputSource(mode) returned \\(selectStatus). Enable or select KnowType from System Settings if macOS did not switch automatically.\\n", stderr)
    }
} else {
    fputs("Warning: KnowType input mode was not found after registration.\\n", stderr)
}
SWIFT

echo "Installed KnowType to: $TARGET_PATH"
echo "Run ./scripts/diagnose-inputmethod.sh --strict for the read-only install status check."
echo "Activate the target text app, run ./scripts/select-inputmethod.sh --require-selected, then type a real probe before manual acceptance."
