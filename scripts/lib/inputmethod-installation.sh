#!/usr/bin/env bash

KNOWTYPE_INSTALLATION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$KNOWTYPE_INSTALLATION_LIB_DIR/inputsource-ids.sh"

KNOWTYPE_PREFPANE_BUNDLE_ID="com.knowtype.preferencepane"
KNOWTYPE_LSREGISTER="${KNOWTYPE_LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"
KNOWTYPE_PLIST_BUDDY="${KNOWTYPE_PLIST_BUDDY:-/usr/libexec/PlistBuddy}"
KNOWTYPE_PYTHON3="${KNOWTYPE_PYTHON3:-/usr/bin/python3}"
if [[ ! -x "$KNOWTYPE_PYTHON3" ]]; then
  KNOWTYPE_PYTHON3="$(command -v python3 2>/dev/null || true)"
fi
KNOWTYPE_SYSTEM_SETTINGS_APP_PATH="/System/Applications/System Settings.app/Contents/MacOS/System Settings"
KNOWTYPE_SYSTEM_PREFERENCES_APP_PATH="/System/Applications/System Preferences.app/Contents/MacOS/System Preferences"
KNOWTYPE_DEFAULT_BACKUP_RETENTION=3

knowtype_inputmethod_target_dir() {
  printf '%s' "${KNOWTYPE_INPUTMETHOD_TARGET_DIR:-$HOME/Library/Input Methods}"
}

knowtype_inputmethod_target_path() {
  printf '%s/KnowType.app' "$(knowtype_inputmethod_target_dir)"
}

knowtype_preferencepane_target_dir() {
  printf '%s' "${KNOWTYPE_PREFPANE_TARGET_DIR:-$HOME/Library/PreferencePanes}"
}

knowtype_preferencepane_target_path() {
  printf '%s/KnowType.prefPane' "$(knowtype_preferencepane_target_dir)"
}

knowtype_app_support_dir() {
  printf '%s' "${KNOWTYPE_APP_SUPPORT_DIR:-$HOME/Library/Application Support/KnowType}"
}

knowtype_install_state_path() {
  printf '%s' "${KNOWTYPE_INSTALL_STATE_PATH:-$(knowtype_app_support_dir)/install-state.json}"
}

knowtype_backup_root_dir() {
  printf '%s' "${KNOWTYPE_BACKUP_ROOT_DIR:-$(knowtype_app_support_dir)/Backups}"
}

knowtype_iso_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

knowtype_backup_id_timestamp() {
  date -u '+%Y%m%dT%H%M%SZ'
}

knowtype_preferencepane_cache_paths() {
  if [[ -n "${KNOWTYPE_PREFPANE_CACHE_PATHS:-}" ]]; then
    tr ':' '\n' <<<"$KNOWTYPE_PREFPANE_CACHE_PATHS" | awk 'NF'
    return 0
  fi

  printf '%s\n' "$HOME/Library/Caches/com.apple.preferencepanes.usercache"
  printf '%s\n' "$HOME/Library/Caches/com.apple.systemsettings.menucache"
}

knowtype_preferencepane_cache_contains_identity() {
  local cache_path="$1"
  [[ -f "$cache_path" ]] || return 1

  LC_ALL=C grep -a -F -q \
    -e "$KNOWTYPE_PREFPANE_BUNDLE_ID" \
    -e "KnowType.prefPane" \
    "$cache_path" 2>/dev/null
}

knowtype_preferencepane_cache_identity_paths() {
  while IFS= read -r cache_path; do
    [[ -n "$cache_path" ]] || continue
    if knowtype_preferencepane_cache_contains_identity "$cache_path"; then
      printf '%s\n' "$cache_path"
    fi
  done < <(knowtype_preferencepane_cache_paths)
}

knowtype_preferencepane_cache_has_identity() {
  [[ -n "$(knowtype_preferencepane_cache_identity_paths)" ]]
}

knowtype_clean_preferencepane_caches() {
  local dry_run="${1:-0}"
  local cleaned=0

  while IFS= read -r cache_path; do
    [[ -n "$cache_path" ]] || continue
    if ! knowtype_preferencepane_cache_contains_identity "$cache_path"; then
      continue
    fi
    cleaned=$((cleaned + 1))
    if [[ "$dry_run" == "1" ]]; then
      echo "[dry-run] Would remove stale System Settings PreferencePane cache: $cache_path"
    else
      rm -f -- "$cache_path"
      echo "Removed stale System Settings PreferencePane cache: $cache_path"
    fi
  done < <(knowtype_preferencepane_cache_paths)

  return 0
}

knowtype_system_settings_is_running() {
  pgrep -f "$KNOWTYPE_SYSTEM_SETTINGS_APP_PATH" >/dev/null 2>&1 ||
    pgrep -f "$KNOWTYPE_SYSTEM_PREFERENCES_APP_PATH" >/dev/null 2>&1
}

knowtype_quit_system_settings_if_running() {
  local dry_run="${1:-0}"

  if ! knowtype_system_settings_is_running; then
    return 0
  fi

  if [[ "$dry_run" == "1" ]]; then
    echo "[dry-run] Would ask System Settings to quit so its PreferencePane sidebar cache can rebuild"
    return 0
  fi

  if osascript -e 'tell application id "com.apple.systempreferences" to quit' >/dev/null 2>&1; then
    echo "Asked System Settings to quit so its PreferencePane sidebar cache can rebuild"
  else
    echo "warning: could not ask System Settings to quit; close and reopen System Settings before checking the KnowType sidebar entry" >&2
  fi
}

knowtype_strip_lsregister_suffix() {
  local value="$1"
  value="${value% (0x*)}"
  printf '%s' "$value"
}

knowtype_expand_home_path() {
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

knowtype_canonical_bundle_path() {
  local path="$1"
  path="$(knowtype_expand_home_path "$(knowtype_strip_lsregister_suffix "$path")")"
  if [[ -e "$path" ]]; then
    printf '%s/%s' "$(cd "$(dirname "$path")" && pwd -P)" "$(basename "$path")"
  else
    printf '%s' "$path"
  fi
}

knowtype_plist_value() {
  local key="$1"
  local plist="$2"
  local output
  if output="$(/usr/bin/plutil -extract "$key" raw -o - "$plist" 2>/dev/null)"; then
    printf '%s' "$output"
  fi
}

knowtype_bundle_short_version() {
  local bundle_path="$1"
  knowtype_plist_value "CFBundleShortVersionString" "$bundle_path/Contents/Info.plist"
}

knowtype_bundle_build_version() {
  local bundle_path="$1"
  knowtype_plist_value "CFBundleVersion" "$bundle_path/Contents/Info.plist"
}

knowtype_bundle_identifier() {
  local bundle_path="$1"
  knowtype_plist_value "CFBundleIdentifier" "$bundle_path/Contents/Info.plist"
}

knowtype_sanitize_backup_component() {
  local value="$1"
  value="${value:-unknown}"
  printf '%s' "$value" | LC_ALL=C sed 's/[^A-Za-z0-9._+-]/-/g'
}

knowtype_is_valid_backup_id() {
  local backup_id="$1"
  [[ -n "$backup_id" ]] || return 1
  [[ "$backup_id" != "." && "$backup_id" != ".." ]] || return 1
  [[ "$backup_id" != *"/"* ]] || return 1
  [[ "$backup_id" == "$(knowtype_sanitize_backup_component "$backup_id")" ]]
}

knowtype_discover_release_manifest() {
  local zip_path="$1"
  local extracted_root="$2"
  local candidate=""
  local count=0
  local manifest_path
  while IFS= read -r manifest_path; do
    [[ -n "$manifest_path" ]] || continue
    count=$((count + 1))
    if [[ -z "$candidate" ]]; then
      candidate="$manifest_path"
    fi
  done < <(find "$extracted_root" -maxdepth 4 -type f -name 'release-manifest.json' -print 2>/dev/null)

  if (( count > 1 )); then
    echo "error: release zip must contain exactly one release-manifest.json; found $count" >&2
    return 1
  fi
  if (( count == 1 )); then
    printf '%s' "$candidate"
    return 0
  fi

  local sibling
  sibling="$(dirname "$zip_path")/release-manifest.json"
  if [[ -f "$sibling" ]]; then
    printf '%s' "$sibling"
  fi
  return 0
}

knowtype_path_checksum() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    return 1
  fi

  if [[ -f "$path" ]]; then
    shasum -a 256 "$path" | awk '{print $1}'
    return 0
  fi

  (
    cd "$path" || exit 1
    find . -type f -print 2>/dev/null |
      LC_ALL=C sort |
      while IFS= read -r file_path; do
        shasum -a 256 "$file_path"
      done |
      shasum -a 256 |
      awk '{print $1}'
  )
}

knowtype_json_escape() {
  local value="$1"
  KNOWTYPE_JSON_VALUE="$value" "$KNOWTYPE_PYTHON3" - <<'PY'
import json
import os
print(json.dumps(os.environ.get("KNOWTYPE_JSON_VALUE", ""))[1:-1])
PY
}

knowtype_write_json_file() {
  local output_path="$1"
  shift
  local directory
  directory="$(dirname "$output_path")"
  mkdir -p "$directory"
  KNOWTYPE_OUTPUT_PATH="$output_path" "$@" "$KNOWTYPE_PYTHON3" - <<'PY'
import json
import os

def env(name, default=""):
    value = os.environ.get(name)
    return default if value is None else value

def optional(name):
    value = os.environ.get(name)
    return value if value else None

payload = json.loads(env("KNOWTYPE_JSON_PAYLOAD", "{}"))
output_path = env("KNOWTYPE_OUTPUT_PATH")
tmp_path = f"{output_path}.tmp"
with open(tmp_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
    handle.write("\n")
os.replace(tmp_path, output_path)
PY
}

knowtype_write_install_state() {
  local source="$1"
  local bundle_path="$2"
  local prefpane_path="$3"
  local backup_id="$4"
  local git_commit="$5"
  local git_tag="$6"
  local release_manifest_digest="$7"
  local state_path
  state_path="$(knowtype_install_state_path)"

  local version
  local build
  local bundle_id
  version="$(knowtype_bundle_short_version "$bundle_path")"
  build="$(knowtype_bundle_build_version "$bundle_path")"
  bundle_id="$(knowtype_bundle_identifier "$bundle_path")"

  KNOWTYPE_JSON_PAYLOAD="$(
    KNOWTYPE_STATE_SOURCE="$source" \
    KNOWTYPE_STATE_INSTALLED_AT="$(knowtype_iso_timestamp)" \
    KNOWTYPE_STATE_VERSION="$version" \
    KNOWTYPE_STATE_BUILD="$build" \
    KNOWTYPE_STATE_GIT_COMMIT="$git_commit" \
    KNOWTYPE_STATE_GIT_TAG="$git_tag" \
    KNOWTYPE_STATE_BUNDLE_PATH="$bundle_path" \
    KNOWTYPE_STATE_PREFPANE_PATH="$prefpane_path" \
    KNOWTYPE_STATE_PREVIOUS_BACKUP_ID="$backup_id" \
    KNOWTYPE_STATE_BUNDLE_ID="$bundle_id" \
    KNOWTYPE_STATE_MODE_ID="$KNOWTYPE_ACTIVE_INPUT_MODE_ID" \
    KNOWTYPE_STATE_RELEASE_MANIFEST_DIGEST="$release_manifest_digest" \
    "$KNOWTYPE_PYTHON3" - <<'PY'
import json
import os

def optional(name):
    value = os.environ.get(name, "")
    return value if value else None

payload = {
    "schemaVersion": 1,
    "installedAt": os.environ["KNOWTYPE_STATE_INSTALLED_AT"],
    "source": os.environ["KNOWTYPE_STATE_SOURCE"],
    "version": os.environ.get("KNOWTYPE_STATE_VERSION", ""),
    "build": os.environ.get("KNOWTYPE_STATE_BUILD", ""),
    "gitCommit": optional("KNOWTYPE_STATE_GIT_COMMIT"),
    "gitTag": optional("KNOWTYPE_STATE_GIT_TAG"),
    "bundlePath": os.environ["KNOWTYPE_STATE_BUNDLE_PATH"],
    "prefPanePath": optional("KNOWTYPE_STATE_PREFPANE_PATH"),
    "previousBackupID": optional("KNOWTYPE_STATE_PREVIOUS_BACKUP_ID"),
    "bundleIdentifier": os.environ.get("KNOWTYPE_STATE_BUNDLE_ID", ""),
    "modeID": os.environ.get("KNOWTYPE_STATE_MODE_ID", ""),
    "releaseManifestDigest": optional("KNOWTYPE_STATE_RELEASE_MANIFEST_DIGEST"),
}
print(json.dumps(payload, ensure_ascii=False))
PY
  )" knowtype_write_json_file "$state_path" env
}

knowtype_read_install_state_field() {
  local field="$1"
  local state_path
  state_path="$(knowtype_install_state_path)"
  [[ -f "$state_path" ]] || return 0
  KNOWTYPE_INSTALL_STATE_FIELD="$field" KNOWTYPE_INSTALL_STATE_PATH_VALUE="$state_path" "$KNOWTYPE_PYTHON3" - <<'PY'
import json
import os
path = os.environ["KNOWTYPE_INSTALL_STATE_PATH_VALUE"]
field = os.environ["KNOWTYPE_INSTALL_STATE_FIELD"]
try:
    with open(path, encoding="utf-8") as handle:
        value = json.load(handle).get(field)
except Exception:
    value = None
if value is not None:
    print(value)
PY
}

KNOWTYPE_CREATED_BACKUP_ID=""
KNOWTYPE_CREATED_BACKUP_DIR=""

knowtype_create_install_backup() {
  local app_path="$1"
  local prefpane_path="$2"
  local dry_run="${3:-0}"
  local keep_backups="${4:-$KNOWTYPE_DEFAULT_BACKUP_RETENTION}"
  KNOWTYPE_CREATED_BACKUP_ID=""
  KNOWTYPE_CREATED_BACKUP_DIR=""

  if [[ ! -d "$app_path" ]]; then
    return 0
  fi

  local version
  local build
  version="$(knowtype_bundle_short_version "$app_path")"
  build="$(knowtype_bundle_build_version "$app_path")"
  local backup_timestamp
  local version_component
  local build_component
  backup_timestamp="$(knowtype_backup_id_timestamp)"
  version_component="$(knowtype_sanitize_backup_component "$version")"
  build_component="$(knowtype_sanitize_backup_component "$build")"
  local backup_root
  local backup_dir
  backup_root="$(knowtype_backup_root_dir)"
  local backup_id
  backup_id="${backup_timestamp}-0000-${version_component}-${build_component}"
  backup_dir="$backup_root/$backup_id"
  KNOWTYPE_CREATED_BACKUP_ID="$backup_id"
  KNOWTYPE_CREATED_BACKUP_DIR="$backup_dir"

  if [[ "$dry_run" == "1" ]]; then
    echo "[dry-run] Would create install backup: $backup_dir"
    [[ -d "$app_path" ]] && echo "[dry-run] Would back up app: $app_path"
    [[ -d "$prefpane_path" ]] && echo "[dry-run] Would back up PreferencePane: $prefpane_path"
    return 0
  fi

  mkdir -p "$backup_root"
  backup_id=""
  backup_dir=""
  local counter
  local counter_component
  for counter in $(seq 0 9999); do
    counter_component="$(printf '%04d' "$counter")"
    backup_id="${backup_timestamp}-${counter_component}-${version_component}-${build_component}"
    backup_dir="$backup_root/$backup_id"
    if mkdir "$backup_dir" 2>/dev/null; then
      break
    fi
    backup_id=""
    backup_dir=""
  done
  if [[ -z "$backup_id" || -z "$backup_dir" ]]; then
    echo "error: failed to allocate a unique KnowType backup directory" >&2
    return 1
  fi
  KNOWTYPE_CREATED_BACKUP_ID="$backup_id"
  KNOWTYPE_CREATED_BACKUP_DIR="$backup_dir"
  if [[ -d "$app_path" ]]; then
    cp -R "$app_path" "$backup_dir/KnowType.app"
  fi
  local included_prefpane="false"
  if [[ -d "$prefpane_path" ]]; then
    cp -R "$prefpane_path" "$backup_dir/KnowType.prefPane"
    included_prefpane="true"
  fi

  local checksum=""
  if [[ -d "$backup_dir/KnowType.app" ]]; then
    checksum="$(knowtype_path_checksum "$backup_dir/KnowType.app" || true)"
  fi

  KNOWTYPE_JSON_PAYLOAD="$(
    KNOWTYPE_BACKUP_ID="$backup_id" \
    KNOWTYPE_BACKUP_CREATED_AT="$(knowtype_iso_timestamp)" \
    KNOWTYPE_BACKUP_VERSION="$version" \
    KNOWTYPE_BACKUP_BUILD="$build" \
    KNOWTYPE_BACKUP_BUNDLE_ID="$(knowtype_bundle_identifier "$app_path")" \
    KNOWTYPE_BACKUP_APP_CHECKSUM="$checksum" \
    KNOWTYPE_BACKUP_INCLUDED_PREFPANE="$included_prefpane" \
    KNOWTYPE_BACKUP_RESTORE_COMMAND="./scripts/rollback-inputmethod.sh --to $backup_id" \
    "$KNOWTYPE_PYTHON3" - <<'PY'
import json
import os
payload = {
    "schemaVersion": 1,
    "backupID": os.environ["KNOWTYPE_BACKUP_ID"],
    "createdAt": os.environ["KNOWTYPE_BACKUP_CREATED_AT"],
    "sourceVersion": os.environ.get("KNOWTYPE_BACKUP_VERSION", ""),
    "sourceBuild": os.environ.get("KNOWTYPE_BACKUP_BUILD", ""),
    "bundleIdentifier": os.environ.get("KNOWTYPE_BACKUP_BUNDLE_ID", ""),
    "appChecksum": os.environ.get("KNOWTYPE_BACKUP_APP_CHECKSUM", ""),
    "includedPrefPane": os.environ.get("KNOWTYPE_BACKUP_INCLUDED_PREFPANE") == "true",
    "restoreCommand": os.environ["KNOWTYPE_BACKUP_RESTORE_COMMAND"],
}
print(json.dumps(payload, ensure_ascii=False))
PY
  )" knowtype_write_json_file "$backup_dir/manifest.json" env

  echo "Created install backup: $backup_dir"
}

knowtype_backup_manifest_field() {
  local manifest_path="$1"
  local field="$2"
  [[ -f "$manifest_path" ]] || return 0
  KNOWTYPE_BACKUP_MANIFEST_PATH="$manifest_path" KNOWTYPE_BACKUP_MANIFEST_FIELD="$field" "$KNOWTYPE_PYTHON3" - <<'PY'
import json
import os
try:
    with open(os.environ["KNOWTYPE_BACKUP_MANIFEST_PATH"], encoding="utf-8") as handle:
        value = json.load(handle).get(os.environ["KNOWTYPE_BACKUP_MANIFEST_FIELD"])
except Exception:
    value = None
if value is not None:
    print(value)
PY
}

knowtype_is_managed_backup_dir() {
  local backup_dir="$1"
  local backup_id
  backup_id="$(basename "$backup_dir")"
  knowtype_is_valid_backup_id "$backup_id" || return 1
  [[ "$backup_id" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9]{4}- ]] || return 1
  [[ -d "$backup_dir/KnowType.app" ]] || return 1
  [[ -f "$backup_dir/manifest.json" ]] || return 1
  local manifest_id
  manifest_id="$(knowtype_backup_manifest_field "$backup_dir/manifest.json" "backupID")"
  [[ "$manifest_id" == "$backup_id" ]]
}

knowtype_list_managed_backup_dirs() {
  local backup_root
  backup_root="$(knowtype_backup_root_dir)"
  [[ -d "$backup_root" ]] || return 0
  local backup_dir
  while IFS= read -r backup_dir; do
    [[ -n "$backup_dir" ]] || continue
    if knowtype_is_managed_backup_dir "$backup_dir"; then
      printf '%s\n' "$backup_dir"
    fi
  done < <(find "$backup_root" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null) | LC_ALL=C sort -r
}

knowtype_prune_install_backups() {
  local keep_backups="${1:-$KNOWTYPE_DEFAULT_BACKUP_RETENTION}"
  local dry_run="${2:-0}"
  [[ "$keep_backups" =~ ^[0-9]+$ ]] || keep_backups="$KNOWTYPE_DEFAULT_BACKUP_RETENTION"

  local index=0
  while IFS= read -r backup_dir; do
    [[ -n "$backup_dir" ]] || continue
    index=$((index + 1))
    if (( index <= keep_backups )); then
      continue
    fi
    if [[ "$dry_run" == "1" ]]; then
      echo "[dry-run] Would prune old install backup: $backup_dir"
    else
      rm -rf -- "$backup_dir"
      echo "Pruned old install backup: $backup_dir"
    fi
  done < <(knowtype_list_managed_backup_dirs)
}

knowtype_latest_backup_dir() {
  # Backup IDs start with UTC timestamp plus a monotonic per-second counter, so
  # reverse lexical order is newest-first for managed restorable backups.
  knowtype_list_managed_backup_dirs | head -n 1
}

knowtype_backup_dir_for_id() {
  local backup_id="$1"
  if ! knowtype_is_valid_backup_id "$backup_id"; then
    return 1
  fi
  local backup_dir
  backup_dir="$(knowtype_backup_root_dir)/$backup_id"
  if [[ -d "$backup_dir" ]] && knowtype_is_managed_backup_dir "$backup_dir"; then
    printf '%s\n' "$backup_dir"
    return 0
  fi
  return 1
}

knowtype_validate_inputmethod_bundle_for_install() {
  local bundle_path="$1"
  local verify_codesign="${2:-1}"
  if [[ ! -d "$bundle_path" ]]; then
    echo "error: KnowType.app bundle is missing: $bundle_path" >&2
    return 1
  fi
  if ! knowtype_bundle_matches_inputmethod_identity "$bundle_path"; then
    echo "error: bundle does not match KnowType input-method identity: $bundle_path" >&2
    return 1
  fi
  if [[ ! -x "$bundle_path/Contents/MacOS/KnowTypeInputMethodApp" ]]; then
    echo "error: input-method executable is missing or not executable in: $bundle_path" >&2
    return 1
  fi
  if [[ ! -f "$bundle_path/Contents/Frameworks/librime.1.dylib" ]]; then
    echo "error: bundled Rime dylib is missing in: $bundle_path" >&2
    return 1
  fi
  if [[ ! -d "$bundle_path/Contents/Resources/rime-data" ]]; then
    echo "error: bundled Rime data directory is missing in: $bundle_path" >&2
    return 1
  fi
  if [[ "$verify_codesign" == "1" ]] && command -v codesign >/dev/null 2>&1; then
    codesign --verify --deep --strict "$bundle_path"
  fi
}

knowtype_plistbuddy_value() {
  local key_path="$1"
  local plist="$2"
  local output
  if [[ -x "$KNOWTYPE_PLIST_BUDDY" ]] &&
     output="$("$KNOWTYPE_PLIST_BUDDY" -c "Print $key_path" "$plist" 2>/dev/null)"; then
    printf '%s' "$output"
  fi
}

knowtype_bundle_visible_input_mode_id() {
  local bundle_path="$1"
  local info_plist="$bundle_path/Contents/Info.plist"
  [[ -f "$info_plist" ]] || return 1

  local mode_id
  mode_id="$(knowtype_plistbuddy_value ":ComponentInputModeDict:tsVisibleInputModeOrderedArrayKey:0" "$info_plist")"
  if [[ -z "$mode_id" ]]; then
    return 1
  fi
  if [[ "$(knowtype_plistbuddy_value ":ComponentInputModeDict:tsInputModeListKey:$mode_id:TISInputSourceID" "$info_plist")" != "$mode_id" ]]; then
    return 1
  fi
  printf '%s' "$mode_id"
}

knowtype_bundle_matches_inputmethod_identity() {
  local bundle_path="$1"
  local info_plist="$bundle_path/Contents/Info.plist"
  [[ -f "$info_plist" ]] || return 1

  local bundle_id
  local parent_source_id
  bundle_id="$(knowtype_plist_value "CFBundleIdentifier" "$info_plist")"
  parent_source_id="$(knowtype_plist_value "TISInputSourceID" "$info_plist")"

  if [[ "$bundle_id" == "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" ||
        "$parent_source_id" == "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" ||
        "$parent_source_id" == "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" ]]; then
    return 0
  fi

  local mode_id
  for mode_id in "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" "${KNOWTYPE_LEGACY_INPUT_MODE_IDS[@]}"; do
    if [[ "$(knowtype_plistbuddy_value ":ComponentInputModeDict:tsInputModeListKey:$mode_id:TISInputSourceID" "$info_plist")" == "$mode_id" ]]; then
      return 0
    fi
  done
  return 1
}

knowtype_find_local_inputmethod_bundle_paths() {
  local target_dir
  target_dir="$(knowtype_inputmethod_target_dir)"
  [[ -d "$target_dir" ]] || return 0

  while IFS= read -r bundle_path; do
    [[ -n "$bundle_path" ]] || continue
    if knowtype_bundle_matches_inputmethod_identity "$bundle_path"; then
      knowtype_canonical_bundle_path "$bundle_path"
      printf '\n'
    fi
  done < <(find "$target_dir" -maxdepth 1 \( -type d -o -type l \) -name '*.app' -print 2>/dev/null | sort)
}

knowtype_is_safe_local_inputmethod_bundle_path() {
  local bundle_path="$1"
  local target_dir
  local canonical_dir
  local canonical_path
  target_dir="$(knowtype_inputmethod_target_dir)"
  canonical_dir="$(knowtype_canonical_bundle_path "$target_dir")"
  canonical_path="$(knowtype_canonical_bundle_path "$bundle_path")"

  [[ -d "$bundle_path" ]] || return 1
  [[ "$(dirname "$canonical_path")" == "$canonical_dir" ]] || return 1
  [[ "$canonical_path" == *.app ]] || return 1
  knowtype_bundle_matches_inputmethod_identity "$bundle_path"
}

knowtype_remove_local_inputmethod_bundle_if_safe() {
  local bundle_path="$1"
  local dry_run="${2:-0}"
  if ! knowtype_is_safe_local_inputmethod_bundle_path "$bundle_path"; then
    echo "error: unsafe non-local KnowType bundle path; refusing to remove or replace: $bundle_path" >&2
    return 1
  fi

  if [[ "$dry_run" == "1" ]]; then
    echo "[dry-run] Would remove local KnowType bundle: $bundle_path"
  else
    rm -rf -- "$bundle_path"
    echo "Removed local KnowType bundle: $bundle_path"
  fi
}

knowtype_launchservices_paths_for_identity() {
  [[ -x "$KNOWTYPE_LSREGISTER" ]] || return 0

  "$KNOWTYPE_LSREGISTER" -dump 2>/dev/null | awk -v id="$KNOWTYPE_PARENT_INPUT_SOURCE_ID" '
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
  '
}

knowtype_unregister_launchservices_path() {
  local bundle_path="$1"
  local dry_run="${2:-0}"
  local unregister_path
  [[ -x "$KNOWTYPE_LSREGISTER" ]] || return 0
  unregister_path="$(knowtype_expand_home_path "$(knowtype_strip_lsregister_suffix "$bundle_path")")"
  [[ -n "$unregister_path" ]] || return 0

  if [[ "$dry_run" == "1" ]]; then
    echo "[dry-run] Would unregister LaunchServices record: $unregister_path"
  else
    "$KNOWTYPE_LSREGISTER" -u "$unregister_path" 2>/dev/null || true
    echo "Unregistered LaunchServices record: $unregister_path"
  fi
}

knowtype_register_launchservices_path() {
  local bundle_path="$1"
  local dry_run="${2:-0}"
  [[ -x "$KNOWTYPE_LSREGISTER" && -d "$bundle_path" ]] || return 0

  if [[ "$dry_run" == "1" ]]; then
    echo "[dry-run] Would register LaunchServices record: $bundle_path"
  else
    "$KNOWTYPE_LSREGISTER" -f "$bundle_path" 2>/dev/null || true
  fi
}

knowtype_unregister_launchservices_records_except() {
  local keep_path="$1"
  local dry_run="${2:-0}"
  local canonical_keep=""
  if [[ -n "$keep_path" ]]; then
    canonical_keep="$(knowtype_canonical_bundle_path "$keep_path")"
  fi

  while IFS= read -r bundle_path; do
    [[ -n "$bundle_path" ]] || continue
    local canonical_path
    canonical_path="$(knowtype_canonical_bundle_path "$bundle_path")"
    if [[ -n "$canonical_keep" && "$canonical_path" == "$canonical_keep" ]]; then
      continue
    fi
    knowtype_unregister_launchservices_path "$bundle_path" "$dry_run"
  done < <(knowtype_launchservices_paths_for_identity)
}

knowtype_cleanup_local_duplicate_bundles_except() {
  local keep_path="$1"
  local dry_run="${2:-0}"
  local canonical_keep=""
  if [[ -n "$keep_path" ]]; then
    canonical_keep="$(knowtype_canonical_bundle_path "$keep_path")"
  fi

  while IFS= read -r bundle_path; do
    [[ -n "$bundle_path" ]] || continue
    local canonical_path
    canonical_path="$(knowtype_canonical_bundle_path "$bundle_path")"
    if [[ -n "$canonical_keep" && "$canonical_path" == "$canonical_keep" ]]; then
      continue
    fi
    knowtype_unregister_launchservices_path "$bundle_path" "$dry_run"
    knowtype_remove_local_inputmethod_bundle_if_safe "$bundle_path" "$dry_run"
  done < <(knowtype_find_local_inputmethod_bundle_paths)
}

knowtype_count_nonempty_lines() {
  awk 'NF { count += 1 } END { print count + 0 }'
}
