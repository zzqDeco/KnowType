#!/usr/bin/env bash
set -u -o pipefail

DEFAULT_BUNDLE_PATH="$HOME/Library/Input Methods/KnowType.app"
BUNDLE_PATH="${KNOWTYPE_BUNDLE_PATH:-$DEFAULT_BUNDLE_PATH}"
DEFAULT_PREFPANE_PATH="$HOME/Library/PreferencePanes/KnowType.prefPane"
PREFPANE_PATH="${KNOWTYPE_PREFPANE_PATH:-$DEFAULT_PREFPANE_PATH}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR"
STRICT=0
REQUIRE_SELECTED=0
SHOW_LOGS=0
JSON_OUTPUT=0
ALLOW_LEGACY_PARENT_ANCHOR=0
LOG_LOOKBACK="${KNOWTYPE_LOG_LOOKBACK:-30m}"
KNOWTYPE_PYTHON3="${KNOWTYPE_PYTHON3:-/usr/bin/python3}"
if [[ ! -x "$KNOWTYPE_PYTHON3" ]]; then
  KNOWTYPE_PYTHON3="$(command -v python3 2>/dev/null || true)"
fi

usage() {
  cat <<'EOF'
Usage: scripts/diagnose-inputmethod.sh [--strict] [--require-selected] [--path /path/to/KnowType.app]

Checks the local KnowType input-method installation without changing system state.

Options:
  --strict            Exit non-zero when critical install, signing, registration, or enabled-state checks fail.
  --require-selected  Treat this diagnostic process's current input source as a failure when it is not KnowType.
                      Manual acceptance still requires typing a probe in the target app.
  --logs              Include recent KnowType, Gatekeeper, and input-source sandbox log hints.
  --log-lookback      Time window for --logs, such as 10m, 1h, or 2h. Defaults to 30m.
  --path              Inspect a specific KnowType.app bundle path.
  --json              Print a stable machine-readable install snapshot and exit.
  --legacy-parent-anchor
                      Deprecated compatibility flag. The parent anchor is enabled automatically for the visible input mode.
  -h, --help          Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
    --strict)
      STRICT=1
      shift
      ;;
    --require-selected)
      REQUIRE_SELECTED=1
      shift
      ;;
    --logs)
      SHOW_LOGS=1
      shift
      ;;
    --json)
      JSON_OUTPUT=1
      shift
      ;;
    --legacy-parent-anchor)
      ALLOW_LEGACY_PARENT_ANCHOR=1
      shift
      ;;
    --log-lookback)
      if (($# < 2)); then
        echo "error: --log-lookback requires a value" >&2
        exit 2
      fi
      LOG_LOOKBACK="$2"
      shift 2
      ;;
    --path)
      if (($# < 2)); then
        echo "error: --path requires a value" >&2
        exit 2
      fi
      BUNDLE_PATH="$2"
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

source "$SCRIPTS_DIR/lib/inputsource-ids.sh"
source "$SCRIPTS_DIR/lib/inputsource-tool.sh"
source "$SCRIPTS_DIR/lib/inputmethod-installation.sh"

failures=0
warnings=0
gatekeeper_rejected=0
hitoolbox_enabled_knowtype=""
hitoolbox_selected_knowtype=""
thirdparty_legacy_knowtype=""
parent_select_capable=""
parent_name=""
mode_name=""

ok() {
  printf '[ok] %s\n' "$1"
}

warn() {
  warnings=$((warnings + 1))
  printf '[warn] %s\n' "$1"
}

fail() {
  failures=$((failures + 1))
  printf '[fail] %s\n' "$1"
}

info() {
  printf '[info] %s\n' "$1"
}

print_json_snapshot() {
  KNOWTYPE_DIAG_BUNDLE_PATH="$BUNDLE_PATH" \
  KNOWTYPE_DIAG_PREFPANE_PATH="$PREFPANE_PATH" \
  KNOWTYPE_DIAG_INSTALL_STATE_PATH="$(knowtype_install_state_path)" \
  KNOWTYPE_DIAG_BACKUP_ROOT="$(knowtype_backup_root_dir)" \
  KNOWTYPE_DIAG_APP_SUPPORT="$(knowtype_app_support_dir)" \
  KNOWTYPE_DIAG_RIME_USER_DATA="${KNOWTYPE_RIME_USER_DATA_DIR:-$(knowtype_app_support_dir)/Rime}" \
  PYTHONPATH="$SCRIPTS_DIR/lib${PYTHONPATH:+:$PYTHONPATH}" \
  "$KNOWTYPE_PYTHON3" - <<'PY'
import json
import hashlib
import os
import plistlib
import re
from datetime import datetime, timezone
from pathlib import Path
from provider_endpoint_summary import privacy_safe_endpoint_summary

def file_mtime(path):
    try:
        return Path(path).stat().st_mtime
    except OSError:
        return None

def file_mtime_iso(path):
    value = file_mtime(path)
    if value is None:
        return None
    return datetime.fromtimestamp(value, timezone.utc).isoformat().replace("+00:00", "Z")

def load_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return None

def bundle_info(bundle_path):
    bundle = Path(bundle_path)
    info_path = bundle / "Contents" / "Info.plist"
    payload = {
        "path": str(bundle),
        "exists": bundle.is_dir(),
        "version": None,
        "build": None,
        "bundleIdentifier": None,
        "executableExists": (bundle / "Contents" / "MacOS" / "KnowTypeInputMethodApp").is_file(),
    }
    if info_path.is_file():
        try:
            with info_path.open("rb") as handle:
                plist = plistlib.load(handle)
            payload["version"] = plist.get("CFBundleShortVersionString")
            payload["build"] = plist.get("CFBundleVersion")
            payload["bundleIdentifier"] = plist.get("CFBundleIdentifier")
        except Exception as error:
            payload["plistError"] = type(error).__name__
    return payload

def default_provider(app_support):
    support = Path(app_support)
    canonical_path = support / "providers.v2.json"
    legacy_path = support / "providers.json"
    snapshot_path = support / "providers.legacy.json"
    legacy_file = load_json(legacy_path)
    legacy_is_tombstone = (
        isinstance(legacy_file, dict)
        and legacy_file.get("schemaVersion") == "migrated-to-providers.v2.json"
        and legacy_file.get("canonicalFile") == "providers.v2.json"
    )
    legacy_expects_canonical = (
        bool(legacy_file.get("canonicalExpected"))
        if isinstance(legacy_file, dict) and "canonicalExpected" in legacy_file
        else snapshot_path.is_file()
    )
    legacy_is_configuration = legacy_path.is_file() and not legacy_is_tombstone
    if canonical_path.is_file():
        provider_path = canonical_path
        storage_state = "legacy-diverged" if legacy_is_configuration else "canonical"
    elif legacy_is_configuration:
        provider_path = legacy_path
        storage_state = "legacy-unmigrated"
    elif legacy_is_tombstone and legacy_expects_canonical:
        provider_path = canonical_path
        storage_state = "canonical-missing"
    elif legacy_is_tombstone:
        provider_path = canonical_path
        storage_state = "tombstone"
    else:
        provider_path = canonical_path
        storage_state = "missing"
    provider_file = load_json(provider_path)
    result = {
        "path": str(provider_path),
        "canonicalPath": str(canonical_path),
        "legacyPath": str(legacy_path),
        "exists": provider_path.is_file(),
        "storageState": storage_state,
        "defaultProfile": None,
    }
    profiles = []
    if isinstance(provider_file, dict):
        profiles = provider_file.get("profiles") or []
    default = next((profile for profile in profiles if profile.get("isDefault")), None)
    if default:
        result["defaultProfile"] = {
            "displayName": default.get("displayName"),
            "kind": default.get("kind"),
            "model": default.get("model"),
            "baseURL": privacy_safe_endpoint_summary(default.get("baseURL")),
        }
    return result

def backup_summary(root):
    root_path = Path(root)
    backups = []
    managed_id_pattern = re.compile(r"^\d{8}T\d{6}Z-\d{4}-")
    if root_path.is_dir():
        for directory in sorted([p for p in root_path.iterdir() if p.is_dir()], reverse=True):
            manifest = load_json(directory / "manifest.json") or {}
            if not managed_id_pattern.match(directory.name):
                continue
            if manifest.get("backupID") != directory.name:
                continue
            if not (directory / "KnowType.app").is_dir():
                continue
            backups.append({
                "backupID": directory.name,
                "createdAt": manifest.get("createdAt"),
                "sourceVersion": manifest.get("sourceVersion"),
                "sourceBuild": manifest.get("sourceBuild"),
                "includedPrefPane": manifest.get("includedPrefPane"),
            })
    return {
        "root": str(root_path),
        "count": len(backups),
        "latest": backups[0] if backups else None,
    }

def accepted_learning_status(app_support, home):
    history_path = Path(app_support) / "AI" / "accepted-ai-learning.jsonl"
    summary_path = Path(app_support) / "AI" / "accepted-ai-summary.json"
    feedback_history_path = Path(app_support) / "AI" / "accepted-ai-feedback.jsonl"
    feedback_summary_path = Path(app_support) / "AI" / "accepted-ai-feedback-summary.json"
    mirror_path = Path(home) / ".knowtype" / "ACCEPTED_AI_LEARNING.md"
    feedback_mirror_path = Path(home) / ".knowtype" / "ACCEPTED_AI_FEEDBACK.md"
    lexical_json_path = Path(app_support) / "AI" / "lexical-profile.json"
    lexical_markdown_path = Path(home) / ".knowtype" / "LEXICAL_PROFILE.md"

    def load_jsonl(path):
        rows = []
        invalid = 0
        if not path.is_file():
            return rows, invalid
        try:
            with path.open(encoding="utf-8") as handle:
                for line in handle:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        rows.append(json.loads(line))
                    except Exception:
                        invalid += 1
        except Exception:
            invalid += 1
        return rows, invalid

    records, invalid_lines = load_jsonl(history_path)
    feedback_records, invalid_feedback_lines = load_jsonl(feedback_history_path)

    def valid_feedback_record(record):
        if not isinstance(record, dict):
            return False
        ranges = record.get("deletedRanges", [])
        if not isinstance(ranges, list):
            return False
        if any(not isinstance(item, dict) for item in ranges):
            return False
        texts = record.get("deletedTexts", [])
        if not isinstance(texts, list):
            return False
        try:
            float(record.get("deletedRatio", 0))
        except (TypeError, ValueError):
            return False
        return True

    valid_feedback_records = []
    for record in feedback_records:
        if valid_feedback_record(record):
            valid_feedback_records.append(record)
        else:
            invalid_feedback_lines += 1
    feedback_records = valid_feedback_records

    def feedback_hash_fragment(record):
        return "|".join([
            str(record.get("acceptID", "")),
            str(record.get("acceptedTextHash", "")),
            ",".join(f"{item.get('location', '')}:{item.get('length', '')}" for item in record.get("deletedRanges", [])),
            "\u001f".join(str(item) for item in record.get("deletedTexts", [])),
            str(record.get("replacementText", "")),
            f"{float(record.get('deletedRatio', 0)):.4f}",
            str(record.get("strength", "")),
        ])

    history_hash = None
    if records:
        joined = "\n".join(str(record.get("textHash", "")) for record in records)
        history_hash = hashlib.sha256(joined.encode("utf-8")).hexdigest()

    summary = load_json(summary_path)
    if not isinstance(summary, dict):
        summary = None
    summary_exists = summary_path.is_file()
    if records:
        is_current = bool(summary) and summary.get("acceptedCount") == len(records) and summary.get("historyHash") == history_hash
    else:
        is_current = summary is None and not summary_exists

    feedback_history_hash = None
    if feedback_records:
        joined = "\n".join(feedback_hash_fragment(record) for record in feedback_records)
        feedback_history_hash = hashlib.sha256(joined.encode("utf-8")).hexdigest()

    feedback_summary = load_json(feedback_summary_path)
    if not isinstance(feedback_summary, dict):
        feedback_summary = None
    feedback_summary_exists = feedback_summary_path.is_file()
    if feedback_records:
        feedback_is_current = bool(feedback_summary) and feedback_summary.get("feedbackCount") == len(feedback_records) and feedback_summary.get("historyHash") == feedback_history_hash
    else:
        feedback_is_current = feedback_summary is None and not feedback_summary_exists

    try:
        lexical_markdown = lexical_markdown_path.read_text(encoding="utf-8")
    except Exception:
        lexical_markdown = ""

    warnings = []
    if invalid_lines:
        warnings.append(f"invalid_history_lines:{invalid_lines}")
    if invalid_feedback_lines:
        warnings.append(f"invalid_feedback_history_lines:{invalid_feedback_lines}")
    if summary_exists and summary is None:
        warnings.append("summary_unreadable")
    elif records and not summary:
        warnings.append("summary_missing")
    elif not is_current:
        warnings.append("summary_stale")
    if feedback_summary_exists and feedback_summary is None:
        warnings.append("feedback_summary_unreadable")
    elif feedback_records and not feedback_summary:
        warnings.append("feedback_summary_missing")
    elif not feedback_is_current:
        warnings.append("feedback_summary_stale")

    return {
        "schemaVersion": 1,
        "history": {
            "path": str(history_path),
            "exists": history_path.is_file(),
            "recordCount": len(records),
            "historyHash": history_hash,
            "mtime": file_mtime_iso(history_path),
        },
        "summary": {
            "path": str(summary_path),
            "exists": summary_path.is_file(),
            "acceptedCount": summary.get("acceptedCount", 0) if isinstance(summary, dict) else 0,
            "historyHash": summary.get("historyHash") if isinstance(summary, dict) else None,
            "termCount": len(summary.get("termProfile", [])) if isinstance(summary, dict) else 0,
            "recentCommitCount": len(summary.get("recentAcceptedCommits", [])) if isinstance(summary, dict) else 0,
            "generatedAt": summary.get("generatedAt") if isinstance(summary, dict) else None,
            "mtime": file_mtime_iso(summary_path),
            "isCurrentWithHistory": is_current,
        },
        "mirror": {
            "path": str(mirror_path),
            "exists": mirror_path.is_file(),
            "mtime": file_mtime_iso(mirror_path),
        },
        "feedback": {
            "history": {
                "path": str(feedback_history_path),
                "exists": feedback_history_path.is_file(),
                "recordCount": len(feedback_records),
                "historyHash": feedback_history_hash,
                "mtime": file_mtime_iso(feedback_history_path),
            },
            "summary": {
                "path": str(feedback_summary_path),
                "exists": feedback_summary_path.is_file(),
                "feedbackCount": feedback_summary.get("feedbackCount", 0) if isinstance(feedback_summary, dict) else 0,
                "strongCount": feedback_summary.get("strongCount", 0) if isinstance(feedback_summary, dict) else 0,
                "avoidTermCount": len(feedback_summary.get("avoidTerms", [])) if isinstance(feedback_summary, dict) else 0,
                "historyHash": feedback_summary.get("historyHash") if isinstance(feedback_summary, dict) else None,
                "generatedAt": feedback_summary.get("generatedAt") if isinstance(feedback_summary, dict) else None,
                "mtime": file_mtime_iso(feedback_summary_path),
                "isCurrentWithHistory": feedback_is_current,
            },
            "mirror": {
                "path": str(feedback_mirror_path),
                "exists": feedback_mirror_path.is_file(),
                "mtime": file_mtime_iso(feedback_mirror_path),
            },
        },
        "lexicalProfile": {
            "jsonPath": str(lexical_json_path),
            "markdownPath": str(lexical_markdown_path),
            "jsonExists": lexical_json_path.is_file(),
            "markdownExists": lexical_markdown_path.is_file(),
            "containsAcceptedAISummary": "accepted-ai-summary:" in lexical_markdown,
            "mtime": file_mtime_iso(lexical_markdown_path),
        },
        "warnings": warnings,
    }

bundle_path = os.environ["KNOWTYPE_DIAG_BUNDLE_PATH"]
prefpane_path = os.environ["KNOWTYPE_DIAG_PREFPANE_PATH"]
install_state_path = os.environ["KNOWTYPE_DIAG_INSTALL_STATE_PATH"]
backup_root = os.environ["KNOWTYPE_DIAG_BACKUP_ROOT"]
app_support = os.environ["KNOWTYPE_DIAG_APP_SUPPORT"]
home = Path.home()
warnings = []
failures = []

bundle = bundle_info(bundle_path)
if not bundle["exists"]:
    failures.append("bundle_missing")
if not bundle["executableExists"]:
    failures.append("executable_missing")

install_state = load_json(install_state_path)
if install_state is None:
    warnings.append("install_state_missing")
elif bundle.get("version") and install_state.get("version") and bundle["version"] != install_state["version"]:
    warnings.append("install_state_version_mismatch")

rime_dylib = Path(bundle_path) / "Contents" / "Frameworks" / "librime.1.dylib"
rime_data = Path(bundle_path) / "Contents" / "Resources" / "rime-data"
user_data = {
    "appSupport": app_support,
    "providerProfiles": default_provider(app_support),
    "selectionHistoryExists": (Path(app_support) / "user-selection-history.json").is_file(),
    "lexicalProfile": {
        "path": str(Path(app_support) / "AI" / "lexical-profile.json"),
        "exists": (Path(app_support) / "AI" / "lexical-profile.json").is_file(),
        "mtime": file_mtime(Path(app_support) / "AI" / "lexical-profile.json"),
    },
    "environmentDocument": {
        "path": str(home / ".knowtype" / "ENV.md"),
        "exists": (home / ".knowtype" / "ENV.md").is_file(),
        "mtime": file_mtime(home / ".knowtype" / "ENV.md"),
    },
    "correctionDocument": {
        "path": str(home / ".knowtype" / "CORRECTION.md"),
        "exists": (home / ".knowtype" / "CORRECTION.md").is_file(),
        "mtime": file_mtime(home / ".knowtype" / "CORRECTION.md"),
    },
    "lexicalProfileMirror": {
        "path": str(home / ".knowtype" / "LEXICAL_PROFILE.md"),
        "exists": (home / ".knowtype" / "LEXICAL_PROFILE.md").is_file(),
        "mtime": file_mtime(home / ".knowtype" / "LEXICAL_PROFILE.md"),
    },
    "acceptedLearning": accepted_learning_status(app_support, home),
}

snapshot = {
    "schemaVersion": 1,
    "install": {
        "statePath": install_state_path,
        "state": install_state,
    },
    "bundle": bundle,
    "preferencePane": {
        "path": prefpane_path,
        "exists": Path(prefpane_path).is_dir(),
    },
    "rime": {
        "dylibPath": str(rime_dylib),
        "dylibExists": rime_dylib.is_file(),
        "dataPath": str(rime_data),
        "dataExists": rime_data.is_dir(),
        "userDataPath": os.environ["KNOWTYPE_DIAG_RIME_USER_DATA"],
        "userDataExists": Path(os.environ["KNOWTYPE_DIAG_RIME_USER_DATA"]).is_dir(),
    },
    "ai": user_data["providerProfiles"],
    "userData": user_data,
    "backups": backup_summary(backup_root),
    "warnings": warnings,
    "failures": failures,
}
print(json.dumps(snapshot, ensure_ascii=False, indent=2, sort_keys=True))
PY
}

if (( JSON_OUTPUT == 1 )); then
  print_json_snapshot
  exit 0
fi

strip_lsregister_suffix() {
  local value="$1"
  value="${value% (0x*)}"
  printf '%s' "$value"
}

expand_home_path() {
  local path="$1"
  case "$path" in
    "~")
      printf '%s' "$HOME"
      ;;
    "~/"*)
      printf '%s/%s' "$HOME" "${path#~/}"
      ;;
    *)
      printf '%s' "$path"
      ;;
  esac
}

canonical_bundle_path() {
  local path="$1"
  path="$(expand_home_path "$(strip_lsregister_suffix "$path")")"
  if [[ -e "$path" ]]; then
    printf '%s/%s' "$(cd "$(dirname "$path")" && pwd -P)" "$(basename "$path")"
  else
    printf '%s' "$path"
  fi
}

plist_value() {
  local key="$1"
  local plist="$2"
  knowtype_plist_value "$key" "$plist"
}

plist_buddy_value() {
  local key="$1"
  local plist="$2"
  local output
  if output="$(/usr/libexec/PlistBuddy -c "Print $key" "$plist" 2>/dev/null)"; then
    printf '%s' "$output"
  fi
}

expect_plist_value() {
  local key="$1"
  local expected="$2"
  local plist="$3"
  local actual
  actual="$(plist_value "$key" "$plist")"
  if [[ "$actual" == "$expected" ]]; then
    ok "Info.plist $key = $expected"
  else
    fail "Info.plist $key expected '$expected' but found '${actual:-<missing>}'"
  fi
}

expect_plist_buddy_value() {
  local key="$1"
  local expected="$2"
  local plist="$3"
  local actual
  actual="$(plist_buddy_value "$key" "$plist")"
  if [[ "$actual" == "$expected" ]]; then
    ok "Info.plist $key = $expected"
  else
    fail "Info.plist $key expected '$expected' but found '${actual:-<missing>}'"
  fi
}

echo "KnowType input-method diagnostics"
echo "Bundle: $BUNDLE_PATH"
echo "Compatibility PreferencePane: $PREFPANE_PATH"
echo

if [[ -d "$BUNDLE_PATH" ]]; then
  ok "bundle directory exists"
else
  fail "bundle directory is missing; run ./scripts/install-inputmethod.sh"
fi

INFO_PLIST="$BUNDLE_PATH/Contents/Info.plist"
EXECUTABLE="$BUNDLE_PATH/Contents/MacOS/KnowTypeInputMethodApp"
CORE_RESOURCE_BUNDLE="$BUNDLE_PATH/Contents/Resources/KnowType_KnowTypeCore.bundle"
SETTINGS_UI_RESOURCE_BUNDLE="$BUNDLE_PATH/Contents/Resources/KnowType_KnowTypeSettingsUI.bundle"
ICON_RESOURCE="$BUNDLE_PATH/Contents/Resources/KnowTypeInputMethodIcon.tiff"
PARENT_ID="$KNOWTYPE_PARENT_INPUT_SOURCE_ID"
MODE_ID="$KNOWTYPE_ACTIVE_INPUT_MODE_ID"
SINGLE_INPUT_SOURCE=0
if [[ "$MODE_ID" == "$PARENT_ID" ]]; then
  SINGLE_INPUT_SOURCE=1
fi

if [[ -f "$INFO_PLIST" ]]; then
  ok "Info.plist exists"
  expect_plist_value "CFBundleIdentifier" "$PARENT_ID" "$INFO_PLIST"
  expect_plist_value "CFBundleExecutable" "KnowTypeInputMethodApp" "$INFO_PLIST"
  expect_plist_value "TISInputSourceID" "$PARENT_ID" "$INFO_PLIST"
  expect_plist_value "InputMethodConnectionName" "$KNOWTYPE_INPUT_METHOD_CONNECTION_NAME" "$INFO_PLIST"
  expect_plist_value "InputMethodServerControllerClass" "KnowTypeInputController" "$INFO_PLIST"
  expect_plist_value "InputMethodServerDelegateClass" "KnowTypeInputController" "$INFO_PLIST"
  expect_plist_value "LSBackgroundOnly" "false" "$INFO_PLIST"
  expect_plist_value "LSUIElement" "true" "$INFO_PLIST"
  expect_plist_value "LSHasLocalizedDisplayName" "true" "$INFO_PLIST"
  if [[ -n "$(plist_value "TISIconIsTemplate" "$INFO_PLIST")" ]]; then
    warn "Info.plist contains private/undocumented TISIconIsTemplate; rebuild from current sources"
  fi
  if (( SINGLE_INPUT_SOURCE == 1 )); then
    fail "KnowType is configured as a parent-only input source; rebuild with the visible .Hans input mode model"
  elif [[ -n "$(plist_value "ComponentInputModeDict" "$INFO_PLIST")" ]]; then
    ok "Info.plist declares the visible component input mode"
    expect_plist_buddy_value ":ComponentInputModeDict:tsInputModeListKey:$MODE_ID:TISInputSourceID" "$MODE_ID" "$INFO_PLIST"
    expect_plist_buddy_value ":ComponentInputModeDict:tsInputModeListKey:$MODE_ID:TISIntendedLanguage" "zh-Hans" "$INFO_PLIST"
    expect_plist_buddy_value ":ComponentInputModeDict:tsInputModeListKey:$MODE_ID:tsInputModeIsVisibleKey" "true" "$INFO_PLIST"
    expect_plist_buddy_value ":ComponentInputModeDict:tsVisibleInputModeOrderedArrayKey:0" "$MODE_ID" "$INFO_PLIST"
  else
    fail "Info.plist is missing ComponentInputModeDict; this macOS System Settings build does not expose parent-only third-party IMK apps as addable input sources"
  fi
else
  fail "Info.plist is missing"
fi

if [[ -d "$BUNDLE_PATH" ]]; then
  LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [[ -x "$LSREGISTER" ]]; then
    CANONICAL_BUNDLE_PATH="$(canonical_bundle_path "$BUNDLE_PATH")"
    STALE_LS_PATHS="$(
      "$LSREGISTER" -dump 2>/dev/null | awk -v id="$PARENT_ID" '
        /^bundle id:/ {
          path = ""
          matched = 0
        }
        /^[[:space:]]*path:/ {
          sub(/^[^:]*:[[:space:]]*/, "")
          path = $0
        }
        /^[[:space:]]*identifier:/ {
          value = $0
          sub(/^[^:]*:[[:space:]]*/, "", value)
          sub(/[[:space:]]*\(0x[[:xdigit:]]+\)$/, "", value)
          if (value == id) {
            matched = 1
          }
        }
        matched == 1 && path != "" {
          print path
          matched = 0
        }
      ' | while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        canonical_path="$(canonical_bundle_path "$path")"
        if [[ "$canonical_path" != "$CANONICAL_BUNDLE_PATH" ]]; then
          printf '%s\n' "$path"
        fi
      done
    )"
    if [[ -z "$STALE_LS_PATHS" ]]; then
      ok "LaunchServices has no stale KnowType bundle records"
    else
      fail "LaunchServices has stale KnowType bundle records outside ~/Library/Input Methods/KnowType.app; dist/KnowType.app, release extraction, or backup paths can split helper selection from the real input menu. Reinstall with ./scripts/install-inputmethod.sh"
      while IFS= read -r path; do
        [[ -n "$path" ]] && info "stale LaunchServices path: $path"
      done <<<"$STALE_LS_PATHS"
    fi
  else
    warn "lsregister command is unavailable; cannot check stale LaunchServices records"
  fi
fi

if [[ -x "$EXECUTABLE" ]]; then
  ok "input-method executable exists and is executable"
else
  fail "input-method executable is missing or not executable"
fi

if [[ -d "$CORE_RESOURCE_BUNDLE" ]]; then
  ok "SwiftPM core resource bundle is packaged"
else
  fail "SwiftPM core resource bundle is missing; bundled lexicon may not load"
fi

if [[ -d "$SETTINGS_UI_RESOURCE_BUNDLE" ]]; then
  ok "SwiftPM settings UI resource bundle is packaged"
else
  fail "SwiftPM settings UI resource bundle is missing; input-method settings may not load localized strings"
fi

if [[ -f "$ICON_RESOURCE" ]]; then
  ok "input-source icon resource is packaged"
else
  warn "input-source icon resource is missing"
fi

if command -v codesign >/dev/null 2>&1; then
  if codesign --verify --deep --strict "$BUNDLE_PATH" >/dev/null 2>&1; then
    ok "codesign verification passes"
  else
    fail "codesign verification failed"
  fi
  CODESIGN_SUMMARY="$(codesign -dv "$BUNDLE_PATH" 2>&1 | awk '/^(Identifier|Authority|TeamIdentifier)=/ {print}' | paste -sd ', ' -)"
  if [[ -n "$CODESIGN_SUMMARY" ]]; then
    info "codesign: $CODESIGN_SUMMARY"
  fi
else
  warn "codesign command is unavailable"
fi

if command -v spctl >/dev/null 2>&1; then
  SPCTL_OUTPUT="$(spctl --assess --type execute --verbose=4 "$BUNDLE_PATH" 2>&1)"
  SPCTL_STATUS=$?
  if (( SPCTL_STATUS == 0 )); then
    ok "Gatekeeper assessment accepts the installed bundle"
  else
    gatekeeper_rejected=1
    warn "Gatekeeper assessment rejects this local build: $SPCTL_OUTPUT"
    info "macOS 15 no longer supports spctl --add; for local Apple Development testing, generate a SystemPolicyRule profile with ./scripts/create-local-system-policy-profile.sh --open"
    info "Run this diagnostic with --logs to check for syspolicy GatekeeperPolicyScanError details"
  fi
else
  warn "spctl command is unavailable"
fi

echo
echo "Install state and rollback"

INSTALL_STATE_PATH="$(knowtype_install_state_path)"
BACKUP_ROOT="$(knowtype_backup_root_dir)"
if [[ -f "$INSTALL_STATE_PATH" ]]; then
  ok "install-state.json exists: $INSTALL_STATE_PATH"
  install_source="$(knowtype_read_install_state_field "source")"
  install_version="$(knowtype_read_install_state_field "version")"
  install_build="$(knowtype_read_install_state_field "build")"
  install_commit="$(knowtype_read_install_state_field "gitCommit")"
  install_tag="$(knowtype_read_install_state_field "gitTag")"
  install_backup="$(knowtype_read_install_state_field "previousBackupID")"
  [[ -n "$install_source" ]] && info "install source: $install_source"
  [[ -n "$install_version" || -n "$install_build" ]] && info "install-state version/build: ${install_version:-<unknown>} (${install_build:-<unknown>})"
  [[ -n "$install_commit" ]] && info "install-state commit: $install_commit"
  [[ -n "$install_tag" ]] && info "install-state tag: $install_tag"
  [[ -n "$install_backup" ]] && info "previous backup id: $install_backup"
else
  warn "install-state.json is missing; reinstall with ./scripts/install-inputmethod.sh to record version/source metadata"
fi

if [[ -d "$BACKUP_ROOT" ]]; then
  backup_count="$(knowtype_list_managed_backup_dirs | wc -l | tr -d ' ')"
  latest_backup="$(knowtype_latest_backup_dir)"
  ok "install backup root exists with $backup_count managed backup(s): $BACKUP_ROOT"
  if [[ -n "$latest_backup" ]]; then
    latest_manifest="$latest_backup/manifest.json"
    latest_version="$(knowtype_backup_manifest_field "$latest_manifest" "sourceVersion")"
    latest_build="$(knowtype_backup_manifest_field "$latest_manifest" "sourceBuild")"
    info "latest backup: $(basename "$latest_backup") version=${latest_version:-<unknown>} build=${latest_build:-<unknown>}"
    info "rollback command: ./scripts/rollback-inputmethod.sh --to $(basename "$latest_backup")"
  fi
else
  info "no install backups yet; the next overwrite install will create one by default"
fi

echo
echo "Compatibility PreferencePane"

PREFPANE_INFO_PLIST="$PREFPANE_PATH/Contents/Info.plist"
PREFPANE_EXECUTABLE="$PREFPANE_PATH/Contents/MacOS/KnowTypePreferencePane"
PREFPANE_LIBRARY="$PREFPANE_PATH/Contents/Frameworks/libKnowTypePreferencePane.dylib"
PREFPANE_SETTINGS_UI_RESOURCE_BUNDLE="$PREFPANE_PATH/Contents/Resources/KnowType_KnowTypeSettingsUI.bundle"

if [[ -d "$PREFPANE_PATH" ]]; then
  ok "KnowType.prefPane is installed"
  if [[ -f "$PREFPANE_INFO_PLIST" ]]; then
    ok "PreferencePane Info.plist exists"
    expect_plist_value "CFBundleIdentifier" "com.knowtype.preferencepane" "$PREFPANE_INFO_PLIST"
    expect_plist_value "CFBundleExecutable" "KnowTypePreferencePane" "$PREFPANE_INFO_PLIST"
    expect_plist_value "NSPrincipalClass" "KnowTypePreferencePane" "$PREFPANE_INFO_PLIST"
  else
    fail "PreferencePane Info.plist is missing"
  fi

  if [[ -x "$PREFPANE_EXECUTABLE" ]]; then
    ok "PreferencePane executable exists and is executable"
    if command -v otool >/dev/null 2>&1; then
      if otool -hv "$PREFPANE_EXECUTABLE" | grep -q "BUNDLE"; then
        ok "PreferencePane executable is a loadable bundle"
      else
        fail "PreferencePane executable is not an MH_BUNDLE; rebuild with scripts/build-preference-pane.sh"
      fi
    fi
  else
    fail "PreferencePane executable is missing or not executable"
  fi

  if [[ -f "$PREFPANE_LIBRARY" ]]; then
    ok "PreferencePane SwiftPM library is packaged"
  else
    fail "PreferencePane SwiftPM library is missing"
  fi

  if [[ -d "$PREFPANE_SETTINGS_UI_RESOURCE_BUNDLE" ]]; then
    ok "PreferencePane settings UI resource bundle is packaged"
  else
    warn "PreferencePane settings UI resource bundle is missing; rebuild with scripts/build-preference-pane.sh"
  fi

  if command -v codesign >/dev/null 2>&1; then
    if codesign --verify --deep --strict "$PREFPANE_PATH" >/dev/null 2>&1; then
      ok "PreferencePane codesign verification passes"
    else
      fail "PreferencePane codesign verification failed"
    fi
  fi
else
  warn "KnowType.prefPane is missing; this is optional because primary settings are opened from the input-method menu"
  STALE_PREFPANE_CACHE_PATHS="$(knowtype_preferencepane_cache_identity_paths)"
  if [[ -z "$STALE_PREFPANE_CACHE_PATHS" ]]; then
    ok "System Settings PreferencePane caches do not contain stale KnowType metadata"
  elif (( STRICT == 1 )); then
    fail "System Settings PreferencePane caches still contain stale KnowType prefPane metadata; run ./scripts/install-inputmethod.sh or ./scripts/uninstall-inputmethod.sh to refresh caches"
    while IFS= read -r cache_path; do
      [[ -n "$cache_path" ]] && info "stale System Settings cache: $cache_path"
    done <<<"$STALE_PREFPANE_CACHE_PATHS"
  else
    warn "System Settings PreferencePane caches still contain stale KnowType prefPane metadata"
    while IFS= read -r cache_path; do
      [[ -n "$cache_path" ]] && info "stale System Settings cache: $cache_path"
    done <<<"$STALE_PREFPANE_CACHE_PATHS"
  fi
fi

echo
echo "Text Input Source state"

TIS_OUTPUT="$(
  INPUTSOURCE_TOOL="$(knowtype_inputsource_tool "$ROOT_DIR")"
  "$INPUTSOURCE_TOOL" status --parent-id "$PARENT_ID" --mode-id "$MODE_ID"
)"

if [[ -z "$TIS_OUTPUT" ]]; then
  if (( REQUIRE_SELECTED == 1 )); then
    fail "could not query Text Input Source state"
  else
    warn "could not query Text Input Source state"
  fi
else
  while IFS='=' read -r key value; do
    case "$key" in
      current.id)
        if [[ -n "$value" ]]; then
          info "current input source in this diagnostic context: $value"
        else
          warn "current input source id is unavailable"
        fi
        ;;
      inputSource.found)
        [[ "$value" == "true" ]] && ok "KnowType input source is registered" || fail "KnowType input source is not registered"
        ;;
      inputSource.enabled)
        [[ "$value" == "true" ]] && ok "KnowType input source is enabled" || fail "KnowType input source is not enabled"
        ;;
      inputSource.selectCapable)
        [[ "$value" == "true" ]] && ok "KnowType input source is select-capable" || fail "KnowType input source is not select-capable"
        ;;
      inputSource.selected)
        if [[ "$value" == "true" ]]; then
          ok "KnowType input source is selected in this diagnostic context"
        elif (( REQUIRE_SELECTED == 1 )); then
          fail "KnowType input source is not selected in this diagnostic context; select KnowType from the target app's input menu and type a real probe"
        else
          warn "KnowType input source is not selected in this diagnostic context"
        fi
        ;;
      inputSource.type)
        [[ -n "$value" ]] && info "KnowType input source TIS type: $value"
        ;;
      inputSource.name)
        mode_name="$value"
        if [[ -z "$value" ]]; then
          warn "KnowType input source localized name is unavailable"
        elif [[ "$value" == "$MODE_ID" ]]; then
          warn "KnowType input source localized name is unresolved; reinstall after packaging InfoPlist.strings"
        else
          ok "KnowType input source localized name = $value"
        fi
        ;;
      inputSource.raw.count)
        if [[ "$value" =~ ^[0-9]+$ && "$value" -gt 1 ]]; then
          warn "TIS raw list reports $value KnowType input source records before de-duplication; logout/reboot may still clear stale session cache"
        else
          ok "TIS raw list reports one KnowType input source record"
        fi
        ;;
      inputSource.count)
        if [[ "$value" == "1" ]]; then
          ok "TIS reports exactly one active KnowType input source registration"
        else
          fail "TIS reports $value active KnowType input source registrations; run ./scripts/repair-inputmethod-selection.sh"
        fi
        ;;
      inputSource.singleSource)
        [[ "$value" == "true" ]] && fail "KnowType is using the parent-only input source model; rebuild with the visible .Hans mode model"
        ;;
      parent.found)
        if (( SINGLE_INPUT_SOURCE == 0 )); then
          [[ "$value" == "true" ]] && ok "KnowType non-selectable parent record is registered" || fail "KnowType non-selectable parent record is not registered"
        fi
        ;;
      parent.enabled)
        if (( SINGLE_INPUT_SOURCE == 1 )); then
          :
        elif [[ "$value" == "true" ]]; then
          ok "KnowType component-mode parent is enabled by TIS"
        elif (( STRICT == 1 )); then
          fail "KnowType component-mode parent is not enabled; TIS may reject selecting the visible mode with paramErr/-50"
        else
          warn "KnowType component-mode parent is not enabled; run ./scripts/repair-inputmethod-selection.sh if KnowType is missing from the input menu"
        fi
        ;;
      parent.selectCapable)
        parent_select_capable="$value"
        if (( SINGLE_INPUT_SOURCE == 0 )) && [[ "$value" != "true" ]]; then
          info "KnowType parent record is not directly selectable; macOS should select the visible input mode instead"
        fi
        ;;
      parent.type)
        if (( SINGLE_INPUT_SOURCE == 0 )); then
          [[ -n "$value" ]] && info "KnowType parent TIS type: $value"
        fi
        ;;
      parent.name)
        parent_name="$value"
        if (( SINGLE_INPUT_SOURCE == 0 )); then
          [[ -n "$value" ]] && info "KnowType parent localized name = $value"
        fi
        ;;
      mode.found)
        if (( SINGLE_INPUT_SOURCE == 0 )); then
          [[ "$value" == "true" ]] && ok "KnowType input mode is registered" || fail "KnowType input mode is not registered"
        fi
        ;;
      mode.enabled)
        if (( SINGLE_INPUT_SOURCE == 0 )); then
          [[ "$value" == "true" ]] && ok "KnowType input mode is enabled" || fail "KnowType input mode is not enabled"
        fi
        ;;
      mode.selectCapable)
        if (( SINGLE_INPUT_SOURCE == 0 )); then
          [[ "$value" == "true" ]] && ok "KnowType input mode is select-capable" || fail "KnowType input mode is not select-capable"
        fi
        ;;
      mode.type)
        [[ -n "$value" ]] && info "KnowType mode TIS type: $value"
        ;;
      mode.selected)
        if (( SINGLE_INPUT_SOURCE == 1 )); then
          continue
        fi
        if [[ "$value" == "true" ]]; then
          ok "KnowType input mode is selected in this diagnostic context"
        elif (( REQUIRE_SELECTED == 1 )); then
          fail "KnowType input mode is not selected in this diagnostic context; select KnowType from the target app's input menu and type a real probe"
        else
          warn "KnowType input mode is not selected in this diagnostic context"
        fi
        ;;
      mode.name)
        if (( SINGLE_INPUT_SOURCE == 1 )); then
          continue
        fi
        mode_name="$value"
        if [[ -z "$value" ]]; then
          warn "KnowType input mode localized name is unavailable"
        elif [[ "$value" == "$MODE_ID" ]]; then
          warn "KnowType input mode localized name is unresolved; reinstall after packaging InfoPlist.strings"
        else
          ok "KnowType input mode localized name = $value"
        fi
        ;;
      mode.count)
        if [[ "$value" =~ ^[0-9]+$ && "$value" -gt 1 ]]; then
          warn "TIS reports $value KnowType input mode registrations; log out or reboot if the input menu shows stale duplicates"
        fi
        ;;
      user.visible.mode.count)
        if [[ "$value" == "1" ]]; then
          ok "TIS reports exactly one user-selectable KnowType mode"
        else
          fail "TIS reports $value user-selectable KnowType modes; run ./scripts/repair-inputmethod-selection.sh and clear stale LaunchServices records"
        fi
        ;;
      active.mode.count)
        if [[ "$value" == "1" ]]; then
          ok "TIS reports exactly one active KnowType mode registration"
        else
          fail "TIS reports $value active KnowType mode registrations; run ./scripts/repair-inputmethod-selection.sh"
        fi
        ;;
      active.mode.raw.count)
        if [[ "$value" =~ ^[0-9]+$ && "$value" -gt 1 ]]; then
          warn "TIS raw list reports $value active KnowType mode records before de-duplication; mature IMK installers de-duplicate TIS records by input-source id, but logout/reboot may still clear stale session cache"
        else
          ok "TIS raw list reports one active KnowType mode record"
        fi
        ;;
      legacy.mode.count)
        if [[ "$value" =~ ^[0-9]+$ && "$value" -gt 0 ]]; then
          warn "TIS still reports $value legacy KnowType mode registration(s); logout or reboot may be needed after purge"
        else
          ok "TIS reports no legacy KnowType mode registrations"
        fi
        ;;
      preference.selected.mode)
        if [[ -n "$value" ]]; then
          info "HIToolbox selected input-mode preference: $value"
        else
          warn "HIToolbox selected input-mode preference is unavailable"
        fi
        ;;
      preference.selected.knowtype)
        hitoolbox_selected_knowtype="$value"
        if [[ "$value" == "true" ]]; then
          ok "HIToolbox selected preference is KnowType"
        else
          warn "HIToolbox selected preference is not KnowType; choose KnowType from the input menu/System Settings before typing"
          info "If macOS shows an authorization prompt to allow 知键/KnowType as an input method, click Allow; until it is allowed, the menu can list KnowType while normal switching still falls back to another source"
        fi
        ;;
      preference.selected.parent.knowtype)
        if (( SINGLE_INPUT_SOURCE == 1 )); then
          continue
        fi
        if [[ "$value" == "true" ]]; then
          if (( STRICT == 1 )); then
            fail "HIToolbox selected preferences still contain the non-selectable KnowType parent row; run ./scripts/repair-inputmethod-selection.sh"
          else
            warn "HIToolbox selected preferences still contain the non-selectable KnowType parent row"
          fi
        fi
        ;;
      preference.enabled.knowtype)
        hitoolbox_enabled_knowtype="$value"
        if [[ "$value" == "true" ]]; then
          ok "HIToolbox enabled preferences include KnowType"
        elif (( STRICT == 1 )); then
          fail "HIToolbox enabled preferences do not include active KnowType input source; run ./scripts/repair-inputmethod-selection.sh"
        else
          warn "HIToolbox enabled preferences do not include KnowType; relying on TIS enabled state and third-party input-source preferences"
        fi
        ;;
      preference.enabled.legacy.knowtype)
        if [[ "$value" == "true" ]]; then
          if (( STRICT == 1 )); then
            fail "HIToolbox enabled preferences still include a legacy KnowType mode; run ./scripts/repair-inputmethod-selection.sh"
          else
            warn "HIToolbox enabled preferences still include a legacy KnowType mode"
          fi
        else
          ok "HIToolbox enabled preferences do not include legacy KnowType modes"
        fi
        ;;
      preference.enabled.parent.knowtype)
        if (( SINGLE_INPUT_SOURCE == 1 )); then
          :
        elif [[ "$value" == "true" ]]; then
          ok "HIToolbox enabled preferences include the component-mode KnowType parent"
        elif (( STRICT == 1 )); then
          fail "HIToolbox enabled preferences are missing the component-mode KnowType parent; run ./scripts/repair-inputmethod-selection.sh"
        else
          warn "HIToolbox enabled preferences are missing the component-mode KnowType parent"
        fi
        ;;
      preference.thirdparty.enabled.knowtype)
        if [[ "$value" == "true" ]]; then
          ok "Third-party input source preferences include KnowType"
        elif (( STRICT == 1 )); then
          fail "Third-party input source preferences do not include active KnowType input source; enable KnowType in System Settings > Keyboard > Input Sources"
        else
          warn "Third-party input source preferences do not include KnowType; enable KnowType in System Settings > Keyboard > Input Sources"
        fi
        ;;
      preference.thirdparty.enabled.legacy.knowtype)
        thirdparty_legacy_knowtype="$value"
        if [[ "$value" == "true" ]]; then
          if (( STRICT == 1 )); then
            fail "Third-party input source preferences still point at a legacy KnowType mode; remove the stale KnowType input source in System Settings and add the current one"
          else
            warn "Third-party input source preferences still point at a legacy KnowType mode"
          fi
        else
          ok "Third-party input source preferences do not include legacy KnowType modes"
        fi
        ;;
      preference.thirdparty.enabled.parent.knowtype)
        if (( SINGLE_INPUT_SOURCE == 1 )); then
          :
        elif [[ "$value" == "true" ]]; then
          ok "Third-party input source preferences include the component-mode KnowType parent"
        elif (( STRICT == 1 )); then
          fail "Third-party input source preferences are missing the component-mode KnowType parent; run ./scripts/repair-inputmethod-selection.sh"
        else
          warn "Third-party input source preferences are missing the component-mode KnowType parent"
        fi
        ;;
      preference.history.knowtype)
        if [[ "$value" == "true" ]]; then
          ok "HIToolbox input-source history includes KnowType"
        else
          warn "HIToolbox input-source history does not include KnowType yet; macOS usually updates history after real app selection or typing"
        fi
        ;;
      preference.history.parent.knowtype)
        if (( SINGLE_INPUT_SOURCE == 1 )); then
          continue
        fi
        if [[ "$value" == "true" ]]; then
          if (( STRICT == 1 )); then
            fail "HIToolbox input-source history still contains the non-selectable KnowType parent row; run ./scripts/repair-inputmethod-selection.sh"
          else
            warn "HIToolbox input-source history still contains the non-selectable KnowType parent row"
          fi
        fi
        ;;
      preference.history.index.knowtype)
        if [[ "$value" == "0" || "$value" == "1" ]]; then
          ok "HIToolbox input-source history has KnowType in Ctrl+Space range"
        elif [[ "$value" =~ ^[0-9]+$ ]]; then
          if (( STRICT == 1 )); then
            fail "HIToolbox input-source history places KnowType at index $value; Ctrl+Space normally toggles only the current and previous sources"
          else
            warn "HIToolbox input-source history places KnowType at index $value; Ctrl+Space may skip it"
          fi
        else
          warn "HIToolbox input-source history position for KnowType is unavailable"
        fi
        ;;
    esac
  done <<<"$TIS_OUTPUT"
fi

INPUTSOURCES_PREF="$HOME/Library/Preferences/com.apple.inputsources.plist"
if [[ -f "$INPUTSOURCES_PREF" ]] && command -v xattr >/dev/null 2>&1; then
  inputsources_xattrs="$(xattr -l "$INPUTSOURCES_PREF" 2>/dev/null || true)"
  if grep -q "com.apple.macl" <<<"$inputsources_xattrs"; then
    if [[ "$thirdparty_legacy_knowtype" == "true" ]]; then
      if (( STRICT == 1 )); then
        fail "com.apple.inputsources.plist has com.apple.macl while it still contains legacy KnowType .Mode; grant Full Disk Access to Terminal/Codex or log out/reboot before cleanup"
      else
        warn "com.apple.inputsources.plist has com.apple.macl while it still contains legacy KnowType .Mode"
      fi
    else
      info "com.apple.inputsources.plist has com.apple.macl"
    fi
  fi
  if grep -q "com.apple.quarantine" <<<"$inputsources_xattrs"; then
    if [[ "$thirdparty_legacy_knowtype" == "true" ]]; then
      if (( STRICT == 1 )); then
        fail "com.apple.inputsources.plist has com.apple.quarantine while it still contains legacy KnowType .Mode; grant Full Disk Access to Terminal/Codex or log out/reboot before cleanup"
      else
        warn "com.apple.inputsources.plist has com.apple.quarantine while it still contains legacy KnowType .Mode"
      fi
    else
      info "com.apple.inputsources.plist has com.apple.quarantine"
    fi
  fi
fi

if (( gatekeeper_rejected == 1 )) &&
   [[ "$hitoolbox_enabled_knowtype" == "true" ]] &&
   [[ "$hitoolbox_selected_knowtype" != "true" ]]; then
  warn "KnowType is enabled but not selected while Gatekeeper rejects the bundle; local Apple Development builds may need explicit user allowance or a Developer ID build before the input menu can select them reliably"
fi

if pgrep -x KnowTypeInputMethodApp >/dev/null 2>&1; then
  ok "KnowTypeInputMethodApp process is running"
else
  warn "KnowTypeInputMethodApp process is not running; it may start after selecting/using the input source"
fi

echo
echo "KnowType user data paths"

APP_SUPPORT="$HOME/Library/Application Support/KnowType"
PROVIDER_JSON_CANONICAL="$APP_SUPPORT/providers.v2.json"
PROVIDER_JSON_LEGACY="$APP_SUPPORT/providers.json"
PROVIDER_JSON_SNAPSHOT="$APP_SUPPORT/providers.legacy.json"
PROVIDER_JSON="$PROVIDER_JSON_CANONICAL"
HISTORY_JSON="$APP_SUPPORT/user-selection-history.json"
LEXICON_DIR="$APP_SUPPORT/Lexicons"
AI_PROFILE_JSON="$APP_SUPPORT/AI/lexical-profile.json"
ACCEPTED_HISTORY_JSONL="$APP_SUPPORT/AI/accepted-ai-learning.jsonl"
ACCEPTED_SUMMARY_JSON="$APP_SUPPORT/AI/accepted-ai-summary.json"
ACCEPTED_MIRROR_MD="$HOME/.knowtype/ACCEPTED_AI_LEARNING.md"
ACCEPTED_FEEDBACK_JSONL="$APP_SUPPORT/AI/accepted-ai-feedback.jsonl"
ACCEPTED_FEEDBACK_SUMMARY_JSON="$APP_SUPPORT/AI/accepted-ai-feedback-summary.json"
ACCEPTED_FEEDBACK_MIRROR_MD="$HOME/.knowtype/ACCEPTED_AI_FEEDBACK.md"
ENV_MD="$HOME/.knowtype/ENV.md"
CORRECTION_MD="$HOME/.knowtype/CORRECTION.md"
LEXICAL_PROFILE_MD="$HOME/.knowtype/LEXICAL_PROFILE.md"

provider_storage_state="$({
  KNOWTYPE_PROVIDER_CANONICAL="$PROVIDER_JSON_CANONICAL" \
  KNOWTYPE_PROVIDER_LEGACY="$PROVIDER_JSON_LEGACY" \
  KNOWTYPE_PROVIDER_SNAPSHOT="$PROVIDER_JSON_SNAPSHOT" \
  "$KNOWTYPE_PYTHON3" - <<'PY'
import json
import os
from pathlib import Path

canonical = Path(os.environ["KNOWTYPE_PROVIDER_CANONICAL"])
legacy = Path(os.environ["KNOWTYPE_PROVIDER_LEGACY"])
snapshot = Path(os.environ["KNOWTYPE_PROVIDER_SNAPSHOT"])
payload = None
try:
    with legacy.open(encoding="utf-8") as handle:
        payload = json.load(handle)
except Exception:
    pass
tombstone = (
    isinstance(payload, dict)
    and payload.get("schemaVersion") == "migrated-to-providers.v2.json"
    and payload.get("canonicalFile") == "providers.v2.json"
)
expects_canonical = (
    bool(payload.get("canonicalExpected"))
    if isinstance(payload, dict) and "canonicalExpected" in payload
    else snapshot.is_file()
)
legacy_configuration = legacy.is_file() and not tombstone
if canonical.is_file():
    print("legacy-diverged" if legacy_configuration else "canonical")
elif legacy_configuration:
    print("legacy-unmigrated")
elif tombstone and expects_canonical:
    print("canonical-missing")
elif tombstone:
    print("tombstone")
else:
    print("missing")
PY
} 2>/dev/null)"

case "$provider_storage_state" in
  canonical)
    ok "canonical provider profile file exists: $PROVIDER_JSON_CANONICAL"
    ;;
  legacy-diverged)
    warn "canonical provider profiles are active, but providers.json was rewritten by a legacy Settings process; both payloads were preserved, so close legacy Settings and resolve the conflict before reinstalling"
    ;;
  legacy-unmigrated)
    PROVIDER_JSON="$PROVIDER_JSON_LEGACY"
    warn "legacy provider profiles require migration before Settings can save changes; rerun the installer"
    ;;
  canonical-missing)
    if (( STRICT == 1 )); then
      fail "canonical providers.v2.json is missing after migration; restore from backup or rerun a verified installer"
    else
      warn "canonical providers.v2.json is missing after migration"
    fi
    ;;
  tombstone)
    info "provider profile storage is initialized; no canonical profile file has been created yet"
    ;;
  *)
    warn "provider profile file is missing; runtime will use seeded local defaults"
    ;;
esac

if [[ -f "$HISTORY_JSON" ]]; then
  ok "local candidate history file exists"
else
  info "local candidate history file has not been created yet"
fi

if [[ -d "$LEXICON_DIR" ]]; then
  LEXICON_COUNT="$(find "$LEXICON_DIR" -maxdepth 1 -type f \( -name '*.json' -o -name '*.tsv' \) | wc -l | tr -d ' ')"
  ok "local lexicon directory exists with $LEXICON_COUNT JSON/TSV resource(s)"
else
  warn "local lexicon directory is missing; bundled seed lexicon will be used"
fi

if [[ -f "$PROVIDER_JSON" ]]; then
  default_provider_summary="$(
    KNOWTYPE_PROVIDER_JSON="$PROVIDER_JSON" \
    PYTHONPATH="$SCRIPTS_DIR/lib${PYTHONPATH:+:$PYTHONPATH}" \
    "$KNOWTYPE_PYTHON3" - <<'PY'
import json
import os
from provider_endpoint_summary import privacy_safe_endpoint_summary
try:
    with open(os.environ["KNOWTYPE_PROVIDER_JSON"], encoding="utf-8") as handle:
        profiles = json.load(handle).get("profiles", [])
    profile = next((item for item in profiles if item.get("isDefault")), None)
    if profile:
        endpoint = privacy_safe_endpoint_summary(profile.get("baseURL"))
        print(f"{profile.get('displayName', '<unnamed>')} · {profile.get('kind', '<kind>')} · {profile.get('model', '<model>')} · {endpoint}")
except Exception:
    pass
PY
  )"
  if [[ -n "$default_provider_summary" ]]; then
    ok "default AI provider: $default_provider_summary"
  else
    warn "provider profile file exists but no default provider is configured"
  fi
fi

for profile_path in "$AI_PROFILE_JSON" "$ENV_MD" "$CORRECTION_MD" "$LEXICAL_PROFILE_MD"; do
  if [[ -f "$profile_path" ]]; then
    info "user data file exists: $profile_path"
  else
    info "user data file has not been created yet: $profile_path"
  fi
done

accepted_learning_summary="$(
  KNOWTYPE_ACCEPTED_HISTORY="$ACCEPTED_HISTORY_JSONL" \
  KNOWTYPE_ACCEPTED_SUMMARY="$ACCEPTED_SUMMARY_JSON" \
  KNOWTYPE_ACCEPTED_MIRROR="$ACCEPTED_MIRROR_MD" \
  KNOWTYPE_ACCEPTED_FEEDBACK="$ACCEPTED_FEEDBACK_JSONL" \
  KNOWTYPE_ACCEPTED_FEEDBACK_SUMMARY="$ACCEPTED_FEEDBACK_SUMMARY_JSON" \
  KNOWTYPE_ACCEPTED_FEEDBACK_MIRROR="$ACCEPTED_FEEDBACK_MIRROR_MD" \
  KNOWTYPE_LEXICAL_PROFILE="$LEXICAL_PROFILE_MD" \
  "$KNOWTYPE_PYTHON3" - <<'PY'
import hashlib
import json
import os
from pathlib import Path

history = Path(os.environ["KNOWTYPE_ACCEPTED_HISTORY"])
summary_path = Path(os.environ["KNOWTYPE_ACCEPTED_SUMMARY"])
mirror = Path(os.environ["KNOWTYPE_ACCEPTED_MIRROR"])
feedback_history = Path(os.environ["KNOWTYPE_ACCEPTED_FEEDBACK"])
feedback_summary_path = Path(os.environ["KNOWTYPE_ACCEPTED_FEEDBACK_SUMMARY"])
feedback_mirror = Path(os.environ["KNOWTYPE_ACCEPTED_FEEDBACK_MIRROR"])
lexical = Path(os.environ["KNOWTYPE_LEXICAL_PROFILE"])

def load_jsonl(path):
    rows = []
    invalid = 0
    read_failed = False
    if not path.is_file():
        return rows, invalid, read_failed
    try:
        with path.open(encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    rows.append(json.loads(line))
                except Exception:
                    invalid += 1
    except Exception:
        read_failed = True
    return rows, invalid, read_failed

records, invalid, history_read_failed = load_jsonl(history)
feedback_records, feedback_invalid, feedback_read_failed = load_jsonl(feedback_history)

def feedback_hash_fragment(record):
    return "|".join([
        str(record.get("acceptID", "")),
        str(record.get("acceptedTextHash", "")),
        ",".join(f"{item.get('location', '')}:{item.get('length', '')}" for item in record.get("deletedRanges", [])),
        "\u001f".join(str(item) for item in record.get("deletedTexts", [])),
        str(record.get("replacementText", "")),
        f"{float(record.get('deletedRatio', 0)):.4f}",
        str(record.get("strength", "")),
    ])

history_hash = ""
if records:
    history_hash = hashlib.sha256("\n".join(str(record.get("textHash", "")) for record in records).encode("utf-8")).hexdigest()[:8]

summary = None
summary_exists = summary_path.is_file()
if summary_exists:
    try:
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
    except Exception:
        summary = None
if not isinstance(summary, dict):
    summary = None

if records:
    current = bool(summary) and summary.get("acceptedCount") == len(records) and summary.get("historyHash", "").startswith(history_hash)
else:
    current = summary is None and not summary_exists

feedback_hash = ""
if feedback_records:
    joined = "\n".join(feedback_hash_fragment(record) for record in feedback_records)
    feedback_hash = hashlib.sha256(joined.encode("utf-8")).hexdigest()[:8]

feedback_summary = None
feedback_summary_exists = feedback_summary_path.is_file()
if feedback_summary_exists:
    try:
        feedback_summary = json.loads(feedback_summary_path.read_text(encoding="utf-8"))
    except Exception:
        feedback_summary = None
if not isinstance(feedback_summary, dict):
    feedback_summary = None

if feedback_records:
    feedback_current = bool(feedback_summary) and feedback_summary.get("feedbackCount") == len(feedback_records) and feedback_summary.get("historyHash", "").startswith(feedback_hash)
else:
    feedback_current = feedback_summary is None and not feedback_summary_exists

try:
    lexical_has_accepted = "accepted-ai-summary:" in lexical.read_text(encoding="utf-8")
except Exception:
    lexical_has_accepted = False

print(f"records={len(records)}")
print(f"historyHash={history_hash or 'none'}")
print(f"summaryExists={'yes' if summary_exists else 'no'}")
print(f"summaryCurrent={'yes' if current else 'no'}")
print(f"acceptedCount={summary.get('acceptedCount', 0) if summary else 0}")
print(f"termCount={len(summary.get('termProfile', [])) if summary else 0}")
print(f"recentCommitCount={len(summary.get('recentAcceptedCommits', [])) if summary else 0}")
print(f"lexicalInjected={'yes' if lexical_has_accepted else 'no'}")
print(f"mirrorExists={'yes' if mirror.is_file() else 'no'}")
print(f"invalidLines={invalid}")
print(f"historyReadFailed={'yes' if history_read_failed else 'no'}")
print(f"feedbackRecords={len(feedback_records)}")
print(f"feedbackHash={feedback_hash or 'none'}")
print(f"feedbackSummaryExists={'yes' if feedback_summary_exists else 'no'}")
print(f"feedbackSummaryCurrent={'yes' if feedback_current else 'no'}")
print(f"feedbackStrongCount={feedback_summary.get('strongCount', 0) if feedback_summary else 0}")
print(f"feedbackAvoidTermCount={len(feedback_summary.get('avoidTerms', [])) if feedback_summary else 0}")
print(f"feedbackMirrorExists={'yes' if feedback_mirror.is_file() else 'no'}")
print(f"feedbackInvalidLines={feedback_invalid}")
print(f"feedbackReadFailed={'yes' if feedback_read_failed else 'no'}")
PY
)"

accepted_records="$(awk -F= '/^records=/{print $2}' <<<"$accepted_learning_summary")"
accepted_history_hash="$(awk -F= '/^historyHash=/{print $2}' <<<"$accepted_learning_summary")"
accepted_summary_exists="$(awk -F= '/^summaryExists=/{print $2}' <<<"$accepted_learning_summary")"
accepted_summary_current="$(awk -F= '/^summaryCurrent=/{print $2}' <<<"$accepted_learning_summary")"
accepted_terms="$(awk -F= '/^termCount=/{print $2}' <<<"$accepted_learning_summary")"
accepted_commits="$(awk -F= '/^recentCommitCount=/{print $2}' <<<"$accepted_learning_summary")"
accepted_lexical_injected="$(awk -F= '/^lexicalInjected=/{print $2}' <<<"$accepted_learning_summary")"
accepted_mirror_exists="$(awk -F= '/^mirrorExists=/{print $2}' <<<"$accepted_learning_summary")"
accepted_invalid_lines="$(awk -F= '/^invalidLines=/{print $2}' <<<"$accepted_learning_summary")"
accepted_history_read_failed="$(awk -F= '/^historyReadFailed=/{print $2}' <<<"$accepted_learning_summary")"
accepted_feedback_records="$(awk -F= '/^feedbackRecords=/{print $2}' <<<"$accepted_learning_summary")"
accepted_feedback_hash="$(awk -F= '/^feedbackHash=/{print $2}' <<<"$accepted_learning_summary")"
accepted_feedback_summary_exists="$(awk -F= '/^feedbackSummaryExists=/{print $2}' <<<"$accepted_learning_summary")"
accepted_feedback_summary_current="$(awk -F= '/^feedbackSummaryCurrent=/{print $2}' <<<"$accepted_learning_summary")"
accepted_feedback_strong_count="$(awk -F= '/^feedbackStrongCount=/{print $2}' <<<"$accepted_learning_summary")"
accepted_feedback_avoid_terms="$(awk -F= '/^feedbackAvoidTermCount=/{print $2}' <<<"$accepted_learning_summary")"
accepted_feedback_mirror_exists="$(awk -F= '/^feedbackMirrorExists=/{print $2}' <<<"$accepted_learning_summary")"
accepted_feedback_invalid_lines="$(awk -F= '/^feedbackInvalidLines=/{print $2}' <<<"$accepted_learning_summary")"
accepted_feedback_read_failed="$(awk -F= '/^feedbackReadFailed=/{print $2}' <<<"$accepted_learning_summary")"

info "accepted AI learning: records=$accepted_records hash=$accepted_history_hash summary=$accepted_summary_exists terms=$accepted_terms commits=$accepted_commits lexicalInjected=$accepted_lexical_injected mirror=$accepted_mirror_exists"
info "accepted AI feedback: records=$accepted_feedback_records hash=$accepted_feedback_hash summary=$accepted_feedback_summary_exists strong=$accepted_feedback_strong_count avoidTerms=$accepted_feedback_avoid_terms mirror=$accepted_feedback_mirror_exists"
if [[ "$accepted_summary_current" != "yes" ]]; then
  warn "accepted AI learning summary is stale or missing; run ./scripts/accepted-learning.sh rebuild"
fi
if [[ "$accepted_feedback_summary_current" != "yes" ]]; then
  warn "accepted AI feedback summary is stale or missing; run ./scripts/accepted-learning.sh rebuild"
fi
if [[ "${accepted_invalid_lines:-0}" != "0" ]]; then
  warn "accepted AI learning history has $accepted_invalid_lines invalid line(s)"
fi
if [[ "$accepted_history_read_failed" == "yes" ]]; then
  warn "accepted AI learning history could not be read"
fi
if [[ "${accepted_feedback_invalid_lines:-0}" != "0" ]]; then
  warn "accepted AI feedback history has $accepted_feedback_invalid_lines invalid line(s)"
fi
if [[ "$accepted_feedback_read_failed" == "yes" ]]; then
  warn "accepted AI feedback history could not be read"
fi

if (( SHOW_LOGS == 1 )); then
  echo
  echo "Recent system log hints"
  if command -v /usr/bin/log >/dev/null 2>&1; then
    LOG_PREDICATE='subsystem == "com.knowtype.inputmethod.KnowType" OR process == "KnowTypeInputMethodApp" OR process == "TextInputMenuAgent" OR process == "TextInputSwitcher" OR eventMessage CONTAINS[c] "GatekeeperPolicyScanError" OR eventMessage CONTAINS[c] "user-preference-write com.apple.inputsources" OR eventMessage CONTAINS[c] "InputMethodKit"'
    if LOG_OUTPUT="$(/usr/bin/log show --style compact --last "$LOG_LOOKBACK" --predicate "$LOG_PREDICATE" 2>/dev/null | tail -80)"; then
      if [[ -n "$LOG_OUTPUT" ]]; then
        printf '%s\n' "$LOG_OUTPUT"
      else
        info "No recent KnowType, Gatekeeper, or input-source sandbox log hints found in the last $LOG_LOOKBACK"
      fi
    else
      warn "could not read unified logs for the last $LOG_LOOKBACK"
    fi
  else
    warn "log command is unavailable"
  fi
fi

echo
echo "Summary: $failures failure(s), $warnings warning(s)"

if (( failures > 0 && (STRICT == 1 || REQUIRE_SELECTED == 1) )); then
  exit 1
fi
