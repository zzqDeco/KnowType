#!/usr/bin/env bash
set -euo pipefail

TARGET_PATH="$HOME/Library/Input Methods/KnowType.app"
rm -rf "$TARGET_PATH"
echo "Removed KnowType from: $TARGET_PATH"
