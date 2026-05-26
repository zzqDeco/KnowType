#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION=""
BUILD_VERSION="${GITHUB_RUN_NUMBER:-1}"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

usage() {
  cat <<'EOF'
Usage: scripts/package-dmg.sh --version X.Y.Z [--build N] [--configuration release]

Builds a non-Developer-ID-signed, non-notarized Developer Preview DMG for
GitHub Releases. The DMG contains a KnowType.app payload plus command-file
install/uninstall entry points. It is intended for users who can manually allow
the preview build in macOS Gatekeeper.

Options:
  --version        Required release version, without the leading v.
  --build          CFBundleVersion for the packaged bundles. Defaults to
                   GITHUB_RUN_NUMBER or 1.
  --configuration  SwiftPM build configuration. Defaults to CONFIGURATION or release.
  -h, --help       Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
    --version)
      if (($# < 2)); then
        echo "error: --version requires a value" >&2
        exit 2
      fi
      VERSION="$2"
      shift 2
      ;;
    --build)
      if (($# < 2)); then
        echo "error: --build requires a value" >&2
        exit 2
      fi
      BUILD_VERSION="$2"
      shift 2
      ;;
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

die() {
  echo "error: $*" >&2
  exit 1
}

plist_read() {
  local key_path="$1"
  local plist_path="$2"
  "$PLIST_BUDDY" -c "Print $key_path" "$plist_path"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

[[ -n "$VERSION" ]] || die "--version is required"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--version must match X.Y.Z"
[[ "$BUILD_VERSION" =~ ^[0-9]+$ ]] || die "--build must be a positive integer"
[[ "$CONFIGURATION" == "debug" || "$CONFIGURATION" == "release" ]] ||
  die "--configuration must be debug or release"
[[ -x "$PLIST_BUDDY" ]] || die "PlistBuddy is unavailable at $PLIST_BUDDY"
command -v hdiutil >/dev/null 2>&1 || die "hdiutil is unavailable"
command -v shasum >/dev/null 2>&1 || die "shasum is unavailable"
command -v codesign >/dev/null 2>&1 || die "codesign is unavailable"

mkdir -p "$RELEASE_DIR"

bundle_path="$(
  CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}" "$ROOT_DIR/scripts/build-inputmethod-bundle.sh" \
    --configuration "$CONFIGURATION" \
    --version "$VERSION" \
    --build "$BUILD_VERSION" |
    tail -n 1
)"
prefpane_path="$(
  CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}" "$ROOT_DIR/scripts/build-preference-pane.sh" \
    --configuration "$CONFIGURATION" \
    --version "$VERSION" \
    --build "$BUILD_VERSION" |
    tail -n 1
)"

swift build --package-path "$ROOT_DIR" --configuration "$CONFIGURATION" --product knowtype-inputsource-tool >&2
bin_dir="$(swift build --package-path "$ROOT_DIR" --configuration "$CONFIGURATION" --show-bin-path 2>/dev/null)"
inputsource_tool_path="$bin_dir/knowtype-inputsource-tool"
[[ -x "$inputsource_tool_path" ]] || die "missing input-source helper: $inputsource_tool_path"
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$inputsource_tool_path" >/dev/null

[[ -d "$bundle_path" ]] || die "missing built input method bundle: $bundle_path"
[[ -d "$prefpane_path" ]] || die "missing built preference pane: $prefpane_path"
codesign --verify --deep --strict "$bundle_path"
codesign --verify --deep --strict "$prefpane_path"
codesign --verify --strict "$inputsource_tool_path"

artifact_stem="KnowType-v${VERSION}-macos-dev-preview"
staging_dir="$RELEASE_DIR/${artifact_stem}-dmg-root"
dmg_path="$RELEASE_DIR/${artifact_stem}.dmg"
checksum_path="$RELEASE_DIR/${artifact_stem}.dmg.sha256"
manifest_path="$RELEASE_DIR/release-manifest.json"

rm -rf "$staging_dir" "$dmg_path" "$checksum_path"
mkdir -p "$staging_dir/Payload" "$staging_dir/Resources" "$staging_dir/Scripts/lib" "$staging_dir/Scripts/bin"
cp -R "$bundle_path" "$staging_dir/Payload/"
cp -R "$prefpane_path" "$staging_dir/Payload/"
cp "$ROOT_DIR/scripts/install-inputmethod.sh" "$staging_dir/Scripts/"
cp "$ROOT_DIR/scripts/uninstall-inputmethod.sh" "$staging_dir/Scripts/"
cp "$ROOT_DIR/scripts/diagnose-inputmethod.sh" "$staging_dir/Scripts/"
cp "$ROOT_DIR/scripts/lib/inputsource-ids.sh" "$staging_dir/Scripts/lib/"
cp "$ROOT_DIR/scripts/lib/inputsource-tool.sh" "$staging_dir/Scripts/lib/"
cp "$ROOT_DIR/scripts/lib/inputmethod-installation.sh" "$staging_dir/Scripts/lib/"
cp "$inputsource_tool_path" "$staging_dir/Scripts/bin/"

release_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
release_tag="${GITHUB_REF_NAME:-}"
if [[ -z "$release_tag" ]]; then
  release_tag="$(git -C "$ROOT_DIR" describe --tags --exact-match HEAD 2>/dev/null || true)"
fi
release_tag="${release_tag:-v$VERSION}"
swift_version="$(swift --version 2>&1 | head -n 1)"
dmg_name="$(basename "$dmg_path")"
checksum_name="$(basename "$checksum_path")"
input_plist="$staging_dir/Payload/KnowType.app/Contents/Info.plist"
prefpane_plist="$staging_dir/Payload/KnowType.prefPane/Contents/Info.plist"

cat >"$manifest_path" <<EOF
{
  "schemaVersion": 1,
  "tag": "$(json_escape "$release_tag")",
  "releaseCommit": "$(json_escape "$release_commit")",
  "sourceKind": "developer-preview-dmg",
  "swiftVersion": "$(json_escape "$swift_version")",
  "artifacts": {
    "dmg": "$(json_escape "$dmg_name")",
    "checksum": "$(json_escape "$checksum_name")"
  },
  "bundles": [
    {
      "path": "KnowType.app",
      "bundleIdentifier": "$(json_escape "$(plist_read ":CFBundleIdentifier" "$input_plist")")",
      "shortVersion": "$(json_escape "$(plist_read ":CFBundleShortVersionString" "$input_plist")")",
      "buildVersion": "$(json_escape "$(plist_read ":CFBundleVersion" "$input_plist")")"
    },
    {
      "path": "KnowType.prefPane",
      "bundleIdentifier": "$(json_escape "$(plist_read ":CFBundleIdentifier" "$prefpane_plist")")",
      "shortVersion": "$(json_escape "$(plist_read ":CFBundleShortVersionString" "$prefpane_plist")")",
      "buildVersion": "$(json_escape "$(plist_read ":CFBundleVersion" "$prefpane_plist")")"
    }
  ],
  "distribution": "developer-preview-dmg-ad-hoc-signed-not-notarized"
}
EOF
cp "$manifest_path" "$staging_dir/Resources/release-manifest.json"

cat >"$staging_dir/README_FIRST.txt" <<EOF
KnowType Developer Preview

This DMG is not Developer ID signed or notarized. macOS may block the command
files or the installed input method until you explicitly allow them in Privacy
& Security or open them with Control-click > Open.

Install:
1. Open this DMG.
2. Double-click "Install KnowType.command".
3. If macOS blocks it, Control-click the command and choose Open, or open
   System Settings > Privacy & Security and choose Open Anyway.
4. After install, enable KnowType in System Settings > Keyboard > Input Sources
   if macOS asks for approval.

Uninstall:
Double-click "Uninstall KnowType.command". User data, provider profiles, Rime
userdb, AI context files, and Keychain secrets are preserved.
EOF

cat >"$staging_dir/Install KnowType.command" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KNOWTYPE_INPUTSOURCE_TOOL="$HERE/Scripts/bin/knowtype-inputsource-tool"
"$HERE/Scripts/install-inputmethod.sh" --from-dmg-payload "$HERE" "$@"
echo
echo "KnowType install command finished."
if [[ -t 0 ]]; then
  read -r -p "Press Return to close this window. " _
fi
EOF

cat >"$staging_dir/Uninstall KnowType.command" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KNOWTYPE_INPUTSOURCE_TOOL="$HERE/Scripts/bin/knowtype-inputsource-tool"
"$HERE/Scripts/uninstall-inputmethod.sh" "$@"
echo
echo "KnowType uninstall command finished."
if [[ -t 0 ]]; then
  read -r -p "Press Return to close this window. " _
fi
EOF

chmod +x \
  "$staging_dir/Install KnowType.command" \
  "$staging_dir/Uninstall KnowType.command" \
  "$staging_dir/Scripts/install-inputmethod.sh" \
  "$staging_dir/Scripts/uninstall-inputmethod.sh" \
  "$staging_dir/Scripts/diagnose-inputmethod.sh" \
  "$staging_dir/Scripts/bin/knowtype-inputsource-tool"

hdiutil create \
  -volname "KnowType v${VERSION} Developer Preview" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dmg_path" >/dev/null
hdiutil verify "$dmg_path" >/dev/null

(cd "$RELEASE_DIR" && shasum -a 256 "$(basename "$dmg_path")" >"$(basename "$checksum_path")")
rm -rf "$staging_dir"

echo "$dmg_path"
echo "$checksum_path"
echo "$manifest_path"
