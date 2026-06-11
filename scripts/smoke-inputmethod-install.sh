#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
source "$ROOT_DIR/scripts/lib/inputsource-ids.sh"
WITH_PREFPANE=0

usage() {
  cat <<'EOF'
Usage: scripts/smoke-inputmethod-install.sh [--with-prefpane]

Runs deterministic install/profile smoke checks without installing KnowType,
selecting an input source, or installing a configuration profile.

Options:
  --with-prefpane  Also build and validate the compatibility KnowType.prefPane.
  -h, --help  Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
    --with-prefpane)
      WITH_PREFPANE=1
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

die() {
  echo "error: $*" >&2
  exit 1
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$actual" != "$expected" ]]; then
    die "$label expected '$expected' but found '$actual'"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    die "$label did not contain '$needle'"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    die "$label unexpectedly contained '$needle'"
  fi
}

assert_file() {
  local path="$1"
  [[ -f "$path" ]] || die "missing file: $path"
}

assert_file_any() {
  local label="$1"
  shift
  local path
  for path in "$@"; do
    if [[ -f "$path" ]]; then
      return 0
    fi
  done
  die "missing file for $label; checked: $*"
}

assert_dir() {
  local path="$1"
  [[ -d "$path" ]] || die "missing directory: $path"
}

plist_read() {
  local key_path="$1"
  local plist_path="$2"
  "$PLIST_BUDDY" -c "Print $key_path" "$plist_path"
}

codesign_value() {
  local key="$1"
  local details="$2"
  printf '%s\n' "$details" |
    awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }'
}

codesign_requirement() {
  local bundle_path="$1"
  local output
  local requirement
  output="$(codesign -dr - "$bundle_path" 2>&1 || true)"
  requirement="$(
    printf '%s\n' "$output" |
      sed -n 's/^designated => //p' |
      head -n 1
  )"
  if [[ -z "$requirement" ]]; then
    requirement="$(
      printf '%s\n' "$output" |
        sed -n 's/^# designated => //p' |
        head -n 1
    )"
  fi
  if [[ -z "$requirement" ]]; then
    local details
    local cd_hash
    details="$(codesign -dvvv "$bundle_path" 2>&1 || true)"
    cd_hash="$(codesign_value "CDHash" "$details")"
    if [[ -n "$cd_hash" ]]; then
      requirement="cdhash H\"$cd_hash\""
    fi
  fi
  printf '%s' "$requirement"
}

if [[ ! -x "$PLIST_BUDDY" ]]; then
  die "PlistBuddy is unavailable at $PLIST_BUDDY"
fi

while IFS= read -r script_path; do
  bash -n "$script_path"
done < <(find "$ROOT_DIR/scripts" -type f -name '*.sh' | sort)

install_script_contents="$(cat "$ROOT_DIR/scripts/install-inputmethod.sh")"
rollback_script_contents="$(cat "$ROOT_DIR/scripts/rollback-inputmethod.sh")"
repair_script_contents="$(cat "$ROOT_DIR/scripts/repair-inputmethod-selection.sh")"

assert_contains "$install_script_contents" "purge_legacy_best_effort" "install script"
assert_contains "$install_script_contents" "bootstrap_input_source_best_effort" "install script"
assert_contains "$install_script_contents" '"$tool" purge-legacy' "install script"
assert_contains "$install_script_contents" '"$tool" bootstrap' "install script"
assert_contains "$install_script_contents" "launching the input method host" "install script"
assert_contains "$install_script_contents" "process shutdown can flush Rime user data" "install script"
assert_contains "$install_script_contents" "knowtype_input_method_host_is_running" "install script"
assert_contains "$install_script_contents" "ps -axo command=" "install script"
assert_contains "$install_script_contents" '*/KnowTypeInputMethodApp\ *' "install script"
assert_not_contains "$install_script_contents" '${command%% *}' "install script"
assert_not_contains "$install_script_contents" '"$INSTALLED_EXECUTABLE" --knowtype-install-activate' "install script"
assert_not_contains "$install_script_contents" '"$INSTALLED_EXECUTABLE" --knowtype-purge-legacy' "install script"
assert_not_contains "$install_script_contents" "killall KnowTypeInputMethodApp" "install script"
assert_not_contains "$install_script_contents" "pgrep -x KnowTypeInputMethodApp" "install script"
assert_not_contains "$install_script_contents" 'open -g "$TARGET_PATH"' "install script"

assert_contains "$rollback_script_contents" '"$inputsource_tool" purge-legacy' "rollback script"
assert_contains "$rollback_script_contents" '"$inputsource_tool" bootstrap' "rollback script"
assert_contains "$rollback_script_contents" "process shutdown can flush Rime user data" "rollback script"
assert_contains "$rollback_script_contents" "knowtype_input_method_host_is_running" "rollback script"
assert_contains "$rollback_script_contents" "ps -axo command=" "rollback script"
assert_contains "$rollback_script_contents" '*/KnowTypeInputMethodApp\ *' "rollback script"
assert_not_contains "$rollback_script_contents" '${command%% *}' "rollback script"
assert_not_contains "$rollback_script_contents" 'KnowTypeInputMethodApp" --knowtype-purge-legacy' "rollback script"
assert_not_contains "$rollback_script_contents" "killall KnowTypeInputMethodApp" "rollback script"
assert_not_contains "$rollback_script_contents" "pgrep -x KnowTypeInputMethodApp" "rollback script"
assert_not_contains "$rollback_script_contents" 'open -g "$target_path"' "rollback script"

assert_contains "$repair_script_contents" '"$INPUTSOURCE_TOOL" purge-legacy' "repair script"
assert_contains "$repair_script_contents" '"$INPUTSOURCE_TOOL" bootstrap' "repair script"
assert_not_contains "$repair_script_contents" '"$BUNDLE_EXECUTABLE" --knowtype-install-activate' "repair script"
assert_not_contains "$repair_script_contents" '"$BUNDLE_EXECUTABLE" --knowtype-purge-legacy' "repair script"
assert_not_contains "$repair_script_contents" "killall KnowTypeInputMethodApp" "repair script"
assert_not_contains "$repair_script_contents" 'open -g "$BUNDLE_PATH"' "repair script"

help_scripts=(
  "$ROOT_DIR/scripts/accept-inputmethod-local.sh"
  "$ROOT_DIR/scripts/build-inputmethod-bundle.sh"
  "$ROOT_DIR/scripts/build-preference-pane.sh"
  "$ROOT_DIR/scripts/create-local-system-policy-profile.sh"
  "$ROOT_DIR/scripts/diagnose-inputmethod.sh"
  "$ROOT_DIR/scripts/install-inputmethod.sh"
  "$ROOT_DIR/scripts/install-lexicon-pack.sh"
  "$ROOT_DIR/scripts/package-dmg.sh"
  "$ROOT_DIR/scripts/package-release.sh"
  "$ROOT_DIR/scripts/perf-input-hotpath.sh"
  "$ROOT_DIR/scripts/repair-inputmethod-selection.sh"
  "$ROOT_DIR/scripts/rollback-inputmethod.sh"
  "$ROOT_DIR/scripts/select-inputmethod.sh"
  "$ROOT_DIR/scripts/smoke-inputmethod-install.sh"
  "$ROOT_DIR/scripts/uninstall-inputmethod.sh"
)

for script_path in "${help_scripts[@]}"; do
  "$script_path" --help >/dev/null
done

source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"
declare -F knowtype_inputsource_tool >/dev/null ||
  die "scripts/lib/inputsource-tool.sh did not load knowtype_inputsource_tool"
source "$ROOT_DIR/scripts/lib/inputmethod-installation.sh"
declare -F knowtype_find_local_inputmethod_bundle_paths >/dev/null ||
  die "scripts/lib/inputmethod-installation.sh did not load duplicate discovery helpers"
declare -F knowtype_remove_local_inputmethod_bundle_if_safe >/dev/null ||
  die "scripts/lib/inputmethod-installation.sh did not load safe removal helpers"
declare -F knowtype_clean_preferencepane_caches >/dev/null ||
  die "scripts/lib/inputmethod-installation.sh did not load PreferencePane cache cleanup helpers"

manifest_smoke_root="$(mktemp -d "${TMPDIR:-/tmp}/knowtype-manifest-smoke.XXXXXX")"
mkdir -p "$manifest_smoke_root/one" "$manifest_smoke_root/two"
printf '{}\n' >"$manifest_smoke_root/one/release-manifest.json"
printf '{}\n' >"$manifest_smoke_root/two/release-manifest.json"
if manifest_error="$(knowtype_discover_release_manifest "$manifest_smoke_root/release.zip" "$manifest_smoke_root" 2>&1 >/dev/null)"; then
  die "release manifest discovery accepted multiple manifests"
fi
assert_contains "$manifest_error" "exactly one release-manifest.json" "release manifest ambiguity output"
rm -rf "$manifest_smoke_root/two"
manifest_path="$(knowtype_discover_release_manifest "$manifest_smoke_root/release.zip" "$manifest_smoke_root")"
assert_equals "$manifest_smoke_root/one/release-manifest.json" "$manifest_path" "single release manifest discovery"
rm -rf "$manifest_smoke_root"

cache_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/knowtype-prefpane-cache-smoke.XXXXXX")"
cache_stale="$cache_tmp_dir/com.apple.systemsettings.menucache"
cache_clean="$cache_tmp_dir/com.apple.preferencepanes.usercache"
cache_unrelated="$cache_tmp_dir/com.apple.preferencepanes.unrelated"
cache_regex_false_positive="$cache_tmp_dir/com.apple.preferencepanes.regex-like"
printf 'label=KnowType id=com.knowtype.preferencepane path=KnowType.prefPane\n' >"$cache_stale"
printf 'label=Keyboard id=com.apple.Keyboard-Settings.extension\n' >"$cache_clean"
printf 'label=KnowType recent search text without prefpane identity\n' >"$cache_unrelated"
printf 'id=comXknowtypeXpreferencepane path=KnowTypeXprefPane\n' >"$cache_regex_false_positive"
previous_cache_paths="${KNOWTYPE_PREFPANE_CACHE_PATHS-}"
export KNOWTYPE_PREFPANE_CACHE_PATHS="$cache_stale:$cache_clean:$cache_unrelated:$cache_regex_false_positive"
knowtype_preferencepane_cache_has_identity ||
  die "PreferencePane cache helper did not detect stale KnowType metadata"
cache_dry_run_output="$(knowtype_clean_preferencepane_caches 1)"
assert_contains "$cache_dry_run_output" "$cache_stale" "PreferencePane cache dry run output"
if grep -Fq "$cache_unrelated" <<<"$cache_dry_run_output"; then
  die "PreferencePane cache dry run treated unrelated KnowType text as stale prefPane metadata"
fi
if grep -Fq "$cache_regex_false_positive" <<<"$cache_dry_run_output"; then
  die "PreferencePane cache dry run treated regex-like text as stale prefPane metadata"
fi
assert_file "$cache_stale"
assert_file "$cache_clean"
assert_file "$cache_unrelated"
assert_file "$cache_regex_false_positive"
knowtype_clean_preferencepane_caches 0 >/dev/null
[[ ! -e "$cache_stale" ]] ||
  die "PreferencePane cache helper did not remove stale KnowType cache"
assert_file "$cache_clean"
assert_file "$cache_unrelated"
assert_file "$cache_regex_false_positive"
if [[ -n "$previous_cache_paths" ]]; then
  export KNOWTYPE_PREFPANE_CACHE_PATHS="$previous_cache_paths"
else
  unset KNOWTYPE_PREFPANE_CACHE_PATHS
fi
rm -rf "$cache_tmp_dir"

if grep -Fq 'bundle.load()' "$ROOT_DIR/scripts/diagnose-inputmethod.sh"; then
  die "diagnostics must not execute PreferencePane bundle code while inspecting install state"
fi

bundle_path="$(CODESIGN_IDENTITY=- "$ROOT_DIR/scripts/build-inputmethod-bundle.sh")"
assert_equals "$ROOT_DIR/dist/KnowType.app" "$bundle_path" "bundle path"
assert_dir "$bundle_path"
assert_file "$bundle_path/Contents/Info.plist"
assert_file "$bundle_path/Contents/MacOS/KnowTypeInputMethodApp"
[[ -x "$bundle_path/Contents/MacOS/KnowTypeInputMethodApp" ]] ||
  die "input-method executable is not executable"
assert_dir "$bundle_path/Contents/Resources/KnowType_KnowTypeCore.bundle"
assert_dir "$bundle_path/Contents/Resources/KnowType_KnowTypeSettingsUI.bundle"
assert_file "$bundle_path/Contents/Resources/KnowTypeInputMethodIcon.tiff"
assert_file "$bundle_path/Contents/Frameworks/librime.1.dylib"
assert_dir "$bundle_path/Contents/Resources/rime-data"
assert_file "$bundle_path/Contents/Resources/rime-data/pinyin_simp.schema.yaml"
assert_file "$bundle_path/Contents/Resources/rime-data/pinyin_simp.dict.yaml"
assert_equals "com.knowtype.inputmethod.KnowType" \
  "$(plist_read ":CFBundleIdentifier" "$bundle_path/Contents/Info.plist")" \
  "CFBundleIdentifier"
assert_equals "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
  "$(plist_read ":TISInputSourceID" "$bundle_path/Contents/Info.plist")" \
  "parent TISInputSourceID"
assert_equals "com.knowtype.inputmethod.KnowType.Hans" "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" "active input mode id"
assert_equals "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" \
  "$(plist_read ":ComponentInputModeDict:tsInputModeListKey:$KNOWTYPE_ACTIVE_INPUT_MODE_ID:TISInputSourceID" "$bundle_path/Contents/Info.plist")" \
  "active component mode TISInputSourceID"
assert_equals "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" \
  "$(plist_read ":ComponentInputModeDict:tsVisibleInputModeOrderedArrayKey:0" "$bundle_path/Contents/Info.plist")" \
  "visible component mode order"
assert_equals "K" \
  "$(plist_read ":ComponentInputModeDict:tsInputModeListKey:$KNOWTYPE_ACTIVE_INPUT_MODE_ID:tsInputModeKeyEquivalentKey" "$bundle_path/Contents/Info.plist")" \
  "component mode shortcut key"
assert_equals "4608" \
  "$(plist_read ":ComponentInputModeDict:tsInputModeListKey:$KNOWTYPE_ACTIVE_INPUT_MODE_ID:tsInputModeKeyEquivalentModifiersKey" "$bundle_path/Contents/Info.plist")" \
  "component mode shortcut modifiers"
assert_equals "KnowTypeInputMethodApp" \
  "$(plist_read ":CFBundleExecutable" "$bundle_path/Contents/Info.plist")" \
  "CFBundleExecutable"
"$bundle_path/Contents/MacOS/KnowTypeInputMethodApp" --knowtype-rime-smoke >/dev/null ||
  die "bundled Rime runtime smoke failed"

install_state_tmp="$(mktemp -d "${TMPDIR:-/tmp}/knowtype-install-state-smoke.XXXXXX")"
fake_input_dir="$install_state_tmp/Input Methods"
fake_prefpane_dir="$install_state_tmp/PreferencePanes"
fake_support_dir="$install_state_tmp/Application Support/KnowType"
mkdir -p "$fake_input_dir" "$fake_prefpane_dir" "$fake_support_dir"
cp -R "$bundle_path" "$fake_input_dir/KnowType.app"

install_dry_run_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  "$ROOT_DIR/scripts/install-inputmethod.sh" --dry-run --from-bundle "$bundle_path" --keep-backups 2
)"
assert_contains "$install_dry_run_output" "Source mode: bundle" "install dry run output"
assert_contains "$install_dry_run_output" "Install state: $fake_support_dir/install-state.json" "install dry run output"
assert_contains "$install_dry_run_output" "Backup root: $fake_support_dir/Backups" "install dry run output"
assert_contains "$install_dry_run_output" "Would create install backup" "install dry run output"

release_zip_path="$install_state_tmp/KnowType-test-release.zip"
release_zip_checksum_path="$install_state_tmp/KnowType-test-release.zip.sha256"
release_stage_root="$install_state_tmp/release-stage"
release_stage="$release_stage_root/KnowType-test-release"
mkdir -p "$release_stage"
cp -R "$bundle_path" "$release_stage/KnowType.app"
cat >"$release_stage/release-manifest.json" <<EOF
{
  "tag": "v0.2.0",
  "releaseCommit": "fixture-commit",
  "artifacts": {
    "archive": "$(basename "$release_zip_path")",
    "checksum": "$(basename "$release_zip_checksum_path")"
  },
  "bundles": [
    {
      "path": "KnowType.app",
      "bundleIdentifier": "$(plist_read ":CFBundleIdentifier" "$bundle_path/Contents/Info.plist")",
      "shortVersion": "$(plist_read ":CFBundleShortVersionString" "$bundle_path/Contents/Info.plist")",
      "buildVersion": "$(plist_read ":CFBundleVersion" "$bundle_path/Contents/Info.plist")"
    }
  ]
}
EOF
ditto -c -k --keepParent "$release_stage" "$release_zip_path"
(cd "$install_state_tmp" && shasum -a 256 "$(basename "$release_zip_path")" >"$(basename "$release_zip_checksum_path")")
release_zip_dry_run_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  "$ROOT_DIR/scripts/install-inputmethod.sh" --dry-run --from-release-zip "$release_zip_path" --no-backup
)"
assert_contains "$release_zip_dry_run_output" "Source mode: release-zip" "release zip install dry run output"
assert_contains "$release_zip_dry_run_output" "Source release zip: $release_zip_path" "release zip install dry run output"
assert_contains "$release_zip_dry_run_output" "Release commit: fixture-commit" "release zip install dry run output"

dmg_payload_root="$install_state_tmp/dmg-payload"
mkdir -p "$dmg_payload_root/Payload" "$dmg_payload_root/Resources"
cp -R "$bundle_path" "$dmg_payload_root/Payload/KnowType.app"
cp "$release_stage/release-manifest.json" "$dmg_payload_root/Resources/release-manifest.json"
dmg_payload_dry_run_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  "$ROOT_DIR/scripts/install-inputmethod.sh" --dry-run --from-dmg-payload "$dmg_payload_root" --no-backup
)"
assert_contains "$dmg_payload_dry_run_output" "Source mode: dmg-dev-preview" "DMG payload install dry run output"
assert_contains "$dmg_payload_dry_run_output" "Source DMG payload: $dmg_payload_root" "DMG payload install dry run output"
assert_contains "$dmg_payload_dry_run_output" "Release commit: fixture-commit" "DMG payload install dry run output"

assert_equals "0.2.0+build-bad-value" \
  "$(knowtype_sanitize_backup_component "0.2.0+build bad/value")" \
  "backup component sanitization"
knowtype_is_valid_backup_id "20260524T100000Z-0.2.0-123.ABCdef" ||
  die "expected safe backup ID to validate"
if knowtype_is_valid_backup_id "../../outside"; then
  die "traversal backup ID unexpectedly validated"
fi

KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  knowtype_create_install_backup "$fake_input_dir/KnowType.app" "$fake_prefpane_dir/KnowType.prefPane" 0 5 >/dev/null
backup_id="$KNOWTYPE_CREATED_BACKUP_ID"
[[ -n "$backup_id" ]] || die "install backup helper did not record a backup id"
assert_file "$fake_support_dir/Backups/$backup_id/manifest.json"
KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  knowtype_create_install_backup "$fake_input_dir/KnowType.app" "$fake_prefpane_dir/KnowType.prefPane" 0 5 >/dev/null
second_backup_id="$KNOWTYPE_CREATED_BACKUP_ID"
[[ -n "$second_backup_id" ]] || die "second install backup helper did not record a backup id"
if [[ "$second_backup_id" == "$backup_id" ]]; then
  die "rapid repeated backups reused ID: $backup_id"
fi
assert_file "$fake_support_dir/Backups/$second_backup_id/manifest.json"
mkdir -p "$fake_support_dir/Backups/zzzz-unmanaged"
latest_backup_dir="$(
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
    knowtype_latest_backup_dir
)"
assert_equals "$second_backup_id" "$(basename "$latest_backup_dir")" "latest backup id"
backup_manifest_id="$(
  KNOWTYPE_BACKUP_MANIFEST_PATH="$fake_support_dir/Backups/$backup_id/manifest.json" python3 - <<'PY'
import json, os
with open(os.environ["KNOWTYPE_BACKUP_MANIFEST_PATH"], encoding="utf-8") as handle:
    print(json.load(handle)["backupID"])
PY
)"
assert_equals "$backup_id" "$backup_manifest_id" "backup manifest id"

rollback_list_output="$(
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  "$ROOT_DIR/scripts/rollback-inputmethod.sh" --list
)"
assert_contains "$rollback_list_output" "$backup_id" "rollback list output"
assert_not_contains "$rollback_list_output" "zzzz-unmanaged" "rollback list output"

rollback_dry_run_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  "$ROOT_DIR/scripts/rollback-inputmethod.sh" --to "$backup_id" --dry-run
)"
assert_contains "$rollback_dry_run_output" "KnowType rollback dry run" "rollback dry run output"
assert_contains "$rollback_dry_run_output" "$backup_id" "rollback dry run output"
rollback_latest_dry_run_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  "$ROOT_DIR/scripts/rollback-inputmethod.sh" --latest --dry-run
)"
assert_contains "$rollback_latest_dry_run_output" "$second_backup_id" "rollback latest dry run output"
if KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  "$ROOT_DIR/scripts/rollback-inputmethod.sh" --to "../../outside" --dry-run >/dev/null 2>&1; then
  die "rollback accepted traversal backup ID"
fi
missing_backup_output="$(
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
    "$ROOT_DIR/scripts/rollback-inputmethod.sh" --to "missing-backup" --dry-run 2>&1 || true
)"
assert_contains "$missing_backup_output" "requested KnowType backup was not found" "rollback missing backup output"
corrupt_backup_id="20260524T010000Z-0000-corrupt-1"
corrupt_backup_dir="$fake_support_dir/Backups/$corrupt_backup_id"
mkdir -p "$corrupt_backup_dir/KnowType.app/Contents"
cp "$fake_input_dir/KnowType.app/Contents/Info.plist" "$corrupt_backup_dir/KnowType.app/Contents/Info.plist"
printf '{"schemaVersion":1,"backupID":"%s"}\n' "$corrupt_backup_id" >"$corrupt_backup_dir/manifest.json"
corrupt_rollback_output="$(
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
    "$ROOT_DIR/scripts/rollback-inputmethod.sh" --to "$corrupt_backup_id" --dry-run 2>&1 || true
)"
assert_contains "$corrupt_rollback_output" "input-method executable is missing" "rollback corrupt backup output"

printf '{"schemaVersion":1,"source":"bundle"}\n' >"$fake_support_dir/install-state.json"
uninstall_dry_run_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  "$ROOT_DIR/scripts/uninstall-inputmethod.sh" --dry-run
)"
assert_contains "$uninstall_dry_run_output" "Would create install backup" "uninstall dry run output"
assert_contains "$uninstall_dry_run_output" "Would remove KnowType install state" "uninstall dry run output"
assert_contains "$uninstall_dry_run_output" "Preserved KnowType install backups" "uninstall dry run output"
assert_not_contains "$uninstall_dry_run_output" "Would prune old install backup" "uninstall dry run output"
uninstall_purge_dry_run_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  "$ROOT_DIR/scripts/uninstall-inputmethod.sh" --dry-run --purge-backups
)"
assert_not_contains "$uninstall_purge_dry_run_output" "Would create install backup" "uninstall purge dry run output"
assert_contains "$uninstall_purge_dry_run_output" "Would delete KnowType install backups" "uninstall purge dry run output"

diagnose_json_output="$(
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  "$ROOT_DIR/scripts/diagnose-inputmethod.sh" --json --path "$fake_input_dir/KnowType.app"
)"
assert_contains "$diagnose_json_output" '"schemaVersion": 1' "diagnostics json output"
assert_contains "$diagnose_json_output" '"backups"' "diagnostics json output"
rm -rf "$install_state_tmp"

if (( WITH_PREFPANE == 1 )); then
  prefpane_path="$(CODESIGN_IDENTITY=- "$ROOT_DIR/scripts/build-preference-pane.sh")"
  assert_equals "$ROOT_DIR/dist/KnowType.prefPane" "$prefpane_path" "PreferencePane path"
  assert_dir "$prefpane_path"
  assert_file "$prefpane_path/Contents/Info.plist"
  assert_file "$prefpane_path/Contents/MacOS/KnowTypePreferencePane"
  assert_file "$prefpane_path/Contents/Frameworks/libKnowTypePreferencePane.dylib"
  assert_dir "$prefpane_path/Contents/Resources/KnowType_KnowTypeSettingsUI.bundle"
  assert_file "$prefpane_path/Contents/Resources/KnowType_KnowTypeSettingsUI.bundle/en.lproj/Localizable.strings"
  assert_file_any "zh-Hans settings localization" \
    "$prefpane_path/Contents/Resources/KnowType_KnowTypeSettingsUI.bundle/zh-Hans.lproj/Localizable.strings" \
    "$prefpane_path/Contents/Resources/KnowType_KnowTypeSettingsUI.bundle/zh-hans.lproj/Localizable.strings"
  [[ -x "$prefpane_path/Contents/MacOS/KnowTypePreferencePane" ]] ||
    die "PreferencePane executable is not executable"
  if command -v otool >/dev/null 2>&1; then
    otool -hv "$prefpane_path/Contents/MacOS/KnowTypePreferencePane" | grep -q "BUNDLE" ||
      die "PreferencePane executable is not an MH_BUNDLE"
    otool -L "$prefpane_path/Contents/MacOS/KnowTypePreferencePane" | grep -q "@rpath/libKnowTypePreferencePane.dylib" ||
      die "PreferencePane executable does not load the SwiftPM preference pane library"
  fi
  principal_class="$(
    PREFPANE_PATH="$prefpane_path" swift -e 'import Foundation; let path = ProcessInfo.processInfo.environment["PREFPANE_PATH"]!; guard let bundle = Bundle(url: URL(fileURLWithPath: path)), bundle.load() else { fatalError("PreferencePane bundle did not load") }; print(String(describing: bundle.principalClass))'
  )"
  [[ "$principal_class" == *"KnowTypePreferencePane"* ]] ||
    die "PreferencePane principal class did not resolve"
  assert_equals "com.knowtype.preferencepane" \
    "$(plist_read ":CFBundleIdentifier" "$prefpane_path/Contents/Info.plist")" \
    "PreferencePane CFBundleIdentifier"
  assert_equals "KnowTypePreferencePane" \
    "$(plist_read ":CFBundleExecutable" "$prefpane_path/Contents/Info.plist")" \
    "PreferencePane CFBundleExecutable"
  assert_equals "KnowTypePreferencePane" \
    "$(plist_read ":NSPrincipalClass" "$prefpane_path/Contents/Info.plist")" \
    "PreferencePane NSPrincipalClass"
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/knowtype-profile-smoke.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
profile_path="$tmp_dir/KnowTypeLocalSystemPolicy.mobileconfig"
profile_output="$("$ROOT_DIR/scripts/create-local-system-policy-profile.sh" --path "$bundle_path" --output "$profile_path")"

assert_file "$profile_path"
plutil -lint "$profile_path" >/dev/null

expected_requirement="$(codesign_requirement "$bundle_path")"
[[ -n "$expected_requirement" ]] || die "codesign did not return or allow deriving a requirement"
actual_requirement="$(plist_read ":PayloadContent:0:Requirement" "$profile_path")"
assert_equals "$expected_requirement" "$actual_requirement" "SystemPolicyRule requirement"
codesign -R "=$actual_requirement" -v "$bundle_path"

assert_equals "com.knowtype.local.systempolicy" \
  "$(plist_read ":PayloadIdentifier" "$profile_path")" \
  "profile PayloadIdentifier"
assert_equals "Configuration" \
  "$(plist_read ":PayloadType" "$profile_path")" \
  "profile PayloadType"
assert_equals "System" \
  "$(plist_read ":PayloadScope" "$profile_path")" \
  "profile PayloadScope"
assert_equals "com.knowtype.local.systempolicy.rule" \
  "$(plist_read ":PayloadContent:0:PayloadIdentifier" "$profile_path")" \
  "rule PayloadIdentifier"
assert_equals "com.apple.systempolicy.rule" \
  "$(plist_read ":PayloadContent:0:PayloadType" "$profile_path")" \
  "rule PayloadType"
assert_equals "operation:execute" \
  "$(plist_read ":PayloadContent:0:OperationType" "$profile_path")" \
  "rule OperationType"

rule_comment="$(plist_read ":PayloadContent:0:Comment" "$profile_path")"
assert_contains "$rule_comment" "$bundle_path" "rule Comment"
assert_contains "$profile_output" "Bundle: $bundle_path" "profile script output"
assert_contains "$profile_output" "PayloadIdentifier: com.knowtype.local.systempolicy" "profile script output"
assert_contains "$profile_output" "Rule PayloadType: com.apple.systempolicy.rule" "profile script output"
assert_contains "$profile_output" "Requirement: $expected_requirement" "profile script output"
assert_contains "$profile_output" "Requirement Source:" "profile script output"

codesign_details="$(codesign -dvvv "$bundle_path" 2>&1)"
signing_identifier="$(codesign_value "Identifier" "$codesign_details")"
team_identifier="$(codesign_value "TeamIdentifier" "$codesign_details")"
signature_kind="$(codesign_value "Signature" "$codesign_details")"

if [[ -n "$signing_identifier" ]]; then
  assert_contains "$rule_comment" "identifier=$signing_identifier" "rule Comment"
  assert_contains "$profile_output" "Signing Identifier: $signing_identifier" "profile script output"
fi

if [[ -n "$team_identifier" ]]; then
  assert_contains "$rule_comment" "team=$team_identifier" "rule Comment"
  assert_contains "$profile_output" "Team Identifier: $team_identifier" "profile script output"
fi

if [[ -n "$signature_kind" ]]; then
  assert_contains "$rule_comment" "signature=$signature_kind" "rule Comment"
  assert_contains "$profile_output" "Signature: $signature_kind" "profile script output"
fi

echo "Input method install/profile smoke passed"
