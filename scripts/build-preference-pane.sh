#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
BUNDLE_SHORT_VERSION="${KNOWTYPE_BUNDLE_SHORT_VERSION:-}"
BUNDLE_BUILD_VERSION="${KNOWTYPE_BUNDLE_BUILD_VERSION:-}"
DIST_DIR="$ROOT_DIR/dist"
PANE_DIR="$DIST_DIR/KnowType.prefPane"
CONTENTS_DIR="$PANE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

copy_swiftpm_resource_bundle() {
  local bundle_name="$1"
  local source_path="$BIN_DIR/$bundle_name"
  local destination_path="$CONTENTS_DIR/Resources/$bundle_name"

  if [[ ! -d "$source_path" ]]; then
    echo "error: required SwiftPM resource bundle is missing: $source_path" >&2
    exit 1
  fi

  rm -rf "$destination_path"
  cp -R "$source_path" "$CONTENTS_DIR/Resources/"
}

usage() {
  cat <<'EOF'
Usage: scripts/build-preference-pane.sh [--configuration debug|release] [--version X.Y.Z] [--build N]

Builds the KnowType PreferencePane bundle into dist/KnowType.prefPane without installing it.

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

swift build --package-path "$ROOT_DIR" --configuration "$CONFIGURATION" --product KnowTypePreferencePane >&2
BIN_DIR="$(swift build --package-path "$ROOT_DIR" --configuration "$CONFIGURATION" --show-bin-path 2>/dev/null)"

rm -rf "$PANE_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$CONTENTS_DIR/Resources"
cp "$ROOT_DIR/Resources/PreferencePane/Info.plist" "$CONTENTS_DIR/Info.plist"
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
cp "$BIN_DIR/libKnowTypePreferencePane.dylib" "$FRAMEWORKS_DIR/"
copy_swiftpm_resource_bundle "KnowType_KnowTypeSettingsUI.bundle"
copy_swiftpm_resource_bundle "KnowType_KnowTypeCore.bundle"
xcrun clang -bundle -x c /dev/null \
  -o "$MACOS_DIR/KnowTypePreferencePane" \
  -L"$FRAMEWORKS_DIR" \
  -lKnowTypePreferencePane \
  -Wl,-rpath,@loader_path/../Frameworks
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
