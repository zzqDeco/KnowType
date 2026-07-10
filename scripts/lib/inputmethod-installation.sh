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
KNOWTYPE_BACKUP_MANIFEST_SCHEMA_VERSION=2

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

knowtype_bundle_executable() {
  local bundle_path="$1"
  knowtype_plist_value "CFBundleExecutable" "$bundle_path/Contents/Info.plist"
}

knowtype_canonical_preferencepane_target_path() {
  local target_dir
  target_dir="$(knowtype_expand_home_path "$(knowtype_preferencepane_target_dir)")"
  [[ ! -L "$target_dir" ]] || return 1
  if [[ -d "$target_dir" ]]; then
    target_dir="$(cd "$target_dir" && pwd -P)"
  elif [[ ! -e "$target_dir" && -d "$(dirname "$target_dir")" ]]; then
    target_dir="$(cd "$(dirname "$target_dir")" && pwd -P)/$(basename "$target_dir")"
  else
    return 1
  fi
  printf '%s/KnowType.prefPane' "$target_dir"
}

knowtype_is_canonical_local_preferencepane_path() {
  local bundle_path="$1"
  local canonical_target
  local bundle_dir
  local canonical_bundle_dir
  canonical_target="$(knowtype_canonical_preferencepane_target_path)" || return 1
  bundle_path="$(knowtype_expand_home_path "$bundle_path")"
  [[ "$(basename "$bundle_path")" == "KnowType.prefPane" ]] || return 1
  bundle_dir="$(dirname "$bundle_path")"
  [[ ! -L "$bundle_dir" ]] || return 1
  if [[ -d "$bundle_dir" ]]; then
    canonical_bundle_dir="$(cd "$bundle_dir" && pwd -P)"
  elif [[ ! -e "$bundle_dir" && -d "$(dirname "$bundle_dir")" ]]; then
    canonical_bundle_dir="$(cd "$(dirname "$bundle_dir")" && pwd -P)/$(basename "$bundle_dir")"
  else
    return 1
  fi
  [[ "$canonical_bundle_dir/KnowType.prefPane" == "$canonical_target" ]]
}

knowtype_bundle_matches_preferencepane_identity() {
  local bundle_path="$1"
  [[ -d "$bundle_path" && ! -L "$bundle_path" ]] || return 1
  [[ "$(knowtype_bundle_identifier "$bundle_path")" == "$KNOWTYPE_PREFPANE_BUNDLE_ID" ]]
}

knowtype_is_safe_local_preferencepane_bundle_path() {
  local bundle_path="$1"
  [[ -d "$bundle_path" && ! -L "$bundle_path" ]] || return 1
  knowtype_is_canonical_local_preferencepane_path "$bundle_path" || return 1
  knowtype_bundle_matches_preferencepane_identity "$bundle_path"
}

knowtype_require_safe_local_preferencepane_if_present() {
  local bundle_path="$1"
  if ! knowtype_is_canonical_local_preferencepane_path "$bundle_path"; then
    echo "error: unsafe PreferencePane target path; refusing to remove or replace: $bundle_path" >&2
    return 1
  fi
  if [[ ! -e "$bundle_path" && ! -L "$bundle_path" ]]; then
    return 0
  fi
  if knowtype_is_safe_local_preferencepane_bundle_path "$bundle_path"; then
    return 0
  fi

  echo "error: foreign or unsafe same-name PreferencePane; refusing to remove or replace: $bundle_path" >&2
  echo "Expected CFBundleIdentifier=$KNOWTYPE_PREFPANE_BUNDLE_ID at the canonical KnowType.prefPane path." >&2
  return 1
}

knowtype_remove_local_preferencepane_bundle_if_safe() {
  local bundle_path="$1"
  local dry_run="${2:-0}"
  knowtype_require_safe_local_preferencepane_if_present "$bundle_path" || return 1
  if [[ ! -e "$bundle_path" && ! -L "$bundle_path" ]]; then
    return 0
  fi

  if [[ "$dry_run" == "1" ]]; then
    echo "[dry-run] Would remove KnowType compatibility PreferencePane: $bundle_path"
  else
    rm -rf -- "$bundle_path"
    echo "Removed KnowType compatibility PreferencePane: $bundle_path"
  fi
}

knowtype_replace_local_preferencepane_bundle_atomically() {
  local source_path="$1"
  local target_path="$2"
  local verify_codesign="${3:-1}"
  local target_dir
  local staged_root=""
  local staged_path=""
  local current_root=""

  knowtype_require_safe_local_preferencepane_if_present "$target_path" || return 1
  knowtype_validate_preferencepane_bundle_for_install "$source_path" "$verify_codesign" || return 1

  target_dir="$(dirname "$target_path")"
  mkdir -p "$target_dir" || return 1
  staged_root="$(mktemp -d "$target_dir/.KnowType.prefPane.install.XXXXXX")" || return 1
  staged_path="$staged_root/KnowType.prefPane"

  if ! cp -R "$source_path" "$staged_path"; then
    rm -rf "$staged_root"
    echo "error: could not stage KnowType.prefPane before replacement" >&2
    return 1
  fi
  if [[ "${KNOWTYPE_TEST_CORRUPT_STAGED_PREFPANE:-0}" == "1" ]]; then
    rm -f "$staged_path/Contents/Info.plist"
  fi
  if ! knowtype_validate_preferencepane_bundle_for_install "$staged_path" "$verify_codesign"; then
    rm -rf "$staged_root"
    echo "error: staged KnowType.prefPane failed validation; the installed pane was not changed" >&2
    return 1
  fi

  if [[ -e "$target_path" || -L "$target_path" ]]; then
    current_root="$(mktemp -d "$target_dir/.KnowType.prefPane.current.XXXXXX")" || {
      rm -rf "$staged_root"
      return 1
    }
    if ! mv "$target_path" "$current_root/KnowType.prefPane"; then
      rm -rf "$staged_root" "$current_root"
      return 1
    fi
  fi

  if ! mv "$staged_path" "$target_path"; then
    if [[ -n "$current_root" && -d "$current_root/KnowType.prefPane" && ! -e "$target_path" ]]; then
      mv "$current_root/KnowType.prefPane" "$target_path" 2>/dev/null || true
    fi
    rm -rf "$staged_root" "$current_root"
    echo "error: could not publish staged KnowType.prefPane; restored the previous pane when available" >&2
    return 1
  fi

  rm -rf "$staged_root" "$current_root"
  echo "Installed KnowType compatibility PreferencePane: $target_path"
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

knowtype_codesign_details() {
  local bundle_path="$1"
  codesign -dvvv "$bundle_path" 2>&1
}

knowtype_codesign_value_from_details() {
  local key="$1"
  local details="$2"
  printf '%s\n' "$details" |
    awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }'
}

knowtype_codesign_requirement() {
  local bundle_path="$1"
  local output
  local requirement
  output="$(codesign -dr - "$bundle_path" 2>&1 || true)"
  requirement="$(
    printf '%s\n' "$output" |
      sed -n -e 's/^designated => //p' -e 's/^# designated => //p' |
      head -n 1
  )"
  if [[ -z "$requirement" ]]; then
    local details
    local cd_hash
    details="$(knowtype_codesign_details "$bundle_path" || true)"
    cd_hash="$(knowtype_codesign_value_from_details "CDHash" "$details")"
    if [[ -n "$cd_hash" ]]; then
      requirement="cdhash H\"$cd_hash\""
    fi
  fi
  printf '%s' "$requirement"
}

knowtype_codesign_identity() {
  local bundle_path="$1"
  local details
  details="$(knowtype_codesign_details "$bundle_path" || true)"

  local identifier
  local team_identifier
  local signature_kind
  local authorities
  identifier="$(knowtype_codesign_value_from_details "Identifier" "$details")"
  team_identifier="$(knowtype_codesign_value_from_details "TeamIdentifier" "$details")"
  authorities="$(
    printf '%s\n' "$details" |
      awk -F= '$1 == "Authority" {
        value = substr($0, index($0, "=") + 1)
        if (out != "") {
          out = out " | "
        }
        out = out value
      } END { print out }'
  )"
  signature_kind="$(knowtype_codesign_value_from_details "Signature" "$details")"
  if [[ -z "$signature_kind" ]] && [[ -n "$authorities" ]]; then
    signature_kind="cms"
  fi

  [[ -n "$identifier" && -n "$signature_kind" ]] || return 1
  printf 'identifier=%s\nteamIdentifier=%s\nsignature=%s\nauthorities=%s' \
    "$identifier" "${team_identifier:-<none>}" "$signature_kind" "${authorities:-<none>}"
}

knowtype_verify_bundle_codesign() {
  local bundle_path="$1"
  if ! command -v codesign >/dev/null 2>&1; then
    echo "error: codesign is required to verify bundle integrity: $bundle_path" >&2
    return 1
  fi

  local output
  if ! output="$(codesign --verify --deep --strict "$bundle_path" 2>&1)"; then
    echo "error: codesign --verify --deep --strict failed for: $bundle_path" >&2
    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
    return 1
  fi
}

knowtype_verify_bundle_signing_requirement() {
  local bundle_path="$1"
  local requirement="$2"
  [[ -n "$requirement" ]] || {
    echo "error: signing requirement is missing for: $bundle_path" >&2
    return 1
  }

  local output
  if ! output="$(codesign --verify --deep --strict -R "=$requirement" "$bundle_path" 2>&1)"; then
    echo "error: bundle does not satisfy its recorded signing requirement: $bundle_path" >&2
    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
    return 1
  fi
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

  local app_bundle_id
  app_bundle_id="$(knowtype_bundle_identifier "$app_path")"
  if [[ "$app_bundle_id" != "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" ]]; then
    echo "error: refusing to back up unexpected input-method bundle identity '$app_bundle_id': $app_path" >&2
    return 1
  fi
  knowtype_require_safe_local_preferencepane_if_present "$prefpane_path" || return 1

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

  knowtype_verify_bundle_codesign "$app_path" || return 1
  if [[ -d "$prefpane_path" ]]; then
    knowtype_validate_preferencepane_bundle_for_install "$prefpane_path" 1 || return 1
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
  if ! cp -R "$app_path" "$backup_dir/KnowType.app"; then
    rm -rf -- "$backup_dir"
    KNOWTYPE_CREATED_BACKUP_ID=""
    KNOWTYPE_CREATED_BACKUP_DIR=""
    return 1
  fi
  local included_prefpane="false"
  if [[ -d "$prefpane_path" ]]; then
    if ! cp -R "$prefpane_path" "$backup_dir/KnowType.prefPane"; then
      rm -rf -- "$backup_dir"
      KNOWTYPE_CREATED_BACKUP_ID=""
      KNOWTYPE_CREATED_BACKUP_DIR=""
      return 1
    fi
    included_prefpane="true"
  fi

  if ! knowtype_verify_bundle_codesign "$backup_dir/KnowType.app"; then
    rm -rf -- "$backup_dir"
    KNOWTYPE_CREATED_BACKUP_ID=""
    KNOWTYPE_CREATED_BACKUP_DIR=""
    return 1
  fi
  if [[ "$included_prefpane" == "true" ]] &&
     ! knowtype_validate_preferencepane_bundle_for_install "$backup_dir/KnowType.prefPane" 1; then
    rm -rf -- "$backup_dir"
    KNOWTYPE_CREATED_BACKUP_ID=""
    KNOWTYPE_CREATED_BACKUP_DIR=""
    return 1
  fi

  local app_backup_path="$backup_dir/KnowType.app"
  local app_checksum
  local app_short_version
  local app_build_version
  local app_signing_requirement
  local app_signing_identity
  app_checksum="$(knowtype_path_checksum "$app_backup_path" || true)"
  app_bundle_id="$(knowtype_bundle_identifier "$app_backup_path")"
  app_short_version="$(knowtype_bundle_short_version "$app_backup_path")"
  app_build_version="$(knowtype_bundle_build_version "$app_backup_path")"
  app_signing_requirement="$(knowtype_codesign_requirement "$app_backup_path")"
  app_signing_identity="$(knowtype_codesign_identity "$app_backup_path" || true)"

  local prefpane_checksum=""
  local prefpane_bundle_id=""
  local prefpane_short_version=""
  local prefpane_build_version=""
  local prefpane_signing_requirement=""
  local prefpane_signing_identity=""
  if [[ "$included_prefpane" == "true" ]]; then
    local prefpane_backup_path="$backup_dir/KnowType.prefPane"
    prefpane_checksum="$(knowtype_path_checksum "$prefpane_backup_path" || true)"
    prefpane_bundle_id="$(knowtype_bundle_identifier "$prefpane_backup_path")"
    prefpane_short_version="$(knowtype_bundle_short_version "$prefpane_backup_path")"
    prefpane_build_version="$(knowtype_bundle_build_version "$prefpane_backup_path")"
    prefpane_signing_requirement="$(knowtype_codesign_requirement "$prefpane_backup_path")"
    prefpane_signing_identity="$(knowtype_codesign_identity "$prefpane_backup_path" || true)"
  fi

  local metadata_complete=1
  if [[ -z "$app_checksum" || -z "$app_bundle_id" || -z "$app_short_version" ||
        -z "$app_build_version" || -z "$app_signing_requirement" || -z "$app_signing_identity" ]]; then
    metadata_complete=0
  fi
  if [[ "$included_prefpane" == "true" ]] &&
     [[ -z "$prefpane_checksum" || -z "$prefpane_bundle_id" || -z "$prefpane_short_version" ||
        -z "$prefpane_build_version" || -z "$prefpane_signing_requirement" || -z "$prefpane_signing_identity" ]]; then
    metadata_complete=0
  fi
  if [[ "$metadata_complete" != "1" ]]; then
    echo "error: could not record complete checksum, version, identity, and signing metadata for backup: $backup_dir" >&2
    rm -rf -- "$backup_dir"
    KNOWTYPE_CREATED_BACKUP_ID=""
    KNOWTYPE_CREATED_BACKUP_DIR=""
    return 1
  fi

  KNOWTYPE_JSON_PAYLOAD="$(
    KNOWTYPE_BACKUP_ID="$backup_id" \
    KNOWTYPE_BACKUP_CREATED_AT="$(knowtype_iso_timestamp)" \
    KNOWTYPE_BACKUP_VERSION="$app_short_version" \
    KNOWTYPE_BACKUP_BUILD="$app_build_version" \
    KNOWTYPE_BACKUP_BUNDLE_ID="$app_bundle_id" \
    KNOWTYPE_BACKUP_APP_CHECKSUM="$app_checksum" \
    KNOWTYPE_BACKUP_APP_SIGNING_REQUIREMENT="$app_signing_requirement" \
    KNOWTYPE_BACKUP_APP_SIGNING_IDENTITY="$app_signing_identity" \
    KNOWTYPE_BACKUP_INCLUDED_PREFPANE="$included_prefpane" \
    KNOWTYPE_BACKUP_PREFPANE_CHECKSUM="$prefpane_checksum" \
    KNOWTYPE_BACKUP_PREFPANE_BUNDLE_ID="$prefpane_bundle_id" \
    KNOWTYPE_BACKUP_PREFPANE_VERSION="$prefpane_short_version" \
    KNOWTYPE_BACKUP_PREFPANE_BUILD="$prefpane_build_version" \
    KNOWTYPE_BACKUP_PREFPANE_SIGNING_REQUIREMENT="$prefpane_signing_requirement" \
    KNOWTYPE_BACKUP_PREFPANE_SIGNING_IDENTITY="$prefpane_signing_identity" \
    KNOWTYPE_BACKUP_RESTORE_COMMAND="./scripts/rollback-inputmethod.sh --to $backup_id" \
    "$KNOWTYPE_PYTHON3" - <<'PY'
import json
import os
included_prefpane = os.environ.get("KNOWTYPE_BACKUP_INCLUDED_PREFPANE") == "true"

def prefpane_value(name):
    return os.environ.get(name, "") if included_prefpane else None

payload = {
    "schemaVersion": 2,
    "backupID": os.environ["KNOWTYPE_BACKUP_ID"],
    "createdAt": os.environ["KNOWTYPE_BACKUP_CREATED_AT"],
    "sourceVersion": os.environ.get("KNOWTYPE_BACKUP_VERSION", ""),
    "sourceBuild": os.environ.get("KNOWTYPE_BACKUP_BUILD", ""),
    "bundleIdentifier": os.environ.get("KNOWTYPE_BACKUP_BUNDLE_ID", ""),
    "appBundleIdentifier": os.environ.get("KNOWTYPE_BACKUP_BUNDLE_ID", ""),
    "appShortVersion": os.environ.get("KNOWTYPE_BACKUP_VERSION", ""),
    "appBuildVersion": os.environ.get("KNOWTYPE_BACKUP_BUILD", ""),
    "appChecksum": os.environ.get("KNOWTYPE_BACKUP_APP_CHECKSUM", ""),
    "appSigningRequirement": os.environ.get("KNOWTYPE_BACKUP_APP_SIGNING_REQUIREMENT", ""),
    "appSigningIdentity": os.environ.get("KNOWTYPE_BACKUP_APP_SIGNING_IDENTITY", ""),
    "includedPrefPane": included_prefpane,
    "prefPaneChecksum": prefpane_value("KNOWTYPE_BACKUP_PREFPANE_CHECKSUM"),
    "prefPaneBundleIdentifier": prefpane_value("KNOWTYPE_BACKUP_PREFPANE_BUNDLE_ID"),
    "prefPaneShortVersion": prefpane_value("KNOWTYPE_BACKUP_PREFPANE_VERSION"),
    "prefPaneBuildVersion": prefpane_value("KNOWTYPE_BACKUP_PREFPANE_BUILD"),
    "prefPaneSigningRequirement": prefpane_value("KNOWTYPE_BACKUP_PREFPANE_SIGNING_REQUIREMENT"),
    "prefPaneSigningIdentity": prefpane_value("KNOWTYPE_BACKUP_PREFPANE_SIGNING_IDENTITY"),
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
    if isinstance(value, bool):
        print("true" if value else "false")
    else:
        print(value)
PY
}

knowtype_backup_manifest_schema_version() {
  local manifest_path="$1"
  [[ -f "$manifest_path" ]] || return 0
  KNOWTYPE_BACKUP_MANIFEST_PATH="$manifest_path" "$KNOWTYPE_PYTHON3" - <<'PY'
import json
import os

try:
    with open(os.environ["KNOWTYPE_BACKUP_MANIFEST_PATH"], encoding="utf-8") as handle:
        value = json.load(handle).get("schemaVersion")
except Exception:
    value = None
if isinstance(value, int) and not isinstance(value, bool):
    print(value)
PY
}

knowtype_validate_backup_manifest_v2_shape() {
  local manifest_path="$1"
  local backup_id="$2"
  KNOWTYPE_BACKUP_MANIFEST_PATH="$manifest_path" \
  KNOWTYPE_BACKUP_EXPECTED_ID="$backup_id" \
  KNOWTYPE_BACKUP_EXPECTED_SCHEMA="$KNOWTYPE_BACKUP_MANIFEST_SCHEMA_VERSION" \
    "$KNOWTYPE_PYTHON3" - <<'PY'
import json
import os
import sys

path = os.environ["KNOWTYPE_BACKUP_MANIFEST_PATH"]
expected_id = os.environ["KNOWTYPE_BACKUP_EXPECTED_ID"]
expected_schema = int(os.environ["KNOWTYPE_BACKUP_EXPECTED_SCHEMA"])

def fail(message):
    print(f"error: backup manifest validation failed: {message}: {path}", file=sys.stderr)
    raise SystemExit(1)

try:
    with open(path, encoding="utf-8") as handle:
        manifest = json.load(handle)
except Exception as error:
    fail(f"invalid JSON ({type(error).__name__})")

if not isinstance(manifest, dict):
    fail("root must be an object")
if manifest.get("schemaVersion") != expected_schema:
    fail(f"schemaVersion must be {expected_schema}")
if manifest.get("backupID") != expected_id:
    fail("backupID does not match its directory")
if manifest.get("restoreCommand") != f"./scripts/rollback-inputmethod.sh --to {expected_id}":
    fail("restoreCommand does not match backupID")

required_strings = (
    "backupID",
    "createdAt",
    "sourceVersion",
    "sourceBuild",
    "bundleIdentifier",
    "appBundleIdentifier",
    "appShortVersion",
    "appBuildVersion",
    "appChecksum",
    "appSigningRequirement",
    "appSigningIdentity",
    "restoreCommand",
)
for key in required_strings:
    if not isinstance(manifest.get(key), str) or not manifest[key]:
        fail(f"required integrity field '{key}' is missing or empty")

if manifest["sourceVersion"] != manifest["appShortVersion"]:
    fail("sourceVersion and appShortVersion differ")
if manifest["sourceBuild"] != manifest["appBuildVersion"]:
    fail("sourceBuild and appBuildVersion differ")
if manifest["bundleIdentifier"] != manifest["appBundleIdentifier"]:
    fail("bundleIdentifier and appBundleIdentifier differ")

included_prefpane = manifest.get("includedPrefPane")
if not isinstance(included_prefpane, bool):
    fail("includedPrefPane must be a boolean")

prefpane_fields = (
    "prefPaneChecksum",
    "prefPaneBundleIdentifier",
    "prefPaneShortVersion",
    "prefPaneBuildVersion",
    "prefPaneSigningRequirement",
    "prefPaneSigningIdentity",
)
for key in prefpane_fields:
    if key not in manifest:
        fail(f"required optional-artifact field '{key}' is missing")
    value = manifest[key]
    if included_prefpane:
        if not isinstance(value, str) or not value:
            fail(f"PreferencePane integrity field '{key}' is missing or empty")
    elif value is not None:
        fail(f"PreferencePane integrity field '{key}' must be null when no pane is included")
PY
}

knowtype_require_backup_metadata_match() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [[ -z "$expected" || -z "$actual" || "$expected" != "$actual" ]]; then
    echo "error: backup integrity mismatch for $label" >&2
    echo "Expected: ${expected:-<missing>}" >&2
    echo "Actual: ${actual:-<missing>}" >&2
    return 1
  fi
}

KNOWTYPE_BACKUP_VALIDATION_STATUS=""

knowtype_validate_install_backup_for_restore() {
  local backup_dir="$1"
  local allow_unverified_legacy="${2:-0}"
  KNOWTYPE_BACKUP_VALIDATION_STATUS=""

  if ! knowtype_is_managed_backup_dir "$backup_dir"; then
    echo "error: backup directory or manifest identity is invalid: $backup_dir" >&2
    return 1
  fi

  local backup_id
  local manifest_path
  local schema_version
  local app_path
  local prefpane_path
  backup_id="$(basename "$backup_dir")"
  manifest_path="$backup_dir/manifest.json"
  schema_version="$(knowtype_backup_manifest_schema_version "$manifest_path")"
  app_path="$backup_dir/KnowType.app"
  prefpane_path="$backup_dir/KnowType.prefPane"

  if [[ "$schema_version" == "1" ]]; then
    if [[ "$allow_unverified_legacy" != "1" ]]; then
      echo "error: legacy backup manifest lacks required integrity metadata: $manifest_path" >&2
      echo "Rollback fails closed. Use --allow-unverified-backup only after independently trusting this legacy backup." >&2
      return 1
    fi

    echo "WARNING: ALLOWING AN UNVERIFIED LEGACY BACKUP" >&2
    echo "WARNING: checksum, recorded version/build, and recorded signing identity cannot be fully validated." >&2
    if [[ "$(knowtype_bundle_identifier "$app_path")" != "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" ]]; then
      echo "error: legacy backup app does not match CFBundleIdentifier=$KNOWTYPE_PARENT_INPUT_SOURCE_ID" >&2
      return 1
    fi
    knowtype_validate_inputmethod_bundle_for_install "$app_path" 1 || return 1
    if [[ -e "$prefpane_path" || -L "$prefpane_path" ]]; then
      knowtype_validate_preferencepane_bundle_for_install "$prefpane_path" 1 || return 1
    fi
    KNOWTYPE_BACKUP_VALIDATION_STATUS="legacy-unverified-override"
    return 0
  fi

  if [[ "$schema_version" != "$KNOWTYPE_BACKUP_MANIFEST_SCHEMA_VERSION" ]]; then
    echo "error: unsupported or missing backup manifest schemaVersion: ${schema_version:-<missing>}" >&2
    echo "--allow-unverified-backup applies only to schemaVersion 1 legacy backups." >&2
    return 1
  fi

  knowtype_validate_backup_manifest_v2_shape "$manifest_path" "$backup_id" || return 1

  local included_prefpane
  included_prefpane="$(knowtype_backup_manifest_field "$manifest_path" "includedPrefPane")"
  if [[ "$included_prefpane" == "true" && ! -d "$prefpane_path" ]]; then
    echo "error: backup manifest requires KnowType.prefPane but the artifact is missing: $backup_dir" >&2
    return 1
  fi
  if [[ "$included_prefpane" == "false" && ( -e "$prefpane_path" || -L "$prefpane_path" ) ]]; then
    echo "error: backup contains an unexpected KnowType.prefPane not recorded by its manifest: $backup_dir" >&2
    return 1
  fi

  local app_bundle_id
  local app_short_version
  local app_build_version
  local app_checksum
  local app_signing_requirement
  local app_signing_identity
  app_bundle_id="$(knowtype_bundle_identifier "$app_path")"
  app_short_version="$(knowtype_bundle_short_version "$app_path")"
  app_build_version="$(knowtype_bundle_build_version "$app_path")"
  app_checksum="$(knowtype_path_checksum "$app_path" || true)"
  app_signing_requirement="$(knowtype_codesign_requirement "$app_path")"
  app_signing_identity="$(knowtype_codesign_identity "$app_path" || true)"

  knowtype_require_backup_metadata_match \
    "app bundle identifier" \
    "$(knowtype_backup_manifest_field "$manifest_path" "appBundleIdentifier")" \
    "$app_bundle_id" || return 1
  if [[ "$app_bundle_id" != "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" ]]; then
    echo "error: backup app has unexpected product identity '$app_bundle_id'" >&2
    return 1
  fi
  knowtype_require_backup_metadata_match \
    "app short version" \
    "$(knowtype_backup_manifest_field "$manifest_path" "appShortVersion")" \
    "$app_short_version" || return 1
  knowtype_require_backup_metadata_match \
    "app build version" \
    "$(knowtype_backup_manifest_field "$manifest_path" "appBuildVersion")" \
    "$app_build_version" || return 1
  knowtype_require_backup_metadata_match \
    "app checksum" \
    "$(knowtype_backup_manifest_field "$manifest_path" "appChecksum")" \
    "$app_checksum" || return 1
  knowtype_require_backup_metadata_match \
    "app signing requirement" \
    "$(knowtype_backup_manifest_field "$manifest_path" "appSigningRequirement")" \
    "$app_signing_requirement" || return 1
  knowtype_require_backup_metadata_match \
    "app signing identity" \
    "$(knowtype_backup_manifest_field "$manifest_path" "appSigningIdentity")" \
    "$app_signing_identity" || return 1
  knowtype_validate_inputmethod_bundle_for_install "$app_path" 0 || return 1
  knowtype_verify_bundle_codesign "$app_path" || return 1
  knowtype_verify_bundle_signing_requirement \
    "$app_path" \
    "$(knowtype_backup_manifest_field "$manifest_path" "appSigningRequirement")" || return 1

  if [[ "$included_prefpane" == "true" ]]; then
    local prefpane_bundle_id
    local prefpane_short_version
    local prefpane_build_version
    local prefpane_checksum
    local prefpane_signing_requirement
    local prefpane_signing_identity
    prefpane_bundle_id="$(knowtype_bundle_identifier "$prefpane_path")"
    prefpane_short_version="$(knowtype_bundle_short_version "$prefpane_path")"
    prefpane_build_version="$(knowtype_bundle_build_version "$prefpane_path")"
    prefpane_checksum="$(knowtype_path_checksum "$prefpane_path" || true)"
    prefpane_signing_requirement="$(knowtype_codesign_requirement "$prefpane_path")"
    prefpane_signing_identity="$(knowtype_codesign_identity "$prefpane_path" || true)"

    knowtype_require_backup_metadata_match \
      "PreferencePane bundle identifier" \
      "$(knowtype_backup_manifest_field "$manifest_path" "prefPaneBundleIdentifier")" \
      "$prefpane_bundle_id" || return 1
    if [[ "$prefpane_bundle_id" != "$KNOWTYPE_PREFPANE_BUNDLE_ID" ]]; then
      echo "error: backup PreferencePane has unexpected product identity '$prefpane_bundle_id'" >&2
      return 1
    fi
    knowtype_require_backup_metadata_match \
      "PreferencePane short version" \
      "$(knowtype_backup_manifest_field "$manifest_path" "prefPaneShortVersion")" \
      "$prefpane_short_version" || return 1
    knowtype_require_backup_metadata_match \
      "PreferencePane build version" \
      "$(knowtype_backup_manifest_field "$manifest_path" "prefPaneBuildVersion")" \
      "$prefpane_build_version" || return 1
    knowtype_require_backup_metadata_match \
      "PreferencePane checksum" \
      "$(knowtype_backup_manifest_field "$manifest_path" "prefPaneChecksum")" \
      "$prefpane_checksum" || return 1
    knowtype_require_backup_metadata_match \
      "PreferencePane signing requirement" \
      "$(knowtype_backup_manifest_field "$manifest_path" "prefPaneSigningRequirement")" \
      "$prefpane_signing_requirement" || return 1
    knowtype_require_backup_metadata_match \
      "PreferencePane signing identity" \
      "$(knowtype_backup_manifest_field "$manifest_path" "prefPaneSigningIdentity")" \
      "$prefpane_signing_identity" || return 1
    knowtype_validate_preferencepane_bundle_for_install "$prefpane_path" 0 || return 1
    knowtype_verify_bundle_codesign "$prefpane_path" || return 1
    knowtype_verify_bundle_signing_requirement \
      "$prefpane_path" \
      "$(knowtype_backup_manifest_field "$manifest_path" "prefPaneSigningRequirement")" || return 1
  fi

  KNOWTYPE_BACKUP_VALIDATION_STATUS="verified-schema-$KNOWTYPE_BACKUP_MANIFEST_SCHEMA_VERSION"
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

knowtype_validate_preferencepane_bundle_for_install() {
  local bundle_path="$1"
  local verify_codesign="${2:-1}"
  if [[ ! -d "$bundle_path" || -L "$bundle_path" ]]; then
    echo "error: KnowType.prefPane bundle is missing or is a symlink: $bundle_path" >&2
    return 1
  fi
  if ! knowtype_bundle_matches_preferencepane_identity "$bundle_path"; then
    echo "error: PreferencePane does not match CFBundleIdentifier=$KNOWTYPE_PREFPANE_BUNDLE_ID: $bundle_path" >&2
    return 1
  fi

  local executable
  executable="$(knowtype_bundle_executable "$bundle_path")"
  if [[ -z "$executable" || ! -x "$bundle_path/Contents/MacOS/$executable" ]]; then
    echo "error: PreferencePane executable is missing or not executable in: $bundle_path" >&2
    return 1
  fi
  if [[ "$verify_codesign" == "1" ]]; then
    knowtype_verify_bundle_codesign "$bundle_path"
  fi
}

knowtype_validate_app_preferencepane_version_consistency() {
  local app_path="$1"
  local prefpane_path="$2"
  local app_version
  local app_build
  local prefpane_version
  local prefpane_build
  app_version="$(knowtype_bundle_short_version "$app_path")"
  app_build="$(knowtype_bundle_build_version "$app_path")"
  prefpane_version="$(knowtype_bundle_short_version "$prefpane_path")"
  prefpane_build="$(knowtype_bundle_build_version "$prefpane_path")"

  if [[ -z "$app_version" || -z "$app_build" || -z "$prefpane_version" || -z "$prefpane_build" ]]; then
    echo "error: app/PreferencePane version consistency check requires non-empty short version and build metadata" >&2
    return 1
  fi
  if [[ "$app_version" != "$prefpane_version" || "$app_build" != "$prefpane_build" ]]; then
    echo "error: app/PreferencePane version mismatch: app=$app_version ($app_build), prefPane=$prefpane_version ($prefpane_build)" >&2
    return 1
  fi
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
  local visible_mode_ids
  if ! visible_mode_ids="$(knowtype_bundle_visible_input_mode_ids "$bundle_path")"; then
    visible_mode_ids=""
  fi
  local visible_mode_count
  visible_mode_count="$(printf '%s\n' "$visible_mode_ids" | awk 'NF { count++ } END { print count + 0 }')"
  local visible_mode_id
  visible_mode_id="$(printf '%s\n' "$visible_mode_ids" | sed -n '1p')"
  if [[ -z "$visible_mode_id" || "$visible_mode_id" == "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" ]]; then
    echo "error: input-method bundle does not declare a menu-visible input mode: $bundle_path" >&2
    return 1
  fi
  if [[ "$visible_mode_count" != "1" ]]; then
    echo "error: input-method bundle declares $visible_mode_count menu-visible input modes (expected exactly one '$KNOWTYPE_ACTIVE_INPUT_MODE_ID'): $bundle_path" >&2
    return 1
  fi
  if [[ "$visible_mode_id" != "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" ]]; then
    echo "error: input-method bundle declares unsupported menu-visible input mode '$visible_mode_id' (expected '$KNOWTYPE_ACTIVE_INPUT_MODE_ID'): $bundle_path" >&2
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
  if [[ "$verify_codesign" == "1" ]]; then
    knowtype_verify_bundle_codesign "$bundle_path"
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

knowtype_bundle_visible_input_mode_ids() {
  local bundle_path="$1"
  local info_plist="$bundle_path/Contents/Info.plist"
  [[ -f "$info_plist" ]] || return 1

  local index=0
  local found=0
  local mode_id
  while :; do
    mode_id="$(knowtype_plistbuddy_value ":ComponentInputModeDict:tsVisibleInputModeOrderedArrayKey:$index" "$info_plist")"
    if [[ -z "$mode_id" ]]; then
      break
    fi
    if [[ "$(knowtype_plistbuddy_value ":ComponentInputModeDict:tsInputModeListKey:$mode_id:TISInputSourceID" "$info_plist")" != "$mode_id" ]]; then
      return 1
    fi
    printf '%s\n' "$mode_id"
    found=1
    index=$((index + 1))
  done
  [[ "$found" == "1" ]]
}

knowtype_bundle_visible_input_mode_id() {
  local bundle_path="$1"
  knowtype_bundle_visible_input_mode_ids "$bundle_path" | sed -n '1p'
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
