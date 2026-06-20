#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR"
source "$SCRIPTS_DIR/lib/inputsource-ids.sh"
source "$SCRIPTS_DIR/lib/inputsource-tool.sh"
source "$SCRIPTS_DIR/lib/inputmethod-installation.sh"

DRY_RUN=0
CONFIGURATION="${CONFIGURATION:-release}"
WITH_PREFPANE="${KNOWTYPE_INSTALL_PREFPANE:-0}"
SOURCE_MODE="build"
FROM_BUNDLE=""
FROM_RELEASE_ZIP=""
FROM_DMG_PAYLOAD=""
BACKUP_ENABLED=1
VERIFY_ENABLED=1
KEEP_BACKUPS="$KNOWTYPE_DEFAULT_BACKUP_RETENTION"

usage() {
  cat <<'EOF'
Usage: scripts/install-inputmethod.sh [options]

Builds and installs KnowType.app into ~/Library/Input Methods, then uses the
dedicated input-source helper to register and enable the input source without
launching the input method host. KnowType-specific settings are opened from the
input-method menu's KnowType Settings item.

Options:
  --configuration debug|release  SwiftPM build configuration. Defaults to CONFIGURATION or release.
  --with-prefpane                Also build/install the compatibility KnowType.prefPane.
  --from-bundle PATH             Install an existing KnowType.app instead of building from source.
  --from-release-zip PATH        Install KnowType.app from a release zip and validate release metadata when present.
  --from-dmg-payload PATH        Install from a mounted Developer Preview DMG payload root.
  --no-backup                    Replace without creating an app/prefPane backup.
  --keep-backups N               Keep the newest N app backups. Defaults to 3.
  --no-verify                    Skip codesign verification during preflight.
  --dry-run                      Print install, backup, and cache actions without changing files.
  -h, --help                     Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
    --configuration)
      if (($# < 2)); then
        echo "error: --configuration requires a value" >&2
        exit 2
      fi
      CONFIGURATION="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --with-prefpane)
      WITH_PREFPANE=1
      shift
      ;;
    --from-bundle)
      if (($# < 2)); then
        echo "error: --from-bundle requires a path" >&2
        exit 2
      fi
      SOURCE_MODE="bundle"
      FROM_BUNDLE="$2"
      shift 2
      ;;
    --from-release-zip)
      if (($# < 2)); then
        echo "error: --from-release-zip requires a path" >&2
        exit 2
      fi
      SOURCE_MODE="release-zip"
      FROM_RELEASE_ZIP="$2"
      shift 2
      ;;
    --from-dmg-payload)
      if (($# < 2)); then
        echo "error: --from-dmg-payload requires a path" >&2
        exit 2
      fi
      SOURCE_MODE="dmg-dev-preview"
      FROM_DMG_PAYLOAD="$2"
      shift 2
      ;;
    --no-backup)
      BACKUP_ENABLED=0
      shift
      ;;
    --keep-backups)
      if (($# < 2)); then
        echo "error: --keep-backups requires a value" >&2
        exit 2
      fi
      KEEP_BACKUPS="$2"
      shift 2
      ;;
    --no-verify)
      VERIFY_ENABLED=0
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

case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "error: --configuration must be debug or release" >&2
    exit 2
    ;;
esac

case "$WITH_PREFPANE" in
  1|true|TRUE|yes|YES) WITH_PREFPANE=1 ;;
  0|false|FALSE|no|NO) WITH_PREFPANE=0 ;;
  *)
    echo "error: KNOWTYPE_INSTALL_PREFPANE must be 0/1, true/false, or yes/no" >&2
    exit 2
    ;;
esac

source_path_count=0
[[ -n "$FROM_BUNDLE" ]] && source_path_count=$((source_path_count + 1))
[[ -n "$FROM_RELEASE_ZIP" ]] && source_path_count=$((source_path_count + 1))
[[ -n "$FROM_DMG_PAYLOAD" ]] && source_path_count=$((source_path_count + 1))
if (( source_path_count > 1 )); then
  echo "error: --from-bundle, --from-release-zip, and --from-dmg-payload are mutually exclusive" >&2
  exit 2
fi
if [[ ! "$KEEP_BACKUPS" =~ ^[0-9]+$ ]]; then
  echo "error: --keep-backups must be a non-negative integer" >&2
  exit 2
fi

LOCAL_BUILD_VERSION="${KNOWTYPE_BUNDLE_BUILD_VERSION:-$(date +%Y%m%d%H%M%S)}"
TARGET_DIR="$(knowtype_inputmethod_target_dir)"
TARGET_PATH="$(knowtype_inputmethod_target_path)"
PREFPANE_TARGET_DIR="$(knowtype_preferencepane_target_dir)"
PREFPANE_TARGET_PATH="$(knowtype_preferencepane_target_path)"
REMOVED_STALE_PREFPANE=0
SOURCE_BUNDLE_PATH=""
SOURCE_PREFPANE_PATH=""
SOURCE_GIT_COMMIT=""
SOURCE_GIT_TAG=""
SOURCE_RELEASE_MANIFEST=""
SOURCE_RELEASE_MANIFEST_DIGEST=""
SOURCE_TEMP_DIR=""
INPUTSOURCE_TOOL=""
INSTALL_SUCCEEDED=0
BACKUP_ID=""
BACKUP_DIR=""

install_state_source() {
  if [[ "$SOURCE_MODE" == "build" ]]; then
    printf 'local-build'
  else
    printf '%s' "$SOURCE_MODE"
  fi
}

cleanup_source_temp() {
  if [[ -n "$SOURCE_TEMP_DIR" && -d "$SOURCE_TEMP_DIR" ]]; then
    rm -rf "$SOURCE_TEMP_DIR"
  fi
}

rollback_failed_install() {
  if (( INSTALL_SUCCEEDED == 1 || DRY_RUN == 1 )); then
    return 0
  fi
  if [[ -n "$BACKUP_DIR" && ( -d "$BACKUP_DIR/KnowType.app" || -d "$BACKUP_DIR/KnowType.prefPane" ) ]]; then
    echo "Install failed; restoring previous KnowType backup: $BACKUP_ID" >&2
    local app_stage=""
    local current_stage=""
    local restored_app=0
    if [[ -d "$BACKUP_DIR/KnowType.app" ]]; then
      app_stage="$(mktemp -d "$TARGET_DIR/.KnowType.failed-install.app.XXXXXX")" || return 0
      if ! cp -R "$BACKUP_DIR/KnowType.app" "$app_stage/KnowType.app"; then
        rm -rf "$app_stage"
        return 0
      fi
      if [[ -e "$TARGET_PATH" || -L "$TARGET_PATH" ]]; then
        if ! knowtype_is_safe_local_inputmethod_bundle_path "$TARGET_PATH"; then
          rm -rf "$app_stage"
          return 0
        fi
        current_stage="$(mktemp -d "$TARGET_DIR/.KnowType.failed-install.current.XXXXXX")" || {
          rm -rf "$app_stage"
          return 0
        }
        if ! mv "$TARGET_PATH" "$current_stage/KnowType.app"; then
          rm -rf "$app_stage" "$current_stage"
          return 0
        fi
      fi
      if ! mv "$app_stage/KnowType.app" "$TARGET_PATH"; then
        if [[ -n "$current_stage" && -d "$current_stage/KnowType.app" && ! -e "$TARGET_PATH" ]]; then
          mv "$current_stage/KnowType.app" "$TARGET_PATH" 2>/dev/null || true
        fi
        rm -rf "$app_stage" "$current_stage"
        return 0
      fi
      rm -rf "$app_stage" "$current_stage"
      restored_app=1
    fi
    if [[ -d "$BACKUP_DIR/KnowType.prefPane" ]]; then
      mkdir -p "$PREFPANE_TARGET_DIR"
      rm -rf -- "$PREFPANE_TARGET_PATH"
      cp -R "$BACKUP_DIR/KnowType.prefPane" "$PREFPANE_TARGET_PATH"
    else
      rm -rf -- "$PREFPANE_TARGET_PATH"
    fi
    if (( restored_app == 1 )); then
      knowtype_register_launchservices_path "$TARGET_PATH" 0
    fi
  fi
}

trap 'rollback_failed_install; cleanup_source_temp' EXIT

inputsource_tool_path() {
  if [[ -z "$INPUTSOURCE_TOOL" ]]; then
    INPUTSOURCE_TOOL="$(knowtype_inputsource_tool "$ROOT_DIR")"
  fi
  printf '%s\n' "$INPUTSOURCE_TOOL"
}

require_input_method_host_stopped() {
  if knowtype_input_method_host_is_running; then
    echo "error: KnowTypeInputMethodApp is running." >&2
    echo "Switch to another input source and quit the running KnowType host, then rerun install." >&2
    echo "The default installer will not kill the host because process shutdown can flush Rime user data." >&2
    exit 1
  fi
}

knowtype_input_method_host_is_running() {
  local command
  while IFS= read -r command; do
    case "$command" in
      KnowTypeInputMethodApp|KnowTypeInputMethodApp\ *|*/KnowTypeInputMethodApp|*/KnowTypeInputMethodApp\ *)
        return 0
        ;;
    esac
  done < <(ps -axo command= 2>/dev/null)
  return 1
}

switch_away_before_replace() {
  local tool
  tool="$(inputsource_tool_path)" || return 0
  local args=(
    switch-away
    --prefix "$KNOWTYPE_PARENT_INPUT_SOURCE_ID"
    --fallback-id "$KNOWTYPE_FALLBACK_INPUT_SOURCE_ID"
    --parent-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID"
    --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID"
  )
  local legacy_id
  for legacy_id in "${KNOWTYPE_LEGACY_INPUT_MODE_IDS[@]}"; do
    args+=(--legacy-mode-id "$legacy_id")
  done
  "$tool" "${args[@]}" >/dev/null 2>&1 || true
}

purge_legacy_best_effort() {
  local tool
  if ! tool="$(inputsource_tool_path)"; then
    echo "warning: input-source helper is unavailable; continuing without legacy input-source cleanup" >&2
    return 0
  fi
  if ! "$tool" purge-legacy \
    --path "$TARGET_PATH" \
    --parent-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
    --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID"; then
    echo "warning: input-source legacy cleanup failed; continuing so diagnostics can report the persisted state" >&2
  fi
}

bootstrap_input_source_best_effort() {
  local tool
  if ! tool="$(inputsource_tool_path)"; then
    echo "warning: input-source helper is unavailable; continuing without input-source bootstrap" >&2
    return 0
  fi
  if ! "$tool" bootstrap \
    --path "$TARGET_PATH" \
    --parent-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
    --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID"; then
    echo "warning: input-source bootstrap failed; continuing so diagnostics can report the persisted state" >&2
  fi
}

repair_preferences_best_effort() {
  local tool
  if ! tool="$(inputsource_tool_path)"; then
    echo "warning: input-source helper is unavailable; continuing so diagnostics can run" >&2
    return 0
  fi
  if ! "$tool" repair-preferences \
    --bundle-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
    --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" \
    --include-history \
    --add-active; then
    echo "warning: input-source preference repair failed; continuing so diagnostics can run" >&2
  fi
}

discover_release_manifest() {
  local zip_path="$1"
  local extracted_root="$2"
  knowtype_discover_release_manifest "$zip_path" "$extracted_root"
}

release_manifest_field() {
  local manifest_path="$1"
  local field_path="$2"
  KNOWTYPE_RELEASE_MANIFEST="$manifest_path" KNOWTYPE_RELEASE_MANIFEST_FIELD="$field_path" python3 - <<'PY'
import json
import os

with open(os.environ["KNOWTYPE_RELEASE_MANIFEST"], encoding="utf-8") as handle:
    value = json.load(handle)
for component in os.environ["KNOWTYPE_RELEASE_MANIFEST_FIELD"].split("."):
    if isinstance(value, dict):
        value = value.get(component)
    else:
        value = None
        break
if value is not None:
    print(value)
PY
}

validate_release_manifest_metadata() {
  local manifest_path="$1"
  local bundle_path="$2"
  local prefpane_path="$3"
  local app_bundle_id app_version app_build
  app_bundle_id="$(knowtype_bundle_identifier "$bundle_path")"
  app_version="$(knowtype_bundle_short_version "$bundle_path")"
  app_build="$(knowtype_bundle_build_version "$bundle_path")"

  local prefpane_bundle_id="" prefpane_version="" prefpane_build=""
  if [[ -n "$prefpane_path" && -d "$prefpane_path" ]]; then
    prefpane_bundle_id="$(knowtype_bundle_identifier "$prefpane_path")"
    prefpane_version="$(knowtype_bundle_short_version "$prefpane_path")"
    prefpane_build="$(knowtype_bundle_build_version "$prefpane_path")"
  fi

  KNOWTYPE_RELEASE_MANIFEST="$manifest_path" \
    KNOWTYPE_RELEASE_APP_BUNDLE_ID="$app_bundle_id" \
    KNOWTYPE_RELEASE_APP_VERSION="$app_version" \
    KNOWTYPE_RELEASE_APP_BUILD="$app_build" \
    KNOWTYPE_RELEASE_PREFPANE_PATH="$prefpane_path" \
    KNOWTYPE_RELEASE_PREFPANE_BUNDLE_ID="$prefpane_bundle_id" \
    KNOWTYPE_RELEASE_PREFPANE_VERSION="$prefpane_version" \
    KNOWTYPE_RELEASE_PREFPANE_BUILD="$prefpane_build" \
    python3 - <<'PY'
import json
import os
import sys

def fail(message: str) -> None:
    print(f"error: release-manifest.json validation failed: {message}", file=sys.stderr)
    sys.exit(1)

with open(os.environ["KNOWTYPE_RELEASE_MANIFEST"], encoding="utf-8") as handle:
    manifest = json.load(handle)

bundles = manifest.get("bundles")
if not isinstance(bundles, list):
    fail("missing bundles array")

def bundle_entries(path: str):
    return [entry for entry in bundles if isinstance(entry, dict) and entry.get("path") == path]

def require_match(entry: dict, key: str, expected: str, label: str) -> None:
    actual = entry.get(key)
    if actual != expected:
        fail(f"{label} mismatch for {entry.get('path', '<unknown>')}: manifest has {actual!r}, bundle has {expected!r}")

app_entries = bundle_entries("KnowType.app")
if len(app_entries) != 1:
    fail(f"expected exactly one KnowType.app metadata entry, found {len(app_entries)}")
app = app_entries[0]
require_match(app, "bundleIdentifier", os.environ["KNOWTYPE_RELEASE_APP_BUNDLE_ID"], "bundleIdentifier")
require_match(app, "shortVersion", os.environ["KNOWTYPE_RELEASE_APP_VERSION"], "shortVersion")
require_match(app, "buildVersion", os.environ["KNOWTYPE_RELEASE_APP_BUILD"], "buildVersion")

if os.environ.get("KNOWTYPE_RELEASE_PREFPANE_PATH"):
    prefpane_entries = bundle_entries("KnowType.prefPane")
    if len(prefpane_entries) != 1:
        fail(f"expected exactly one KnowType.prefPane metadata entry, found {len(prefpane_entries)}")
    pane = prefpane_entries[0]
    require_match(pane, "bundleIdentifier", os.environ["KNOWTYPE_RELEASE_PREFPANE_BUNDLE_ID"], "prefPane bundleIdentifier")
    require_match(pane, "shortVersion", os.environ["KNOWTYPE_RELEASE_PREFPANE_VERSION"], "prefPane shortVersion")
    require_match(pane, "buildVersion", os.environ["KNOWTYPE_RELEASE_PREFPANE_BUILD"], "prefPane buildVersion")
PY
}

validate_release_zip_checksum_if_available() {
  local manifest_path="$1"
  local zip_path="$2"
  local checksum_name checksum_path expected actual
  checksum_name="$(release_manifest_field "$manifest_path" "artifacts.checksum")"
  [[ -n "$checksum_name" ]] || return 0
  checksum_path="$(dirname "$zip_path")/$checksum_name"
  if [[ ! -f "$checksum_path" ]]; then
    echo "warning: release checksum file listed by manifest was not found: $checksum_path" >&2
    return 0
  fi
  expected="$(awk 'NF {print $1; exit}' "$checksum_path")"
  actual="$(shasum -a 256 "$zip_path" | awk '{print $1}')"
  if [[ -z "$expected" || "$expected" != "$actual" ]]; then
    echo "error: release zip checksum does not match $checksum_path" >&2
    exit 1
  fi
}

prepare_source_artifacts() {
  case "$SOURCE_MODE" in
    build)
      SOURCE_GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true)"
      SOURCE_GIT_TAG="$(git -C "$ROOT_DIR" describe --tags --exact-match HEAD 2>/dev/null || true)"
      SOURCE_BUNDLE_PATH="$(KNOWTYPE_BUNDLE_BUILD_VERSION="$LOCAL_BUILD_VERSION" "$SCRIPTS_DIR/build-inputmethod-bundle.sh" --configuration "$CONFIGURATION" | tail -n 1)"
      if (( WITH_PREFPANE == 1 )); then
        SOURCE_PREFPANE_PATH="$("$SCRIPTS_DIR/build-preference-pane.sh" --configuration "$CONFIGURATION" | tail -n 1)"
      fi
      ;;
    bundle)
      SOURCE_BUNDLE_PATH="$(knowtype_canonical_bundle_path "$FROM_BUNDLE")"
      ;;
    release-zip)
      command -v ditto >/dev/null 2>&1 || {
        echo "error: ditto is required for --from-release-zip" >&2
        exit 2
      }
      SOURCE_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/knowtype-release-install.XXXXXX")"
      ditto -x -k "$FROM_RELEASE_ZIP" "$SOURCE_TEMP_DIR"
      local source_bundle_count=0
      while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        source_bundle_count=$((source_bundle_count + 1))
        if [[ -z "$SOURCE_BUNDLE_PATH" ]]; then
          SOURCE_BUNDLE_PATH="$candidate"
        fi
      done < <(find "$SOURCE_TEMP_DIR" -maxdepth 4 -type d -name 'KnowType.app' -print 2>/dev/null)
      if (( source_bundle_count != 1 )); then
        echo "error: release zip must contain exactly one KnowType.app bundle; found $source_bundle_count" >&2
        exit 1
      fi
      local source_prefpane_count=0
      while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        source_prefpane_count=$((source_prefpane_count + 1))
        if [[ -z "$SOURCE_PREFPANE_PATH" ]]; then
          SOURCE_PREFPANE_PATH="$candidate"
        fi
      done < <(find "$SOURCE_TEMP_DIR" -maxdepth 4 -type d -name 'KnowType.prefPane' -print 2>/dev/null)
      if (( source_prefpane_count > 1 )); then
        echo "error: release zip must contain at most one KnowType.prefPane bundle; found $source_prefpane_count" >&2
        exit 1
      fi
      SOURCE_RELEASE_MANIFEST="$(discover_release_manifest "$FROM_RELEASE_ZIP" "$SOURCE_TEMP_DIR")"
      if [[ -n "$SOURCE_RELEASE_MANIFEST" ]]; then
        SOURCE_RELEASE_MANIFEST_DIGEST="$(shasum -a 256 "$SOURCE_RELEASE_MANIFEST" | awk '{print $1}')"
        validate_release_manifest_metadata "$SOURCE_RELEASE_MANIFEST" "$SOURCE_BUNDLE_PATH" "$SOURCE_PREFPANE_PATH"
        validate_release_zip_checksum_if_available "$SOURCE_RELEASE_MANIFEST" "$FROM_RELEASE_ZIP"
        SOURCE_GIT_COMMIT="$(release_manifest_field "$SOURCE_RELEASE_MANIFEST" "releaseCommit")"
        SOURCE_GIT_TAG="$(release_manifest_field "$SOURCE_RELEASE_MANIFEST" "tag")"
      else
        echo "warning: release-manifest.json was not found in or beside the release zip; install-state will record release-zip without commit metadata" >&2
      fi
      ;;
    dmg-dev-preview)
      local payload_root
      payload_root="$(knowtype_canonical_bundle_path "$FROM_DMG_PAYLOAD")"
      SOURCE_BUNDLE_PATH="$payload_root/Payload/KnowType.app"
      if [[ -d "$payload_root/Payload/KnowType.prefPane" ]]; then
        SOURCE_PREFPANE_PATH="$payload_root/Payload/KnowType.prefPane"
      fi
      SOURCE_RELEASE_MANIFEST="$payload_root/Resources/release-manifest.json"
      if [[ ! -f "$SOURCE_RELEASE_MANIFEST" ]]; then
        echo "error: Developer Preview DMG payload is missing Resources/release-manifest.json: $payload_root" >&2
        exit 1
      fi
      SOURCE_RELEASE_MANIFEST_DIGEST="$(shasum -a 256 "$SOURCE_RELEASE_MANIFEST" | awk '{print $1}')"
      validate_release_manifest_metadata "$SOURCE_RELEASE_MANIFEST" "$SOURCE_BUNDLE_PATH" "$SOURCE_PREFPANE_PATH"
      SOURCE_GIT_COMMIT="$(release_manifest_field "$SOURCE_RELEASE_MANIFEST" "releaseCommit")"
      SOURCE_GIT_TAG="$(release_manifest_field "$SOURCE_RELEASE_MANIFEST" "tag")"
      ;;
  esac

  [[ -n "$SOURCE_BUNDLE_PATH" ]] || {
    echo "error: source KnowType.app was not found" >&2
    exit 1
  }
  knowtype_validate_inputmethod_bundle_for_install "$SOURCE_BUNDLE_PATH" "$VERIFY_ENABLED"

  if (( WITH_PREFPANE == 1 )) && [[ -z "$SOURCE_PREFPANE_PATH" ]]; then
    echo "error: --with-prefpane requested but source KnowType.prefPane was not found" >&2
    exit 1
  fi
}

if (( DRY_RUN == 1 )); then
  if [[ "$SOURCE_MODE" != "build" ]]; then
    prepare_source_artifacts
  fi
  echo "KnowType input-method install dry run"
  echo "Source mode: $(install_state_source)"
  [[ -n "$FROM_BUNDLE" ]] && echo "Source bundle: $FROM_BUNDLE"
  [[ -n "$FROM_RELEASE_ZIP" ]] && echo "Source release zip: $FROM_RELEASE_ZIP"
  [[ -n "$FROM_DMG_PAYLOAD" ]] && echo "Source DMG payload: $FROM_DMG_PAYLOAD"
  [[ -n "$SOURCE_BUNDLE_PATH" ]] && echo "Resolved source app: $SOURCE_BUNDLE_PATH"
  [[ -n "$SOURCE_GIT_TAG" ]] && echo "Release tag: $SOURCE_GIT_TAG"
  [[ -n "$SOURCE_GIT_COMMIT" ]] && echo "Release commit: $SOURCE_GIT_COMMIT"
  echo "Target bundle: $TARGET_PATH"
  echo "Install state: $(knowtype_install_state_path)"
  echo "Backup root: $(knowtype_backup_root_dir)"
  if (( BACKUP_ENABLED == 1 )); then
    knowtype_create_install_backup "$TARGET_PATH" "$PREFPANE_TARGET_PATH" 1 "$KEEP_BACKUPS"
    knowtype_prune_install_backups "$KEEP_BACKUPS" 1
  fi
  if (( WITH_PREFPANE == 1 )); then
    echo "Target compatibility PreferencePane: $PREFPANE_TARGET_PATH"
  fi
  echo
  echo "Local KnowType bundles that would be removed before install:"
  local_bundle_count=0
  while IFS= read -r bundle_path; do
    [[ -n "$bundle_path" ]] || continue
    local_bundle_count=$((local_bundle_count + 1))
    echo "  $bundle_path"
  done < <(knowtype_find_local_inputmethod_bundle_paths)
  if (( local_bundle_count == 0 )); then
    echo "  <none>"
  fi
  echo
  echo "LaunchServices records that would be unregistered:"
  ls_count=0
  while IFS= read -r bundle_path; do
    [[ -n "$bundle_path" ]] || continue
    ls_count=$((ls_count + 1))
    echo "  $(knowtype_expand_home_path "$(knowtype_strip_lsregister_suffix "$bundle_path")")"
  done < <(knowtype_launchservices_paths_for_identity)
  if (( ls_count == 0 )); then
    echo "  <none>"
  fi
  if [[ -d "$PREFPANE_TARGET_PATH" ]]; then
    echo
    if (( WITH_PREFPANE == 1 )); then
      echo "Compatibility PreferencePane that would be replaced:"
    else
      echo "Stale compatibility PreferencePane that would be removed:"
    fi
    echo "  $PREFPANE_TARGET_PATH"
  fi
  echo
  echo "System Settings PreferencePane caches that would be refreshed:"
  cache_count=0
  while IFS= read -r cache_path; do
    [[ -n "$cache_path" ]] || continue
    cache_count=$((cache_count + 1))
    echo "  $cache_path"
  done < <(knowtype_preferencepane_cache_identity_paths)
  if (( cache_count == 0 )); then
    echo "  <none with KnowType metadata>"
  else
    knowtype_clean_preferencepane_caches 1
  fi
  knowtype_quit_system_settings_if_running 1
  echo
  echo "Text Input Source preference rows would be repaired and menu agents would be restarted."
  exit 0
fi

if (( DRY_RUN == 0 )); then
  require_input_method_host_stopped
fi

prepare_source_artifacts

mkdir -p "$TARGET_DIR"
if (( WITH_PREFPANE == 1 )); then
  mkdir -p "$PREFPANE_TARGET_DIR"
fi

switch_away_before_replace
sleep 0.2
require_input_method_host_stopped

if (( BACKUP_ENABLED == 1 )); then
  knowtype_create_install_backup "$TARGET_PATH" "$PREFPANE_TARGET_PATH" 0 "$KEEP_BACKUPS"
  BACKUP_ID="$KNOWTYPE_CREATED_BACKUP_ID"
  BACKUP_DIR="$KNOWTYPE_CREATED_BACKUP_DIR"
fi

if [[ -e "$TARGET_PATH" || -L "$TARGET_PATH" ]]; then
  knowtype_remove_local_inputmethod_bundle_if_safe "$TARGET_PATH" 0
fi
knowtype_cleanup_local_duplicate_bundles_except "" 0
cp -R "$SOURCE_BUNDLE_PATH" "$TARGET_PATH"
if [[ "$SOURCE_MODE" == "build" ]]; then
  rm -rf "$SOURCE_BUNDLE_PATH"
fi

if (( WITH_PREFPANE == 1 )); then
  rm -rf "$PREFPANE_TARGET_PATH"
  cp -R "$SOURCE_PREFPANE_PATH" "$PREFPANE_TARGET_PATH"
  if [[ "$SOURCE_MODE" == "build" ]]; then
    rm -rf "$SOURCE_PREFPANE_PATH"
  fi
elif [[ -d "$PREFPANE_TARGET_PATH" ]]; then
  rm -rf "$PREFPANE_TARGET_PATH"
  REMOVED_STALE_PREFPANE=1
fi

knowtype_clean_preferencepane_caches 0
knowtype_quit_system_settings_if_running 0

if command -v xattr >/dev/null 2>&1; then
  if (( WITH_PREFPANE == 1 )); then
    xattr -dr com.apple.quarantine "$TARGET_PATH" "$PREFPANE_TARGET_PATH" 2>/dev/null || true
  else
    xattr -dr com.apple.quarantine "$TARGET_PATH" 2>/dev/null || true
  fi
fi

knowtype_unregister_launchservices_records_except "$TARGET_PATH" 0
knowtype_register_launchservices_path "$TARGET_PATH" 0

purge_legacy_best_effort
repair_preferences_best_effort
bootstrap_input_source_best_effort
repair_preferences_best_effort

sleep 0.75
killall cfprefsd 2>/dev/null || true
killall TextInputMenuAgent 2>/dev/null || true
killall TextInputSwitcher 2>/dev/null || true
sleep 0.5

knowtype_write_install_state \
  "$(install_state_source)" \
  "$TARGET_PATH" \
  "$([[ "$WITH_PREFPANE" == "1" ]] && printf '%s' "$PREFPANE_TARGET_PATH" || true)" \
  "$([[ "$KEEP_BACKUPS" != "0" ]] && printf '%s' "$BACKUP_ID" || true)" \
  "$SOURCE_GIT_COMMIT" \
  "$SOURCE_GIT_TAG" \
  "$SOURCE_RELEASE_MANIFEST_DIGEST"

duplicate_count="$(knowtype_find_local_inputmethod_bundle_paths | knowtype_count_nonempty_lines)"
if [[ "$duplicate_count" =~ ^[0-9]+$ && "$duplicate_count" -gt 1 ]]; then
  echo "warning: found $duplicate_count local KnowType bundles after install:" >&2
  knowtype_find_local_inputmethod_bundle_paths | sed 's/^/  /' >&2
  echo "Run ./scripts/repair-inputmethod-selection.sh before testing selection." >&2
fi

installed_version="$(knowtype_bundle_short_version "$TARGET_PATH")"
installed_build="$(knowtype_bundle_build_version "$TARGET_PATH")"
postflight_result="ok"
postflight_json=""
if ! postflight_json="$("$SCRIPTS_DIR/diagnose-inputmethod.sh" --json --path "$TARGET_PATH" 2>/dev/null)"; then
  postflight_result="warning"
elif command -v python3 >/dev/null 2>&1; then
  if ! python3 -c 'import json,sys; data=json.load(sys.stdin); sys.exit(1 if data.get("failures") else 0)' <<<"$postflight_json"; then
    postflight_result="warning"
  fi
fi

INSTALL_SUCCEEDED=1
if (( BACKUP_ENABLED == 1 )); then
  knowtype_prune_install_backups "$KEEP_BACKUPS" 0
  if [[ "$KEEP_BACKUPS" == "0" ]]; then
    BACKUP_ID=""
  fi
fi

echo
echo "KnowType install summary"
printf '  %-18s %s\n' "Source:" "$(install_state_source)"
printf '  %-18s %s\n' "Version:" "${installed_version:-<unknown>}"
printf '  %-18s %s\n' "Build:" "${installed_build:-<unknown>}"
printf '  %-18s %s\n' "Target:" "$TARGET_PATH"
printf '  %-18s %s\n' "Install state:" "$(knowtype_install_state_path)"
printf '  %-18s %s\n' "Backup:" "${BACKUP_ID:-<none>}"
printf '  %-18s %s\n' "Postflight:" "$postflight_result"

if (( WITH_PREFPANE == 1 )); then
  echo "Installed KnowType compatibility PreferencePane to: $PREFPANE_TARGET_PATH"
  echo "System Settings may show the compatibility KnowType pane after reopening."
else
  echo "KnowType settings are available from the input-method menu: KnowType Settings..."
  echo "Default install keeps System Settings free of stale KnowType PreferencePane entries."
  if (( REMOVED_STALE_PREFPANE == 1 )); then
    echo "Removed stale KnowType compatibility PreferencePane from: $PREFPANE_TARGET_PATH"
  fi
fi

echo "Registered and enabled input source via helper: $KNOWTYPE_ACTIVE_INPUT_MODE_ID"
echo "Postflight uses the JSON install snapshot only; run ./scripts/diagnose-inputmethod.sh --strict for full TIS diagnostics."
if [[ -n "$BACKUP_ID" ]]; then
  echo "Rollback command: ./scripts/rollback-inputmethod.sh --to $BACKUP_ID"
fi
echo "Activate the target text app, select KnowType or run ./scripts/select-inputmethod.sh --require-selected, then type a real probe before manual acceptance."
echo "If System Settings asks to allow 知键/KnowType as an input method, click Allow before testing selection."
echo "If diagnostics show HIToolbox selected preference is still another source, choose KnowType from the active app's input menu/System Settings."
