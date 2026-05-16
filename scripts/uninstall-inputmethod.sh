#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/uninstall-inputmethod.sh

Removes KnowType.app from ~/Library/Input Methods.

Options:
  -h, --help  Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
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

TARGET_PATH="$HOME/Library/Input Methods/KnowType.app"
rm -rf "$TARGET_PATH"
echo "Removed KnowType from: $TARGET_PATH"
