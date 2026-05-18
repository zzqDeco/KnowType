#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
DIST_DIR="$ROOT_DIR/dist"
PANE_DIR="$DIST_DIR/KnowType.prefPane"
CONTENTS_DIR="$PANE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

usage() {
  cat <<'EOF'
Usage: scripts/build-preference-pane.sh [--configuration debug|release]

Builds the KnowType PreferencePane bundle into dist/KnowType.prefPane without installing it.

Options:
  --configuration  SwiftPM build configuration. Defaults to CONFIGURATION or debug.
  -h, --help       Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
    --configuration)
      if (($# < 2)); then
        echo "error: --configuration requires a value" >&2
        exit 2
      fi
      CONFIGURATION="$2"
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

swift build --package-path "$ROOT_DIR" --configuration "$CONFIGURATION" --product KnowTypePreferencePane >&2
BIN_DIR="$(swift build --package-path "$ROOT_DIR" --configuration "$CONFIGURATION" --show-bin-path 2>/dev/null)"

rm -rf "$PANE_DIR"
mkdir -p "$MACOS_DIR" "$CONTENTS_DIR/Resources"
cp "$ROOT_DIR/Resources/PreferencePane/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BIN_DIR/libKnowTypePreferencePane.dylib" "$MACOS_DIR/KnowTypePreferencePane"
if [[ -f "$ROOT_DIR/Resources/InputMethod/KnowTypeInputMethodIcon.icns" ]]; then
  cp "$ROOT_DIR/Resources/InputMethod/KnowTypeInputMethodIcon.icns" "$CONTENTS_DIR/Resources/"
fi
chmod +x "$MACOS_DIR/KnowTypePreferencePane"

SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development/ { print $2; exit }')"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --deep --sign "$SIGN_IDENTITY" "$PANE_DIR" >/dev/null

echo "$PANE_DIR"
