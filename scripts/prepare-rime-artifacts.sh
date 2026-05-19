#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RIME_VERSION="${RIME_VERSION:-1.16.1}"
RIME_GIT_HASH="${RIME_GIT_HASH:-de4700e}"
RIME_ARCHIVE_SHA256="${RIME_ARCHIVE_SHA256:-147dc220d20bcf2650889c98f943f1792b3c675dbef91f42f9151a216ad2c372}"
RIME_DEPS_ARCHIVE_SHA256="${RIME_DEPS_ARCHIVE_SHA256:-087e753056f092f644cc4a470f64ecf2cd9de18e684b220e0588f86f6b91dfcc}"
RIME_PLUM_REPOSITORY="${RIME_PLUM_REPOSITORY:-https://github.com/rime/plum.git}"
RIME_PLUM_REF="${RIME_PLUM_REF:-b1be1969f914cc005add4090631b855db00c2591}"
RIME_DATA_RECIPES="${RIME_DATA_RECIPES-rime/rime-prelude rime/rime-pinyin-simp}"
RIME_DEFAULT_SCHEMA="${RIME_DEFAULT_SCHEMA-pinyin_simp}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-$ROOT_DIR/.build/rime-downloads}"
VENDOR_DIR="${KNOWTYPE_RIME_VENDOR_DIR:-$ROOT_DIR/Vendor/Rime}"

usage() {
  cat <<'EOF'
Usage: scripts/prepare-rime-artifacts.sh [--vendor-dir PATH] [--download-dir PATH]

Downloads and verifies the pinned librime macOS universal artifacts used by
KnowType's optional native Rime bridge. CI does not need Homebrew.

Environment:
  RIME_VERSION                 Defaults to 1.16.1
  RIME_GIT_HASH                Defaults to de4700e
  RIME_ARCHIVE_SHA256          Expected rime archive SHA256
  RIME_DEPS_ARCHIVE_SHA256     Expected rime-deps archive SHA256
  RIME_PLUM_REPOSITORY         Defaults to https://github.com/rime/plum.git
  RIME_PLUM_REF                Pinned plum commit used for shared data recipes
  RIME_DATA_RECIPES            Space-separated plum recipes; empty disables data
  RIME_DEFAULT_SCHEMA          Schema patched into default.custom.yaml; empty skips
  KNOWTYPE_RIME_VENDOR_DIR     Default output directory
EOF
}

while (($# > 0)); do
  case "$1" in
    --vendor-dir)
      if (($# < 2)); then
        echo "error: --vendor-dir requires a value" >&2
        exit 2
      fi
      VENDOR_DIR="$2"
      shift 2
      ;;
    --download-dir)
      if (($# < 2)); then
        echo "error: --download-dir requires a value" >&2
        exit 2
      fi
      DOWNLOAD_DIR="$2"
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

verify_sha256() {
  local expected="$1"
  local file="$2"
  local actual
  actual="$(shasum -a 256 "$file" | awk '{ print $1 }')"
  [[ "$actual" == "$expected" ]] || die "checksum mismatch for $(basename "$file"): expected $expected got $actual"
}

command -v curl >/dev/null 2>&1 || die "curl is unavailable"
command -v git >/dev/null 2>&1 || die "git is unavailable"
command -v tar >/dev/null 2>&1 || die "tar is unavailable"
command -v shasum >/dev/null 2>&1 || die "shasum is unavailable"

rime_archive="rime-${RIME_GIT_HASH}-macOS-universal.tar.bz2"
rime_deps_archive="rime-deps-${RIME_GIT_HASH}-macOS-universal.tar.bz2"
rime_url="https://github.com/rime/librime/releases/download/${RIME_VERSION}/${rime_archive}"
rime_deps_url="https://github.com/rime/librime/releases/download/${RIME_VERSION}/${rime_deps_archive}"

mkdir -p "$DOWNLOAD_DIR"
if [[ ! -f "$DOWNLOAD_DIR/$rime_archive" ]]; then
  curl --fail --location --output "$DOWNLOAD_DIR/$rime_archive" "$rime_url"
fi
if [[ ! -f "$DOWNLOAD_DIR/$rime_deps_archive" ]]; then
  curl --fail --location --output "$DOWNLOAD_DIR/$rime_deps_archive" "$rime_deps_url"
fi

verify_sha256 "$RIME_ARCHIVE_SHA256" "$DOWNLOAD_DIR/$rime_archive"
verify_sha256 "$RIME_DEPS_ARCHIVE_SHA256" "$DOWNLOAD_DIR/$rime_deps_archive"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/knowtype-rime.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/deps"
tar --bzip2 -xf "$DOWNLOAD_DIR/$rime_archive" -C "$tmp_dir"
tar --bzip2 -xf "$DOWNLOAD_DIR/$rime_deps_archive" -C "$tmp_dir/deps"

rm -rf "$VENDOR_DIR"
mkdir -p "$VENDOR_DIR"
cp -R "$tmp_dir/dist" "$VENDOR_DIR/"
mkdir -p "$VENDOR_DIR/share"
if [[ -d "$tmp_dir/deps/share/opencc" ]]; then
  cp -R "$tmp_dir/deps/share/opencc" "$VENDOR_DIR/share/"
fi

recipes=()
if [[ -n "$RIME_DATA_RECIPES" ]]; then
  # Intentional word splitting: plum recipes are a space-separated list.
  recipes=( $RIME_DATA_RECIPES )
fi
if ((${#recipes[@]} > 0)); then
  plum_dir="$DOWNLOAD_DIR/plum-$RIME_PLUM_REF"
  if [[ ! -d "$plum_dir/.git" ]]; then
    rm -rf "$plum_dir"
    git init "$plum_dir"
    git -C "$plum_dir" remote add origin "$RIME_PLUM_REPOSITORY"
    git -C "$plum_dir" fetch --depth 1 origin "$RIME_PLUM_REF"
    git -C "$plum_dir" checkout --detach FETCH_HEAD
  fi
  plum_output="$tmp_dir/plum-output"
  mkdir -p "$plum_output"
  rime_dir="$plum_output" bash "$plum_dir/rime-install" "${recipes[@]}"
  cp -R "$plum_output/." "$VENDOR_DIR/share/"
fi

if [[ -n "$RIME_DEFAULT_SCHEMA" ]]; then
  cat >"$VENDOR_DIR/share/default.custom.yaml" <<EOF
patch:
  schema_list:
    - schema: $RIME_DEFAULT_SCHEMA
EOF
fi

cat >"$VENDOR_DIR/VERSION" <<EOF
librime=${RIME_VERSION}
git=${RIME_GIT_HASH}
plum=${RIME_PLUM_REF}
recipes=${RIME_DATA_RECIPES}
default_schema=${RIME_DEFAULT_SCHEMA}
rime_archive_sha256=${RIME_ARCHIVE_SHA256}
rime_deps_archive_sha256=${RIME_DEPS_ARCHIVE_SHA256}
EOF

echo "$VENDOR_DIR"
