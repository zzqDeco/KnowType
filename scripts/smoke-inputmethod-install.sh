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
uninstall_script_contents="$(cat "$ROOT_DIR/scripts/uninstall-inputmethod.sh")"
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
assert_contains "$install_script_contents" '--version "$LOCAL_SHORT_VERSION" --build "$LOCAL_BUILD_VERSION"' "install script"
assert_contains "$install_script_contents" 'knowtype_validate_install_backup_for_restore "$BACKUP_DIR" 0' "install script"
assert_contains "$install_script_contents" 'knowtype_replace_local_preferencepane_bundle_atomically' "install script"

assert_contains "$rollback_script_contents" "purge_args=(" "rollback script"
assert_contains "$rollback_script_contents" "bootstrap_args=(" "rollback script"
assert_contains "$rollback_script_contents" '"$inputsource_tool" "${purge_args[@]}"' "rollback script"
assert_contains "$rollback_script_contents" '"$inputsource_tool" "${bootstrap_args[@]}"' "rollback script"
assert_contains "$rollback_script_contents" "process shutdown can flush Rime user data" "rollback script"
assert_contains "$rollback_script_contents" "knowtype_input_method_host_is_running" "rollback script"
assert_contains "$rollback_script_contents" "ps -axo command=" "rollback script"
assert_contains "$rollback_script_contents" '*/KnowTypeInputMethodApp\ *' "rollback script"
assert_not_contains "$rollback_script_contents" '${command%% *}' "rollback script"
assert_not_contains "$rollback_script_contents" 'KnowTypeInputMethodApp" --knowtype-purge-legacy' "rollback script"
assert_not_contains "$rollback_script_contents" "killall KnowTypeInputMethodApp" "rollback script"
assert_not_contains "$rollback_script_contents" "pgrep -x KnowTypeInputMethodApp" "rollback script"
assert_not_contains "$rollback_script_contents" 'open -g "$target_path"' "rollback script"
assert_contains "$rollback_script_contents" "--allow-unverified-backup" "rollback script"
assert_contains "$rollback_script_contents" 'knowtype_validate_install_backup_for_restore "$backup_dir" "$ALLOW_UNVERIFIED_BACKUP"' "rollback script"
assert_contains "$rollback_script_contents" 'knowtype_remove_local_preferencepane_bundle_if_safe "$prefpane_path" 0' "rollback script"
assert_not_contains "$rollback_script_contents" 'rm -rf -- "$prefpane_path"' "rollback script"

assert_contains "$uninstall_script_contents" 'knowtype_require_safe_local_preferencepane_if_present "$PREFPANE_TARGET_PATH"' "uninstall script"
assert_contains "$uninstall_script_contents" 'knowtype_remove_local_preferencepane_bundle_if_safe "$PREFPANE_TARGET_PATH" "$DRY_RUN"' "uninstall script"
assert_not_contains "$uninstall_script_contents" 'rm -rf -- "$PREFPANE_TARGET_PATH"' "uninstall script"

assert_contains "$repair_script_contents" '"$INPUTSOURCE_TOOL" purge-legacy' "repair script"
assert_contains "$repair_script_contents" '"$BUNDLE_EXECUTABLE" --knowtype-register-input-source --knowtype-enable-input-source' "repair script"
assert_contains "$repair_script_contents" '"$BUNDLE_EXECUTABLE" --knowtype-select-input-source' "repair script"
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
  "$ROOT_DIR/scripts/uninstall-inputmethod.sh"
)

for script_path in "${help_scripts[@]}"; do
  bash "$script_path" --help >/dev/null
done

source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"
declare -F knowtype_inputsource_tool >/dev/null ||
  die "scripts/lib/inputsource-tool.sh did not load knowtype_inputsource_tool"
source "$ROOT_DIR/scripts/lib/inputmethod-installation.sh"
declare -F knowtype_find_local_inputmethod_bundle_paths >/dev/null ||
  die "scripts/lib/inputmethod-installation.sh did not load duplicate discovery helpers"
declare -F knowtype_remove_local_inputmethod_bundle_if_safe >/dev/null ||
  die "scripts/lib/inputmethod-installation.sh did not load safe removal helpers"
declare -F knowtype_remove_local_preferencepane_bundle_if_safe >/dev/null ||
  die "scripts/lib/inputmethod-installation.sh did not load PreferencePane safe removal helpers"
declare -F knowtype_validate_install_backup_for_restore >/dev/null ||
  die "scripts/lib/inputmethod-installation.sh did not load backup integrity helpers"
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

smoke_short_version="9.8.7"
smoke_build_version="987"
bundle_path="$(bash "$ROOT_DIR/scripts/build-inputmethod-bundle.sh" --version "$smoke_short_version" --build "$smoke_build_version")"
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
assert_equals "com.knowtype.inputmethod.KnowType.Hans" "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" "visible active input mode id"
assert_equals "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" \
  "$(plist_read ":ComponentInputModeDict:tsInputModeListKey:$KNOWTYPE_ACTIVE_INPUT_MODE_ID:TISInputSourceID" "$bundle_path/Contents/Info.plist")" \
  "visible mode TISInputSourceID"
assert_equals "zh-Hans" \
  "$(plist_read ":ComponentInputModeDict:tsInputModeListKey:$KNOWTYPE_ACTIVE_INPUT_MODE_ID:TISIntendedLanguage" "$bundle_path/Contents/Info.plist")" \
  "visible mode intended language"
assert_equals "true" \
  "$(plist_read ":ComponentInputModeDict:tsInputModeListKey:$KNOWTYPE_ACTIVE_INPUT_MODE_ID:tsInputModeIsVisibleKey" "$bundle_path/Contents/Info.plist")" \
  "visible mode is visible"
assert_equals "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" \
  "$(plist_read ":ComponentInputModeDict:tsVisibleInputModeOrderedArrayKey:0" "$bundle_path/Contents/Info.plist")" \
  "visible input mode order"
assert_equals "KnowTypeInputMethodApp" \
  "$(plist_read ":CFBundleExecutable" "$bundle_path/Contents/Info.plist")" \
  "CFBundleExecutable"
assert_equals "$smoke_short_version" \
  "$(plist_read ":CFBundleShortVersionString" "$bundle_path/Contents/Info.plist")" \
  "input-method short version override"
assert_equals "$smoke_build_version" \
  "$(plist_read ":CFBundleVersion" "$bundle_path/Contents/Info.plist")" \
  "input-method build version override"

prefpane_path=""
if (( WITH_PREFPANE == 1 )); then
  prefpane_path="$(CODESIGN_IDENTITY=- bash "$ROOT_DIR/scripts/build-preference-pane.sh" --version "$smoke_short_version" --build "$smoke_build_version")"
  assert_equals "$smoke_short_version" \
    "$(plist_read ":CFBundleShortVersionString" "$prefpane_path/Contents/Info.plist")" \
    "PreferencePane short version consistency"
  assert_equals "$smoke_build_version" \
    "$(plist_read ":CFBundleVersion" "$prefpane_path/Contents/Info.plist")" \
    "PreferencePane build version consistency"
fi
# Run the Rime runtime check from the repository SwiftPM executable, not the
# packaged app bundle. macOS may SIGKILL a second IMK app process with the same
# bundle id while the installed input-method host is already running.
(
  cd "$ROOT_DIR"
  swift run --package-path "$ROOT_DIR" --quiet KnowTypeInputMethodApp --knowtype-rime-smoke
) >/dev/null ||
  die "Rime runtime smoke failed"

install_state_tmp="$(mktemp -d "${TMPDIR:-/tmp}/knowtype-install-state-smoke.XXXXXX")"
fake_input_dir="$install_state_tmp/Input Methods"
fake_prefpane_dir="$install_state_tmp/PreferencePanes"
fake_support_dir="$install_state_tmp/Application Support/KnowType"
mkdir -p "$fake_input_dir" "$fake_prefpane_dir" "$fake_support_dir"
cp -R "$bundle_path" "$fake_input_dir/KnowType.app"
if (( WITH_PREFPANE == 1 )); then
  cp -R "$prefpane_path" "$fake_prefpane_dir/KnowType.prefPane"
fi

install_dry_run_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  bash "$ROOT_DIR/scripts/install-inputmethod.sh" --dry-run --from-bundle "$bundle_path" --keep-backups 2
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
  bash "$ROOT_DIR/scripts/install-inputmethod.sh" --dry-run --from-release-zip "$release_zip_path" --no-backup
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
  bash "$ROOT_DIR/scripts/install-inputmethod.sh" --dry-run --from-dmg-payload "$dmg_payload_root" --no-backup
)"
assert_contains "$dmg_payload_dry_run_output" "Source mode: dmg-dev-preview" "DMG payload install dry run output"
assert_contains "$dmg_payload_dry_run_output" "Source DMG payload: $dmg_payload_root" "DMG payload install dry run output"
assert_contains "$dmg_payload_dry_run_output" "Release commit: fixture-commit" "DMG payload install dry run output"

packaged_dmg_root="$install_state_tmp/packaged-dmg-root"
mkdir -p "$packaged_dmg_root/Payload" "$packaged_dmg_root/Resources" "$packaged_dmg_root/Scripts/lib"
cp -R "$bundle_path" "$packaged_dmg_root/Payload/KnowType.app"
cp "$release_stage/release-manifest.json" "$packaged_dmg_root/Resources/release-manifest.json"
cp "$ROOT_DIR/scripts/install-inputmethod.sh" "$packaged_dmg_root/Scripts/"
cp "$ROOT_DIR/scripts/lib/inputsource-ids.sh" "$packaged_dmg_root/Scripts/lib/"
cp "$ROOT_DIR/scripts/lib/inputsource-tool.sh" "$packaged_dmg_root/Scripts/lib/"
cp "$ROOT_DIR/scripts/lib/inputmethod-installation.sh" "$packaged_dmg_root/Scripts/lib/"
packaged_dmg_dry_run_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  bash "$packaged_dmg_root/Scripts/install-inputmethod.sh" \
    --dry-run \
    --from-dmg-payload "$packaged_dmg_root" \
    --no-backup
)"
assert_contains "$packaged_dmg_dry_run_output" "Source mode: dmg-dev-preview" "packaged DMG install dry run output"
assert_not_contains "$packaged_dmg_dry_run_output" "local build short version is missing" "packaged DMG install dry run output"

if (( WITH_PREFPANE == 1 )); then
  staged_failure_source="$install_state_tmp/staged-failure-source/KnowType.prefPane"
  mkdir -p "$(dirname "$staged_failure_source")"
  cp -R "$prefpane_path" "$staged_failure_source"
  "$PLIST_BUDDY" -c "Set :CFBundleShortVersionString 9.9.9-stage-failure" \
    "$staged_failure_source/Contents/Info.plist"
  if KNOWTYPE_TEST_CORRUPT_STAGED_PREFPANE=1 \
    knowtype_replace_local_preferencepane_bundle_atomically \
      "$staged_failure_source" \
      "$fake_prefpane_dir/KnowType.prefPane" \
      0 >/dev/null 2>&1; then
    die "atomic PreferencePane replacement accepted an invalid staged copy"
  fi
  assert_equals "$smoke_short_version" \
    "$(plist_read ":CFBundleShortVersionString" "$fake_prefpane_dir/KnowType.prefPane/Contents/Info.plist")" \
    "failed staged PreferencePane replacement preserved current pane"
fi

assert_equals "0.2.0+build-bad-value" \
  "$(knowtype_sanitize_backup_component "0.2.0+build bad/value")" \
  "backup component sanitization"
knowtype_is_valid_backup_id "20260524T100000Z-0.2.0-123.ABCdef" ||
  die "expected safe backup ID to validate"
if knowtype_is_valid_backup_id "../../outside"; then
  die "traversal backup ID unexpectedly validated"
fi

KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  knowtype_create_install_backup "$fake_input_dir/KnowType.app" "$fake_prefpane_dir/KnowType.prefPane" 0 5 >/dev/null
backup_id="$KNOWTYPE_CREATED_BACKUP_ID"
[[ -n "$backup_id" ]] || die "install backup helper did not record a backup id"
assert_file "$fake_support_dir/Backups/$backup_id/manifest.json"
KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
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
  KNOWTYPE_BACKUP_MANIFEST_PATH="$fake_support_dir/Backups/$backup_id/manifest.json" "$KNOWTYPE_PYTHON3" - <<'PY'
import json, os
with open(os.environ["KNOWTYPE_BACKUP_MANIFEST_PATH"], encoding="utf-8") as handle:
    print(json.load(handle)["backupID"])
PY
)"
assert_equals "$backup_id" "$backup_manifest_id" "backup manifest id"
backup_manifest_path="$fake_support_dir/Backups/$backup_id/manifest.json"
assert_equals "2" "$(knowtype_backup_manifest_schema_version "$backup_manifest_path")" "backup manifest schema"
assert_equals "com.knowtype.inputmethod.KnowType" \
  "$(knowtype_backup_manifest_field "$backup_manifest_path" "appBundleIdentifier")" \
  "backup app bundle identifier"
assert_equals "$smoke_short_version" \
  "$(knowtype_backup_manifest_field "$backup_manifest_path" "appShortVersion")" \
  "backup app short version"
assert_equals "$smoke_build_version" \
  "$(knowtype_backup_manifest_field "$backup_manifest_path" "appBuildVersion")" \
  "backup app build version"
[[ -n "$(knowtype_backup_manifest_field "$backup_manifest_path" "appChecksum")" ]] ||
  die "backup manifest app checksum is missing"
[[ -n "$(knowtype_backup_manifest_field "$backup_manifest_path" "appSigningRequirement")" ]] ||
  die "backup manifest app signing requirement is missing"
[[ -n "$(knowtype_backup_manifest_field "$backup_manifest_path" "appSigningIdentity")" ]] ||
  die "backup manifest app signing identity is missing"
if (( WITH_PREFPANE == 1 )); then
  assert_equals "true" \
    "$(knowtype_backup_manifest_field "$backup_manifest_path" "includedPrefPane")" \
    "backup included PreferencePane"
  assert_equals "com.knowtype.preferencepane" \
    "$(knowtype_backup_manifest_field "$backup_manifest_path" "prefPaneBundleIdentifier")" \
    "backup PreferencePane bundle identifier"
  assert_equals "$smoke_short_version" \
    "$(knowtype_backup_manifest_field "$backup_manifest_path" "prefPaneShortVersion")" \
    "backup PreferencePane short version"
  assert_equals "$smoke_build_version" \
    "$(knowtype_backup_manifest_field "$backup_manifest_path" "prefPaneBuildVersion")" \
    "backup PreferencePane build version"
  [[ -n "$(knowtype_backup_manifest_field "$backup_manifest_path" "prefPaneChecksum")" ]] ||
    die "backup manifest PreferencePane checksum is missing"
  [[ -n "$(knowtype_backup_manifest_field "$backup_manifest_path" "prefPaneSigningRequirement")" ]] ||
    die "backup manifest PreferencePane signing requirement is missing"
  [[ -n "$(knowtype_backup_manifest_field "$backup_manifest_path" "prefPaneSigningIdentity")" ]] ||
    die "backup manifest PreferencePane signing identity is missing"
else
  assert_equals "false" \
    "$(knowtype_backup_manifest_field "$backup_manifest_path" "includedPrefPane")" \
    "backup excluded PreferencePane"
  assert_equals "" \
    "$(knowtype_backup_manifest_field "$backup_manifest_path" "prefPaneChecksum")" \
    "backup absent PreferencePane checksum"
fi

rollback_list_output="$(
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  bash "$ROOT_DIR/scripts/rollback-inputmethod.sh" --list
)"
assert_contains "$rollback_list_output" "$backup_id" "rollback list output"
assert_not_contains "$rollback_list_output" "zzzz-unmanaged" "rollback list output"

rollback_dry_run_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  bash "$ROOT_DIR/scripts/rollback-inputmethod.sh" --to "$backup_id" --dry-run
)"
assert_contains "$rollback_dry_run_output" "KnowType rollback dry run" "rollback dry run output"
assert_contains "$rollback_dry_run_output" "$backup_id" "rollback dry run output"
assert_contains "$rollback_dry_run_output" "Backup integrity: verified-schema-2" "rollback dry run output"
rollback_latest_dry_run_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  bash "$ROOT_DIR/scripts/rollback-inputmethod.sh" --latest --dry-run
)"
assert_contains "$rollback_latest_dry_run_output" "$second_backup_id" "rollback latest dry run output"

tampered_backup_file="$fake_support_dir/Backups/$backup_id/KnowType.app/Contents/Resources/rime-data/pinyin_simp.schema.yaml"
printf '\n# tampered backup smoke\n' >>"$tampered_backup_file"
if tampered_rollback_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
    bash "$ROOT_DIR/scripts/rollback-inputmethod.sh" --to "$backup_id" --dry-run 2>&1
)"; then
  die "rollback accepted a checksum-tampered schema-v2 backup"
fi
assert_contains "$tampered_rollback_output" "backup integrity mismatch for app checksum" "tampered backup rollback output"
if tampered_override_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
    bash "$ROOT_DIR/scripts/rollback-inputmethod.sh" --to "$backup_id" --dry-run --allow-unverified-backup 2>&1
)"; then
  die "legacy override bypassed a schema-v2 checksum mismatch"
fi
assert_contains "$tampered_override_output" "backup integrity mismatch for app checksum" "schema-v2 override rejection output"

signature_tampered_backup_id="20260524T020000Z-0000-signature-tampered-1"
signature_tampered_backup_dir="$fake_support_dir/Backups/$signature_tampered_backup_id"
cp -R "$fake_support_dir/Backups/$second_backup_id" "$signature_tampered_backup_dir"
signature_tampered_file="$signature_tampered_backup_dir/KnowType.app/Contents/Resources/rime-data/pinyin_simp.schema.yaml"
printf '\n# signature tamper with refreshed manifest checksum\n' >>"$signature_tampered_file"
signature_tampered_checksum="$(knowtype_path_checksum "$signature_tampered_backup_dir/KnowType.app")"
KNOWTYPE_BACKUP_MANIFEST_PATH="$signature_tampered_backup_dir/manifest.json" \
KNOWTYPE_BACKUP_ID_VALUE="$signature_tampered_backup_id" \
KNOWTYPE_BACKUP_CHECKSUM_VALUE="$signature_tampered_checksum" \
  "$KNOWTYPE_PYTHON3" - <<'PY'
import json
import os

path = os.environ["KNOWTYPE_BACKUP_MANIFEST_PATH"]
with open(path, encoding="utf-8") as handle:
    manifest = json.load(handle)
manifest["backupID"] = os.environ["KNOWTYPE_BACKUP_ID_VALUE"]
manifest["appChecksum"] = os.environ["KNOWTYPE_BACKUP_CHECKSUM_VALUE"]
manifest["restoreCommand"] = f"./scripts/rollback-inputmethod.sh --to {manifest['backupID']}"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, ensure_ascii=False, indent=2, sort_keys=True)
    handle.write("\n")
PY
if signature_tampered_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
    bash "$ROOT_DIR/scripts/rollback-inputmethod.sh" --to "$signature_tampered_backup_id" --dry-run 2>&1
)"; then
  die "rollback accepted a signature-tampered schema-v2 backup"
fi
assert_contains "$signature_tampered_output" "codesign --verify --deep --strict failed" "signature-tampered backup rollback output"

legacy_backup_id="20260524T030000Z-0000-legacy-1"
legacy_backup_dir="$fake_support_dir/Backups/$legacy_backup_id"
mkdir -p "$legacy_backup_dir"
cp -R "$fake_support_dir/Backups/$second_backup_id/KnowType.app" "$legacy_backup_dir/KnowType.app"
cat >"$legacy_backup_dir/manifest.json" <<EOF
{
  "schemaVersion": 1,
  "backupID": "$legacy_backup_id",
  "createdAt": "2026-05-24T03:00:00Z",
  "sourceVersion": "$smoke_short_version",
  "sourceBuild": "$smoke_build_version",
  "bundleIdentifier": "com.knowtype.inputmethod.KnowType",
  "appChecksum": "legacy-checksum",
  "includedPrefPane": false,
  "restoreCommand": "./scripts/rollback-inputmethod.sh --to $legacy_backup_id"
}
EOF
if legacy_rejected_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
    bash "$ROOT_DIR/scripts/rollback-inputmethod.sh" --to "$legacy_backup_id" --dry-run 2>&1
)"; then
  die "rollback accepted a legacy backup without the explicit override"
fi
assert_contains "$legacy_rejected_output" "legacy backup manifest lacks required integrity metadata" "legacy backup rejection output"
legacy_override_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
    bash "$ROOT_DIR/scripts/rollback-inputmethod.sh" --to "$legacy_backup_id" --dry-run --allow-unverified-backup 2>&1
)"
assert_contains "$legacy_override_output" "WARNING: ALLOWING AN UNVERIFIED LEGACY BACKUP" "legacy override warning"
assert_contains "$legacy_override_output" "UNVERIFIED LEGACY OVERRIDE: ENABLED" "legacy override dry-run output"

if KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  bash "$ROOT_DIR/scripts/rollback-inputmethod.sh" --to "../../outside" --dry-run >/dev/null 2>&1; then
  die "rollback accepted traversal backup ID"
fi
missing_backup_output="$(
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
    bash "$ROOT_DIR/scripts/rollback-inputmethod.sh" --to "missing-backup" --dry-run 2>&1 || true
)"
assert_contains "$missing_backup_output" "requested KnowType backup was not found" "rollback missing backup output"
corrupt_backup_id="20260524T010000Z-0000-corrupt-1"
corrupt_backup_dir="$fake_support_dir/Backups/$corrupt_backup_id"
mkdir -p "$corrupt_backup_dir/KnowType.app/Contents"
cp "$fake_input_dir/KnowType.app/Contents/Info.plist" "$corrupt_backup_dir/KnowType.app/Contents/Info.plist"
printf '{"schemaVersion":1,"backupID":"%s"}\n' "$corrupt_backup_id" >"$corrupt_backup_dir/manifest.json"
corrupt_rollback_output="$(
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
    bash "$ROOT_DIR/scripts/rollback-inputmethod.sh" --to "$corrupt_backup_id" --dry-run --allow-unverified-backup 2>&1 || true
)"
assert_contains "$corrupt_rollback_output" "input-method executable is missing" "rollback corrupt backup output"

printf '{"schemaVersion":1,"source":"bundle"}\n' >"$fake_support_dir/install-state.json"
uninstall_dry_run_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  bash "$ROOT_DIR/scripts/uninstall-inputmethod.sh" --dry-run
)"
assert_contains "$uninstall_dry_run_output" "Would create install backup" "uninstall dry run output"
assert_contains "$uninstall_dry_run_output" "Would remove KnowType install state" "uninstall dry run output"
assert_contains "$uninstall_dry_run_output" "Preserved KnowType install backups" "uninstall dry run output"
assert_not_contains "$uninstall_dry_run_output" "Would prune old install backup" "uninstall dry run output"
uninstall_purge_dry_run_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$fake_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$fake_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  bash "$ROOT_DIR/scripts/uninstall-inputmethod.sh" --dry-run --purge-backups
)"
assert_not_contains "$uninstall_purge_dry_run_output" "Would create install backup" "uninstall purge dry run output"
assert_contains "$uninstall_purge_dry_run_output" "Would delete KnowType install backups" "uninstall purge dry run output"

foreign_root="$install_state_tmp/foreign-prefpane"
foreign_input_dir="$foreign_root/Input Methods"
foreign_prefpane_dir="$foreign_root/PreferencePanes"
mkdir -p "$foreign_input_dir" "$foreign_prefpane_dir/KnowType.prefPane/Contents"
cp -R "$bundle_path" "$foreign_input_dir/KnowType.app"
cp "$ROOT_DIR/Resources/PreferencePane/Info.plist" "$foreign_prefpane_dir/KnowType.prefPane/Contents/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleIdentifier com.example.foreign.preferencepane" \
  "$foreign_prefpane_dir/KnowType.prefPane/Contents/Info.plist"

if foreign_install_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$foreign_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$foreign_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
    bash "$ROOT_DIR/scripts/install-inputmethod.sh" --dry-run --from-bundle "$bundle_path" --no-backup 2>&1
)"; then
  die "install dry run accepted a foreign same-name PreferencePane"
fi
assert_contains "$foreign_install_output" "foreign or unsafe same-name PreferencePane" "foreign PreferencePane install output"

if foreign_uninstall_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$foreign_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$foreign_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
    bash "$ROOT_DIR/scripts/uninstall-inputmethod.sh" --dry-run --no-backup 2>&1
)"; then
  die "uninstall dry run accepted a foreign same-name PreferencePane"
fi
assert_contains "$foreign_uninstall_output" "foreign or unsafe same-name PreferencePane" "foreign PreferencePane uninstall output"

if foreign_rollback_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$foreign_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$foreign_prefpane_dir" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
    bash "$ROOT_DIR/scripts/rollback-inputmethod.sh" --to "$second_backup_id" --dry-run 2>&1
)"; then
  die "rollback dry run accepted a foreign same-name PreferencePane"
fi
assert_contains "$foreign_rollback_output" "foreign or unsafe same-name PreferencePane" "foreign PreferencePane rollback output"
assert_equals "com.example.foreign.preferencepane" \
  "$(plist_read ":CFBundleIdentifier" "$foreign_prefpane_dir/KnowType.prefPane/Contents/Info.plist")" \
  "foreign PreferencePane remained unchanged"

symlink_prefpane_root="$install_state_tmp/symlink-prefpane-target"
mkdir -p "$symlink_prefpane_root/actual"
ln -s "$symlink_prefpane_root/actual" "$symlink_prefpane_root/linked"
if symlink_target_output="$(
  KNOWTYPE_INPUTMETHOD_TARGET_DIR="$foreign_input_dir" \
  KNOWTYPE_PREFPANE_TARGET_DIR="$symlink_prefpane_root/linked" \
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
    bash "$ROOT_DIR/scripts/install-inputmethod.sh" --dry-run --from-bundle "$bundle_path" --no-backup 2>&1
)"; then
  die "install dry run accepted a symlinked PreferencePane target directory"
fi
assert_contains "$symlink_target_output" "unsafe PreferencePane target path" "symlinked PreferencePane target output"

diagnose_json_output="$(
  KNOWTYPE_APP_SUPPORT_DIR="$fake_support_dir" \
  bash "$ROOT_DIR/scripts/diagnose-inputmethod.sh" --json --path "$fake_input_dir/KnowType.app"
)"
assert_contains "$diagnose_json_output" '"schemaVersion": 1' "diagnostics json output"
assert_contains "$diagnose_json_output" '"backups"' "diagnostics json output"
rm -rf "$install_state_tmp"

if (( WITH_PREFPANE == 1 )); then
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
profile_output="$(bash "$ROOT_DIR/scripts/create-local-system-policy-profile.sh" --path "$bundle_path" --output "$profile_path")"

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
