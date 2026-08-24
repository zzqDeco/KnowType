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
if grep -q 'SessionSuggestionPipeline\.localSuggestions' "$coordinator_source"; then
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

swift build \
  --package-path "$ROOT_DIR" \
  --configuration release \
  --build-tests \
  -Xswiftc -enable-testing

bin_path="$(swift build --package-path "$ROOT_DIR" --configuration release --show-bin-path 2>/dev/null)"
xctest_bundle="$bin_path/KnowTypePackageTests.xctest"
if [[ -d "$xctest_bundle" ]] && command -v codesign >/dev/null 2>&1; then
  sign_identity="${CODESIGN_IDENTITY:--}"
  codesign --force --deep --sign "$sign_identity" "$xctest_bundle" >/dev/null
fi

perf_test_selector='KnowTypeInputMethodTests.InputHotPathPerformanceTests/testStrictRimeOnlyHotPathBudgetsWhenEnabled'
if ! test_list="$(
  swift test list \
    --package-path "$ROOT_DIR" \
    --configuration release \
    --skip-build
)"; then
  echo "error: failed to enumerate tests before running strict input perf selector $perf_test_selector" >&2
  exit 1
fi

selector_count="$(printf '%s\n' "$test_list" | awk -v selector="$perf_test_selector" '$0 == selector { count += 1 } END { print count + 0 }')"
if [[ "$selector_count" != "1" ]]; then
  echo "error: expected exactly one test selector $perf_test_selector, found $selector_count" >&2
  exit 1
fi

KNOWTYPE_RIME_ENABLED=1 \
KNOWTYPE_STRICT_INPUT_PERF=1 \
swift test \
  --package-path "$ROOT_DIR" \
  --configuration release \
  --skip-build \
  --filter "$perf_test_selector"
