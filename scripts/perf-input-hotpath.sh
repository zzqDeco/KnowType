#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: scripts/perf-input-hotpath.sh

Runs strict release-build performance budgets for the Rime-only IMK hot path.

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

coordinator_source="$ROOT_DIR/Sources/KnowTypeInputMethod/InputControllerCoordinator.swift"
if grep -q 'InputMethodPipeline\.localSuggestions' "$coordinator_source"; then
  echo "error: retired local suggestion pipeline is still referenced by InputControllerCoordinator" >&2
  exit 1
fi
if grep -q '\.segmentCandidates(' "$coordinator_source"; then
  echo "error: retired segment candidate path is still referenced by InputControllerCoordinator" >&2
  exit 1
fi
if grep -q 'lexiconRuntime\.makeEngine' "$coordinator_source"; then
  echo "error: retired local lexicon rebuild is still referenced by InputControllerCoordinator" >&2
  exit 1
fi

KNOWTYPE_RIME_ENABLED=1 \
KNOWTYPE_STRICT_INPUT_PERF=1 \
swift test \
  --package-path "$ROOT_DIR" \
  --configuration release \
  --filter InputHotPathPerformanceTests
