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
Usage: scripts/package-release.sh --version X.Y.Z [--build N] [--configuration release]

Builds the local MVP release zip for GitHub Releases. The package contains
KnowType.app and the compatibility KnowType.prefPane. It is ad-hoc signed and
not notarized.

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
command -v ditto >/dev/null 2>&1 || die "ditto is unavailable"
command -v shasum >/dev/null 2>&1 || die "shasum is unavailable"
command -v codesign >/dev/null 2>&1 || die "codesign is unavailable"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

bundle_path="$(
  CODESIGN_IDENTITY=- "$ROOT_DIR/scripts/build-inputmethod-bundle.sh" \
    --configuration "$CONFIGURATION" \
    --version "$VERSION" \
    --build "$BUILD_VERSION" |
    tail -n 1
)"
prefpane_path="$(
  CODESIGN_IDENTITY=- "$ROOT_DIR/scripts/build-preference-pane.sh" \
    --configuration "$CONFIGURATION" \
    --version "$VERSION" \
    --build "$BUILD_VERSION" |
    tail -n 1
)"

[[ -d "$bundle_path" ]] || die "missing built input method bundle: $bundle_path"
[[ -d "$prefpane_path" ]] || die "missing built preference pane: $prefpane_path"
codesign --verify --deep --strict "$bundle_path"
codesign --verify --deep --strict "$prefpane_path"

artifact_stem="KnowType-v${VERSION}-macos-local-mvp"
staging_dir="$RELEASE_DIR/$artifact_stem"
archive_path="$RELEASE_DIR/${artifact_stem}.zip"
checksum_path="$RELEASE_DIR/${artifact_stem}.zip.sha256"
manifest_path="$RELEASE_DIR/release-manifest.json"
archive_relative="dist/release/${artifact_stem}.zip"

mkdir -p "$staging_dir"
cp -R "$bundle_path" "$staging_dir/"
cp -R "$prefpane_path" "$staging_dir/"

release_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
release_tag="${GITHUB_REF_NAME:-}"
if [[ -z "$release_tag" ]]; then
  release_tag="$(git -C "$ROOT_DIR" describe --tags --exact-match HEAD 2>/dev/null || true)"
fi
release_tag="${release_tag:-v$VERSION}"
swift_version="$(swift --version 2>&1 | head -n 1)"
archive_name="$(basename "$archive_path")"
checksum_name="$(basename "$checksum_path")"
input_plist="$staging_dir/KnowType.app/Contents/Info.plist"
prefpane_plist="$staging_dir/KnowType.prefPane/Contents/Info.plist"

cat >"$manifest_path" <<EOF
{
  "tag": "$(json_escape "$release_tag")",
  "releaseCommit": "$(json_escape "$release_commit")",
  "swiftVersion": "$(json_escape "$swift_version")",
  "artifacts": {
    "archive": "$(json_escape "$archive_name")",
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
  "distribution": "local-mvp-ad-hoc-signed-not-notarized"
}
EOF

cp "$manifest_path" "$staging_dir/release-manifest.json"

ditto -c -k --sequesterRsrc --keepParent "$staging_dir" "$archive_path"
(cd "$ROOT_DIR" && shasum -a 256 "$archive_relative" >"$checksum_path")

echo "$archive_path"
echo "$checksum_path"
echo "$manifest_path"
