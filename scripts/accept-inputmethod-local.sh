#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_BUNDLE_PATH="$HOME/Library/Input Methods/KnowType.app"
BUNDLE_PATH="${KNOWTYPE_BUNDLE_PATH:-$DEFAULT_BUNDLE_PATH}"
LOG_LOOKBACK="${KNOWTYPE_LOG_LOOKBACK:-10m}"
REPORT_PATH="$ROOT_DIR/dist/KnowTypeLocalIMEAcceptance.md"
RUN_SMOKE=1
RUN_DIAGNOSE=1
RUN_INSTALL=0
RUN_SELECT=0
STRICT_DIAGNOSE=0
WRITE_REPORT=1
PRINT_CHECKLIST=0

usage() {
  cat <<'EOF'
Usage: scripts/accept-inputmethod-local.sh [options]

Runs the local KnowType IME acceptance harness. By default it performs
non-mutating preflight checks and writes a manual acceptance report template.
Real install and Text Input Source selection are opt-in.

Options:
  --install           Build and install KnowType before diagnostics.
  --select            Run the target-app selection preflight. Activate the target text app first.
  --strict            Treat diagnostic failures as hard failures.
  --path PATH         Inspect a specific installed KnowType.app bundle path.
  --log-lookback WIN  Log lookback for diagnostics, such as 10m or 1h. Defaults to 10m.
  --report PATH       Write the manual acceptance report template to PATH.
  --no-report         Do not write a report template.
  --skip-smoke        Skip deterministic script/bundle/profile smoke.
  --skip-diagnose     Skip installed-bundle diagnostics.
  --print-checklist   Print the manual typing checklist to stdout.
  -h, --help          Show this help.
EOF
}

run_step() {
  printf '\n==> %s\n' "$*"
  "$@"
}

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

git_value() {
  git -C "$ROOT_DIR" "$@" 2>/dev/null || true
}

manual_checklist() {
  cat <<'EOF'
Manual typing checklist:

TextEdit
- Type: wo jue de zhege fagnan
- Verify: candidate panel follows the caret, Space commits 我觉得这个方案, Tab commits prefix + first continuation.

Safari or Chrome
- Type in a normal input and textarea: zhege api latnecy youdian gao
- Verify: candidate panel follows the caret after scrolling, API stays uppercase, latency remains protected.

Electron or Codex-style text field
- Type: nishishei and ni
- Verify: marked text stays active, candidates page predictably, commit inserts into the focused field.

Terminal
- Type: /Users/zq/project/KnowType and swift test
- Verify: Level 0 protection commits unchanged and no provider request is needed.

Xcode
- Type identifiers containing API, JSON, macOS, InputMethodKit, snake_case, and camelCase.
- Verify: technical tokens and code-like snippets are preserved.

WeChat or Feishu chat field
- Type normal chat text and use Space, Tab, Option+1, and Option+R.
- Verify: candidate window remains visible and shortcuts do not conflict with the tested field.

Provider failure
- Disable or misconfigure the provider temporarily.
- Verify: traditional prefix candidates still appear and typing is not blocked.
EOF
}

write_report() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<EOF
# KnowType Local IME Acceptance Report

- Date: $(timestamp_utc)
- Git branch: $(git_value branch --show-current)
- Git commit: $(git_value rev-parse HEAD)
- macOS: $(sw_vers -productVersion 2>/dev/null || echo unknown)
- Bundle: $BUNDLE_PATH
- Log lookback: $LOG_LOOKBACK

## Preflight Evidence

- [ ] \`swift test\` result recorded separately if run for this acceptance pass.
- [ ] \`./scripts/smoke-inputmethod-install.sh\` passed.
- [ ] \`./scripts/diagnose-inputmethod.sh --strict --logs --log-lookback $LOG_LOOKBACK\` passed after install/profile setup.
- [ ] Gatekeeper accepts the installed bundle.
- [ ] Input menu visibly shows KnowType / 知键 in the target app.
- [ ] \`./scripts/select-inputmethod.sh --require-selected\` was run while the target text app was active.

## Manual Typing Results

| Target | Probe | Expected | Result | Notes |
|---|---|---|---|---|
| TextEdit | \`wo jue de zhege fagnan\` | caret-following panel; Space commits \`我觉得这个方案\`; Tab commits prefix + continuation | pending | |
| Safari/Chrome input | \`zhege api latnecy youdian gao\` | mixed Chinese/English correction; \`API\` and \`latency\` preserved | pending | |
| Safari/Chrome textarea | same probe after scrolling | panel follows caret after scroll | pending | |
| Electron/Codex-style field | \`nishishei\`, \`ni\` | marked text and candidate paging remain usable | pending | |
| Terminal | \`/Users/zq/project/KnowType\`, \`swift test\` | Level 0 unchanged, no provider dependency | pending | |
| Xcode | \`API JSON macOS InputMethodKit snake_case camelCase\` | technical tokens preserved | pending | |
| WeChat chat field | normal chat text plus Space/Tab/Option+1/Option+R | candidate window remains visible and shortcuts do not conflict | pending | |
| Feishu chat field | normal chat text plus Space/Tab/Option+1/Option+R | candidate window remains visible and shortcuts do not conflict | pending | |
| Provider failure | provider disabled or invalid endpoint | traditional candidates still usable | pending | |

## Screenshots Or Logs

- Add screenshots, screen recordings, or log snippets here.
- Record host app versions when a failure appears host-specific.

## Checklist

$(manual_checklist)
EOF
  printf 'Wrote acceptance report template: %s\n' "$path"
}

while (($# > 0)); do
  case "$1" in
    --install)
      RUN_INSTALL=1
      shift
      ;;
    --select)
      RUN_SELECT=1
      shift
      ;;
    --strict)
      STRICT_DIAGNOSE=1
      shift
      ;;
    --path)
      if (($# < 2)); then
        echo "error: --path requires a value" >&2
        exit 2
      fi
      BUNDLE_PATH="$2"
      shift 2
      ;;
    --log-lookback)
      if (($# < 2)); then
        echo "error: --log-lookback requires a value" >&2
        exit 2
      fi
      LOG_LOOKBACK="$2"
      shift 2
      ;;
    --report)
      if (($# < 2)); then
        echo "error: --report requires a value" >&2
        exit 2
      fi
      REPORT_PATH="$2"
      WRITE_REPORT=1
      shift 2
      ;;
    --no-report)
      WRITE_REPORT=0
      shift
      ;;
    --skip-smoke)
      RUN_SMOKE=0
      shift
      ;;
    --skip-diagnose)
      RUN_DIAGNOSE=0
      shift
      ;;
    --print-checklist)
      PRINT_CHECKLIST=1
      shift
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

echo "KnowType local IME acceptance harness"
echo "Commit: $(git_value rev-parse HEAD)"
echo "Bundle: $BUNDLE_PATH"

if (( RUN_SMOKE == 1 )); then
  run_step "$ROOT_DIR/scripts/smoke-inputmethod-install.sh"
fi

if (( RUN_INSTALL == 1 )); then
  run_step "$ROOT_DIR/scripts/install-inputmethod.sh"
fi

if (( RUN_DIAGNOSE == 1 )); then
  diagnose_args=(--logs --log-lookback "$LOG_LOOKBACK" --path "$BUNDLE_PATH")
  if (( STRICT_DIAGNOSE == 1 )); then
    diagnose_args=(--strict "${diagnose_args[@]}")
  fi
  run_step "$ROOT_DIR/scripts/diagnose-inputmethod.sh" "${diagnose_args[@]}"
fi

if (( RUN_SELECT == 1 )); then
  echo
  echo "Activate the target text app before using --select. This is a preflight only; manual typing remains required."
  run_step "$ROOT_DIR/scripts/select-inputmethod.sh" --require-selected
fi

if (( WRITE_REPORT == 1 )); then
  write_report "$REPORT_PATH"
fi

if (( PRINT_CHECKLIST == 1 )); then
  echo
  manual_checklist
fi

echo
echo "Local IME acceptance requires typing the report probes in the target apps."
