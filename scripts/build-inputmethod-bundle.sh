#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
BUNDLE_SHORT_VERSION="${KNOWTYPE_BUNDLE_SHORT_VERSION:-}"
BUNDLE_BUILD_VERSION="${KNOWTYPE_BUNDLE_BUILD_VERSION:-}"
DIST_DIR="$ROOT_DIR/dist"
BUNDLE_DIR="$DIST_DIR/KnowType.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

usage() {
  cat <<'EOF'
Usage: scripts/build-inputmethod-bundle.sh [--configuration debug|release] [--version X.Y.Z] [--build N]

Builds the KnowType input-method executable and packages it into
dist/KnowType.app without installing it.

Options:
  --configuration  SwiftPM build configuration. Defaults to CONFIGURATION or debug.
  --version        Override CFBundleShortVersionString in the packaged bundle.
                   Defaults to KNOWTYPE_BUNDLE_SHORT_VERSION when set.
  --build          Override CFBundleVersion in the packaged bundle.
                   Defaults to KNOWTYPE_BUNDLE_BUILD_VERSION when set.
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
    --version)
      if (($# < 2)); then
        echo "error: --version requires a value" >&2
        exit 2
      fi
      BUNDLE_SHORT_VERSION="$2"
      shift 2
      ;;
    --build)
      if (($# < 2)); then
        echo "error: --build requires a value" >&2
        exit 2
      fi
      BUNDLE_BUILD_VERSION="$2"
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

swift build --package-path "$ROOT_DIR" --configuration "$CONFIGURATION" --product KnowTypeInputMethodApp >&2
BIN_DIR="$(swift build --package-path "$ROOT_DIR" --configuration "$CONFIGURATION" --show-bin-path 2>/dev/null)"

rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$CONTENTS_DIR/Resources"
cp "$BIN_DIR/KnowTypeInputMethodApp" "$MACOS_DIR/KnowTypeInputMethodApp"
cp "$ROOT_DIR/Resources/InputMethod/Info.plist" "$CONTENTS_DIR/Info.plist"
if [[ -n "$BUNDLE_SHORT_VERSION" || -n "$BUNDLE_BUILD_VERSION" ]]; then
  [[ -x "$PLIST_BUDDY" ]] || {
    echo "error: PlistBuddy is unavailable at $PLIST_BUDDY" >&2
    exit 1
  }
fi
if [[ -n "$BUNDLE_SHORT_VERSION" ]]; then
  "$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $BUNDLE_SHORT_VERSION" "$CONTENTS_DIR/Info.plist"
fi
if [[ -n "$BUNDLE_BUILD_VERSION" ]]; then
  "$PLIST_BUDDY" -c "Set :CFBundleVersion $BUNDLE_BUILD_VERSION" "$CONTENTS_DIR/Info.plist"
fi
for resource_path in "$ROOT_DIR"/Resources/InputMethod/*; do
  [[ -e "$resource_path" ]] || continue
  [[ "$(basename "$resource_path")" == "Info.plist" ]] && continue
  if [[ -d "$resource_path" ]]; then
    cp -R "$resource_path" "$CONTENTS_DIR/Resources/"
  else
    cp "$resource_path" "$CONTENTS_DIR/Resources/"
  fi
done
for resource_bundle in "$BIN_DIR"/KnowType_*.bundle; do
  [[ -d "$resource_bundle" ]] || continue
  cp -R "$resource_bundle" "$CONTENTS_DIR/Resources/"
done
chmod +x "$MACOS_DIR/KnowTypeInputMethodApp"

SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development/ { print $2; exit }')"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --deep --sign "$SIGN_IDENTITY" "$BUNDLE_DIR" >/dev/null

echo "$BUNDLE_DIR"
