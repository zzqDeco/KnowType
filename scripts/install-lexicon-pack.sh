#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: scripts/install-lexicon-pack.sh [pack-id] [--directory PATH] [--force]

Downloads, verifies, converts, and installs a managed KnowType lexicon pack.

Packs:
  rime-pinyin-simp  Rime Pinyin Simplified dictionary (Apache-2.0)

Options:
  --directory PATH  Install into a custom lexicon directory
  --force           Replace an existing pack output file
  -h, --help        Show this help.
EOF
}

args=()
while (($# > 0)); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if ((${#args[@]} == 0)); then
  args=("rime-pinyin-simp")
fi

swift run --package-path "$ROOT_DIR" knowtype-lexicon-tool install "${args[@]}"
