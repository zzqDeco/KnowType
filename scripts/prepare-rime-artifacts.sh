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
RIME_DATA_RECIPE_REFS="${RIME_DATA_RECIPE_REFS-rime/rime-prelude=082425ea0684bca36474415d4a0e8db9b016487e rime/rime-pinyin-simp=0c6861ef7420ee780270ca6d993d18d4101049d0}"
RIME_ALLOW_UNPINNED_DATA_RECIPES="${RIME_ALLOW_UNPINNED_DATA_RECIPES:-0}"
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
  RIME_PLUM_REF                Pinned plum commit for unpinned override installs
  RIME_DATA_RECIPES            Space-separated Rime data recipes; empty disables data
  RIME_DATA_RECIPE_REFS        Space-separated recipe=commit pins
  RIME_ALLOW_UNPINNED_DATA_RECIPES=1 allows recipes without a pinned ref
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

canonical_recipe_package() {
  local recipe="$1"
  local package="${recipe%%[@:]*}"
  if [[ "$package" == */* ]]; then
    echo "$package"
  elif [[ "$package" == rime-* ]]; then
    echo "rime/$package"
  else
    echo "rime/rime-$package"
  fi
}

recipe_ref_for() {
  local package="$1"
  local entry
  for entry in $RIME_DATA_RECIPE_REFS; do
    if [[ "${entry%%=*}" == "$package" ]]; then
      echo "${entry#*=}"
      return 0
    fi
  done
  return 1
}

copy_pinned_recipe_files() {
  local package_dir="$1"
  local output_dir="$2"
  local rel
  while IFS= read -r -d '' rel; do
    rel="${rel#./}"
    mkdir -p "$output_dir/$(dirname "$rel")"
    cp "$package_dir/$rel" "$output_dir/$rel"
  done < <(
    cd "$package_dir"
    find . -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.txt' -o -name '*.gram' \) \
      ! -name '*.custom.yaml' ! -name '*.recipe.yaml' ! -name 'recipe.yaml' -print0
    if [[ -d opencc ]]; then
      find opencc -type f \( -name '*.json' -o -name '*.ocd' -o -name '*.txt' \) -print0
    fi
  )
}

install_pinned_recipe() {
  local recipe="$1"
  local output_dir="$2"
  local package
  package="$(canonical_recipe_package "$recipe")"
  local ref
  ref="$(recipe_ref_for "$package")" || {
    if [[ "$RIME_ALLOW_UNPINNED_DATA_RECIPES" == "1" ]]; then
      return 1
    fi
    die "missing pinned ref for Rime recipe '$recipe' (canonical package '$package')"
  }
  if [[ "$recipe" == *:* ]]; then
    if [[ "$RIME_ALLOW_UNPINNED_DATA_RECIPES" == "1" ]]; then
      return 1
    fi
    die "pinned recipe options are not supported for '$recipe'; use a package-level recipe or set RIME_ALLOW_UNPINNED_DATA_RECIPES=1"
  fi

  local package_dir="$tmp_dir/pinned-recipes/${package//\//-}-$ref"
  mkdir -p "$package_dir"
  git -C "$package_dir" init -q
  if git -C "$package_dir" remote get-url origin >/dev/null 2>&1; then
    git -C "$package_dir" remote set-url origin "https://github.com/$package.git"
  else
    git -C "$package_dir" remote add origin "https://github.com/$package.git"
  fi
  git -C "$package_dir" fetch --depth 1 origin "$ref"
  git -C "$package_dir" checkout --detach --force FETCH_HEAD
  local actual_ref
  actual_ref="$(git -C "$package_dir" rev-parse HEAD)"
  [[ "$actual_ref" == "$ref" ]] || die "recipe '$package' resolved to $actual_ref, expected $ref"
  copy_pinned_recipe_files "$package_dir" "$output_dir"
}

install_unpinned_recipes_with_plum() {
  local output_dir="$1"
  shift
  local plum_dir="$DOWNLOAD_DIR/plum-$RIME_PLUM_REF"
  if [[ ! -d "$plum_dir/.git" ]]; then
    rm -rf "$plum_dir"
    git init "$plum_dir"
  fi
  if git -C "$plum_dir" remote get-url origin >/dev/null 2>&1; then
    git -C "$plum_dir" remote set-url origin "$RIME_PLUM_REPOSITORY"
  else
    git -C "$plum_dir" remote add origin "$RIME_PLUM_REPOSITORY"
  fi
  git -C "$plum_dir" fetch --depth 1 origin "$RIME_PLUM_REF"
  git -C "$plum_dir" checkout --detach --force FETCH_HEAD
  git -C "$plum_dir" reset --hard FETCH_HEAD
  git -C "$plum_dir" clean -fdx
  rime_dir="$output_dir" bash "$plum_dir/rime-install" "$@"
}

install_data_recipes() {
  local output_dir="$1"
  shift
  local unpinned=()
  local recipe
  for recipe in "$@"; do
    if ! install_pinned_recipe "$recipe" "$output_dir"; then
      unpinned+=("$recipe")
    fi
  done
  if ((${#unpinned[@]} > 0)); then
    install_unpinned_recipes_with_plum "$output_dir" "${unpinned[@]}"
  fi
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
  recipe_output="$tmp_dir/recipe-output"
  mkdir -p "$recipe_output"
  install_data_recipes "$recipe_output" "${recipes[@]}"
  cp -R "$recipe_output/." "$VENDOR_DIR/share/"
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
recipe_refs=${RIME_DATA_RECIPE_REFS}
default_schema=${RIME_DEFAULT_SCHEMA}
rime_archive_sha256=${RIME_ARCHIVE_SHA256}
rime_deps_archive_sha256=${RIME_DEPS_ARCHIVE_SHA256}
EOF

echo "$VENDOR_DIR"
