#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/inputsource-ids.sh"
source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"
source "$ROOT_DIR/scripts/lib/inputmethod-installation.sh"

DRY_RUN=0
LIST_BACKUPS=0
TARGET_BACKUP_ID=""
USE_LATEST=0
ALLOW_UNVERIFIED_BACKUP=0

usage() {
  cat <<'EOF'
Usage: scripts/rollback-inputmethod.sh [--list] [--latest | --to BACKUP_ID] [--dry-run] [--allow-unverified-backup]

Restores a previously backed up KnowType.app and optional KnowType.prefPane.
Rollback preserves user data. Before publishing a pre-v2 app, it converts the
current provider profile metadata to the legacy numeric schema without changing
profiles or Keychain secrets. It does not modify Rime userdb, ENV.md,
CORRECTION.md, LEXICAL_PROFILE.md, or lexicons.

Options:
  --list          List available backups.
  --latest        Restore the newest backup.
  --to BACKUP_ID  Restore a specific backup ID.
  --dry-run       Print actions without changing files or preferences.
  --allow-unverified-backup
                  DANGEROUS: allow schema-v1 legacy backups that lack complete
                  checksum/version/signing metadata. Schema-v2 failures remain fatal.
  -h, --help      Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
    --list)
      LIST_BACKUPS=1
      shift
      ;;
    --latest)
      USE_LATEST=1
      shift
      ;;
    --to)
      if (($# < 2)); then
        echo "error: --to requires a backup ID" >&2
        exit 2
      fi
      TARGET_BACKUP_ID="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --allow-unverified-backup)
      ALLOW_UNVERIFIED_BACKUP=1
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

backup_root="$(knowtype_backup_root_dir)"
target_path="$(knowtype_inputmethod_target_path)"
prefpane_path="$(knowtype_preferencepane_target_path)"
target_dir="$(knowtype_inputmethod_target_dir)"
prefpane_dir="$(knowtype_preferencepane_target_dir)"
restore_app_staging_dir=""
current_app_staging_dir=""
restore_prefpane_staging_dir=""
provider_storage_downgraded=0
provider_profile_tool=""

provider_profile_tool_path() {
  if [[ -z "$provider_profile_tool" ]]; then
    provider_profile_tool="$(knowtype_inputsource_tool "$ROOT_DIR")"
  fi
  printf '%s\n' "$provider_profile_tool"
}

cleanup_restore_staging() {
  [[ -n "$restore_app_staging_dir" && -d "$restore_app_staging_dir" ]] && rm -rf "$restore_app_staging_dir"
  [[ -n "$current_app_staging_dir" && -d "$current_app_staging_dir" ]] && rm -rf "$current_app_staging_dir"
  [[ -n "$restore_prefpane_staging_dir" && -d "$restore_prefpane_staging_dir" ]] && rm -rf "$restore_prefpane_staging_dir"
  return 0
}

trap cleanup_restore_staging EXIT

require_input_method_host_stopped() {
  if knowtype_input_method_host_is_running; then
    echo "error: KnowTypeInputMethodApp is running." >&2
    echo "Switch to another input source and quit the running KnowType host, then rerun rollback." >&2
    echo "Rollback will not kill the host because process shutdown can flush Rime user data." >&2
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

provider_storage_generation_for_bundle() {
  local bundle_path="$1"
  knowtype_plist_value \
    "KnowTypeProviderProfileStorageGeneration" \
    "$bundle_path/Contents/Info.plist"
}

knowtype_settings_host_pids() {
  local pid command
  while read -r pid command; do
    [[ -n "${pid:-}" && -n "${command:-}" ]] || continue
    case "$command" in
      KnowTypeSettingsApp|KnowTypeSettingsApp\ *|*/KnowTypeSettingsApp|*/KnowTypeSettingsApp\ *|KnowTypeSettings|KnowTypeSettings\ *|*/KnowTypeSettings|*/KnowTypeSettings\ *)
        printf '%s\n' "$pid"
        ;;
    esac
  done < <(ps -axo pid=,command= 2>/dev/null)
}

stop_provider_profile_writer_hosts() {
  local pids=""
  pids="$(knowtype_settings_host_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [[ -n "$pids" ]]; then
    echo "Requesting KnowType Settings shutdown before provider storage rollback: $pids"
    # shellcheck disable=SC2086
    kill -TERM $pids 2>/dev/null || true
  fi
  knowtype_quit_system_settings_if_running 0

  local attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if [[ -z "$(knowtype_settings_host_pids)" ]] && ! knowtype_system_settings_is_running; then
      return 0
    fi
    sleep 0.2
  done
  echo "error: close KnowType Settings and System Settings before restoring an older input method" >&2
  return 1
}

prepare_provider_storage_for_restored_app() {
  local restored_generation current_generation provider_tool output status
  restored_generation="$(provider_storage_generation_for_bundle "$backup_dir/KnowType.app" || true)"
  stop_provider_profile_writer_hosts
  if [[ "$restored_generation" =~ ^[0-9]+$ ]] && (( restored_generation >= 2 )); then
    return 0
  fi

  current_generation="$(provider_storage_generation_for_bundle "$target_path" || true)"
  if [[ "$current_generation" =~ ^[0-9]+$ ]] && (( current_generation >= 2 )); then
    provider_tool="$(provider_profile_tool_path)"
    if [[ ! -x "$provider_tool" ]]; then
      echo "error: provider profile helper is unavailable for storage downgrade" >&2
      return 1
    fi
    output=""
    if ! output="$("$provider_tool" downgrade-provider-profiles 2>&1)"; then
      [[ -n "$output" ]] && printf '%s\n' "$output" >&2
      echo "error: provider storage downgrade failed; refusing to publish an incompatible pre-v2 app" >&2
      return 1
    fi
    [[ -n "$output" ]] && printf '%s\n' "$output"
    status="$(printf '%s\n' "$output" | awk -F= '/^provider\.storage\.downgrade\.status=/{print $2; exit}')"
    case "$status" in
      downgraded)
        provider_storage_downgraded=1
        ;;
      already_legacy|unmanaged)
        ;;
      *)
        echo "error: provider storage downgrade returned an unknown status" >&2
        return 1
        ;;
    esac
    return 0
  fi

  if ! knowtype_provider_storage_is_pre_v2_compatible; then
    echo "error: current app cannot downgrade the provider tombstone for this pre-v2 backup" >&2
    echo "Reinstall the current KnowType build, then retry rollback." >&2
    return 1
  fi
}

migrate_provider_storage_for_restored_app() {
  local restored_generation
  restored_generation="$(provider_storage_generation_for_bundle "$target_path" || true)"
  if [[ ! "$restored_generation" =~ ^[0-9]+$ ]] || (( restored_generation < 2 )); then
    return 0
  fi
  if ! knowtype_migrate_provider_storage_for_bundle "$target_path" "$(provider_profile_tool_path)"; then
    echo "error: provider profile migration failed; refusing to finalize the generation-2 rollback" >&2
    return 1
  fi
}

restore_current_app_after_failed_provider_migration() {
  local previous_app="$current_app_staging_dir/KnowType.app"
  local previous_generation=""
  local provider_tool=""
  local output=""
  local status=""

  [[ -d "$previous_app" ]] || return 1
  previous_generation="$(provider_storage_generation_for_bundle "$previous_app" || true)"
  if [[ ! "$previous_generation" =~ ^[0-9]+$ ]] || (( previous_generation < 2 )); then
    provider_tool="$(provider_profile_tool_path)"
    if [[ ! -x "$provider_tool" ]] ||
       ! output="$("$provider_tool" downgrade-provider-profiles 2>&1)"; then
      [[ -n "$output" ]] && printf '%s\n' "$output" >&2
      echo "error: provider metadata could not be returned to a pre-v2-compatible state; keeping the generation-2 app" >&2
      return 1
    fi
    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
    status="$(printf '%s\n' "$output" | awk -F= '/^provider\.storage\.downgrade\.status=/{print $2; exit}')"
    case "$status" in
      downgraded|already_legacy|unmanaged)
        ;;
      *)
        echo "error: provider storage downgrade returned an unknown status; keeping the generation-2 app" >&2
        return 1
        ;;
    esac
  fi

  knowtype_remove_local_inputmethod_bundle_if_safe "$target_path" 0
  mv "$previous_app" "$target_path"
  rm -rf "$current_app_staging_dir"
  current_app_staging_dir=""
  return 0
}

reapply_provider_migration_after_abandoned_rollback() {
  local provider_tool=""
  if (( provider_storage_downgraded != 1 )); then
    return 0
  fi
  provider_tool="$(provider_profile_tool_path)"
  if [[ -x "$provider_tool" ]] && "$provider_tool" migrate-provider-profiles >/dev/null 2>&1; then
    provider_storage_downgraded=0
    return 0
  fi
  echo "warning: could not reapply provider migration after app rollback was abandoned; rerun the installer" >&2
  return 1
}

list_backups() {
  if [[ ! -d "$backup_root" ]]; then
    echo "No KnowType install backups were found."
    return 0
  fi

  local count=0
  while IFS= read -r backup_dir; do
    [[ -n "$backup_dir" ]] || continue
    count=$((count + 1))
    local manifest="$backup_dir/manifest.json"
    local backup_id version build created
    backup_id="$(basename "$backup_dir")"
    version="$(knowtype_backup_manifest_field "$manifest" "sourceVersion")"
    build="$(knowtype_backup_manifest_field "$manifest" "sourceBuild")"
    created="$(knowtype_backup_manifest_field "$manifest" "createdAt")"
    printf '%s\tversion=%s\tbuild=%s\tcreated=%s\n' "$backup_id" "${version:-<unknown>}" "${build:-<unknown>}" "${created:-<unknown>}"
  done < <(knowtype_list_managed_backup_dirs)

  if (( count == 0 )); then
    echo "No KnowType install backups were found."
  fi
  return 0
}

if (( LIST_BACKUPS == 1 )); then
  list_backups
  if (( USE_LATEST == 0 )) && [[ -z "$TARGET_BACKUP_ID" ]]; then
    exit 0
  fi
fi

if (( USE_LATEST == 1 )) && [[ -n "$TARGET_BACKUP_ID" ]]; then
  echo "error: --latest and --to are mutually exclusive" >&2
  exit 2
fi

backup_dir=""
if (( USE_LATEST == 1 )); then
  backup_dir="$(knowtype_latest_backup_dir)"
elif [[ -n "$TARGET_BACKUP_ID" ]]; then
  backup_dir="$(knowtype_backup_dir_for_id "$TARGET_BACKUP_ID" || true)"
else
  echo "error: choose --latest, --to BACKUP_ID, or --list" >&2
  usage >&2
  exit 2
fi

if [[ -z "$backup_dir" || ! -d "$backup_dir" ]]; then
  echo "error: requested KnowType backup was not found" >&2
  exit 1
fi
if [[ ! -d "$backup_dir/KnowType.app" ]]; then
  echo "error: backup does not contain KnowType.app: $backup_dir" >&2
  exit 1
fi
if ! knowtype_validate_install_backup_for_restore "$backup_dir" "$ALLOW_UNVERIFIED_BACKUP"; then
  exit 1
fi
backup_validation_status="$KNOWTYPE_BACKUP_VALIDATION_STATUS"
restored_active_mode_id="$(knowtype_bundle_visible_input_mode_id "$backup_dir/KnowType.app" || true)"
if [[ -z "$restored_active_mode_id" || "$restored_active_mode_id" == "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" ]]; then
  echo "error: backup KnowType.app does not declare a menu-visible input mode." >&2
  echo "Rollback refuses to repair preferences for parent-only backups because they cannot satisfy the current menu-switchable IMK model." >&2
  exit 1
fi

restored_legacy_mode_ids=()
append_restored_legacy_mode_id() {
  local candidate="$1"
  local existing
  [[ -n "$candidate" && "$candidate" != "$restored_active_mode_id" ]] || return 0
  if ((${#restored_legacy_mode_ids[@]} > 0)); then
    for existing in "${restored_legacy_mode_ids[@]}"; do
      [[ "$existing" == "$candidate" ]] && return 0
    done
  fi
  restored_legacy_mode_ids+=("$candidate")
}
append_restored_legacy_mode_id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID"
for legacy_id in "${KNOWTYPE_LEGACY_INPUT_MODE_IDS[@]}"; do
  append_restored_legacy_mode_id "$legacy_id"
done
restored_legacy_args=()
if ((${#restored_legacy_mode_ids[@]} > 0)); then
  for legacy_id in "${restored_legacy_mode_ids[@]}"; do
    restored_legacy_args+=(--legacy-mode-id "$legacy_id")
  done
fi

backup_id="$(basename "$backup_dir")"
knowtype_require_safe_local_preferencepane_if_present "$prefpane_path"

if (( DRY_RUN == 1 )); then
  echo "KnowType rollback dry run"
  echo "Backup: $backup_id"
  echo "Backup path: $backup_dir"
  echo "Backup integrity: $backup_validation_status"
  if [[ "$backup_validation_status" == "legacy-unverified-override" ]]; then
    echo "UNVERIFIED LEGACY OVERRIDE: ENABLED"
  elif (( ALLOW_UNVERIFIED_BACKUP == 1 )); then
    echo "Legacy override: not applicable; schema-v2 integrity validation remained strict"
  fi
  echo "Restored active input mode: $restored_active_mode_id"
  echo "Target app: $target_path"
  restored_provider_generation="$(provider_storage_generation_for_bundle "$backup_dir/KnowType.app" || true)"
  if [[ ! "$restored_provider_generation" =~ ^[0-9]+$ ]] || (( restored_provider_generation < 2 )); then
    echo "[dry-run] Would quiesce Settings writers and convert current provider metadata to the legacy numeric schema before publishing this pre-v2 app."
  else
    echo "[dry-run] Restored app supports provider storage generation $restored_provider_generation; after publishing it, rollback would migrate any legacy metadata before registration."
  fi
  if [[ -d "$backup_dir/KnowType.prefPane" ]]; then
    echo "Target PreferencePane: $prefpane_path"
  else
    echo "Target PreferencePane: <remove if installed>"
  fi
  echo "[dry-run] Would require KnowTypeInputMethodApp to be stopped, switch away from KnowType, restore app, refresh LaunchServices through helpers, repair preferences, and write install-state.json."
  exit 0
fi

require_input_method_host_stopped

inputsource_tool=""
if inputsource_tool="$(knowtype_inputsource_tool "$ROOT_DIR" 2>/dev/null)"; then
  switch_args=(
    switch-away
    --prefix "$KNOWTYPE_PARENT_INPUT_SOURCE_ID"
    --fallback-id "$KNOWTYPE_FALLBACK_INPUT_SOURCE_ID"
    --parent-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID"
    --mode-id "$restored_active_mode_id"
  )
  if ((${#restored_legacy_mode_ids[@]} > 0)); then
    for legacy_id in "${restored_legacy_mode_ids[@]}"; do
      switch_args+=(--legacy-mode-id "$legacy_id")
    done
  fi
  "$inputsource_tool" "${switch_args[@]}" >/dev/null 2>&1 || true
else
  echo "warning: input-source helper is unavailable; rollback will restore bundles and skip preference repair" >&2
  inputsource_tool=""
fi
require_input_method_host_stopped

mkdir -p "$target_dir"
restore_app_staging_dir="$(mktemp -d "$target_dir/.KnowType.rollback.app.XXXXXX")"
cp -R "$backup_dir/KnowType.app" "$restore_app_staging_dir/KnowType.app"

if [[ -d "$backup_dir/KnowType.prefPane" ]]; then
  mkdir -p "$prefpane_dir"
  restore_prefpane_staging_dir="$(mktemp -d "$prefpane_dir/.KnowType.rollback.prefpane.XXXXXX")"
  cp -R "$backup_dir/KnowType.prefPane" "$restore_prefpane_staging_dir/KnowType.prefPane"
fi

knowtype_validate_inputmethod_bundle_for_install "$restore_app_staging_dir/KnowType.app" 1
if [[ "$backup_validation_status" == verified-schema-* ]]; then
  knowtype_require_backup_metadata_match \
    "staged app checksum" \
    "$(knowtype_backup_manifest_field "$backup_dir/manifest.json" "appChecksum")" \
    "$(knowtype_path_checksum "$restore_app_staging_dir/KnowType.app" || true)"
fi
if [[ -n "$restore_prefpane_staging_dir" ]]; then
  knowtype_validate_preferencepane_bundle_for_install "$restore_prefpane_staging_dir/KnowType.prefPane" 1
  if [[ "$backup_validation_status" == verified-schema-* ]]; then
    knowtype_require_backup_metadata_match \
      "staged PreferencePane checksum" \
      "$(knowtype_backup_manifest_field "$backup_dir/manifest.json" "prefPaneChecksum")" \
      "$(knowtype_path_checksum "$restore_prefpane_staging_dir/KnowType.prefPane" || true)"
  fi
fi

prepare_provider_storage_for_restored_app

if [[ -e "$target_path" || -L "$target_path" ]]; then
  if ! knowtype_is_safe_local_inputmethod_bundle_path "$target_path"; then
    reapply_provider_migration_after_abandoned_rollback \
      "$target_path/Contents/MacOS/KnowTypeInputMethodApp" || true
    echo "error: refusing to replace a foreign or unsafe current input-method bundle" >&2
    exit 1
  fi
  current_app_staging_dir="$(mktemp -d "$target_dir/.KnowType.rollback.current.XXXXXX")"
  if ! mv "$target_path" "$current_app_staging_dir/KnowType.app"; then
    reapply_provider_migration_after_abandoned_rollback \
      "$target_path/Contents/MacOS/KnowTypeInputMethodApp" || true
    echo "error: could not stage the current KnowType app for rollback" >&2
    exit 1
  fi
fi
if ! mv "$restore_app_staging_dir/KnowType.app" "$target_path"; then
  if [[ -d "$current_app_staging_dir/KnowType.app" && ! -e "$target_path" ]]; then
    mv "$current_app_staging_dir/KnowType.app" "$target_path" 2>/dev/null || true
  fi
  reapply_provider_migration_after_abandoned_rollback \
    "$target_path/Contents/MacOS/KnowTypeInputMethodApp" || true
  echo "error: could not publish the staged KnowType backup" >&2
  exit 1
fi
rm -rf "$restore_app_staging_dir"
restore_app_staging_dir=""
if ! migrate_provider_storage_for_restored_app; then
  if restore_current_app_after_failed_provider_migration; then
    echo "Restored the previous app after provider profile migration failed." >&2
  else
    echo "The generation-2 backup remains installed so canonical provider metadata stays fail-closed." >&2
  fi
  exit 1
fi
rm -rf "$current_app_staging_dir"
current_app_staging_dir=""

if [[ -d "$backup_dir/KnowType.prefPane" ]]; then
  knowtype_remove_local_preferencepane_bundle_if_safe "$prefpane_path" 0
  mv "$restore_prefpane_staging_dir/KnowType.prefPane" "$prefpane_path"
  rm -rf "$restore_prefpane_staging_dir"
  restore_prefpane_staging_dir=""
else
  knowtype_remove_local_preferencepane_bundle_if_safe "$prefpane_path" 0
fi

knowtype_clean_preferencepane_caches 0
knowtype_quit_system_settings_if_running 0

if command -v xattr >/dev/null 2>&1; then
  if [[ -d "$prefpane_path" ]]; then
    xattr -dr com.apple.quarantine "$target_path" "$prefpane_path" 2>/dev/null || true
  else
    xattr -dr com.apple.quarantine "$target_path" 2>/dev/null || true
  fi
fi

knowtype_unregister_launchservices_records_except "$target_path" 0
knowtype_register_launchservices_path "$target_path" 0

if [[ -n "$inputsource_tool" ]]; then
  purge_args=(
    purge-legacy
    --path "$target_path"
    --parent-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID"
    --mode-id "$restored_active_mode_id"
  )
  repair_args=(
    repair-preferences
    --bundle-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID"
    --mode-id "$restored_active_mode_id"
  )
  bootstrap_args=(
    bootstrap
    --path "$target_path"
    --parent-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID"
    --mode-id "$restored_active_mode_id"
  )
  if ((${#restored_legacy_args[@]} > 0)); then
    purge_args+=("${restored_legacy_args[@]}")
    repair_args+=("${restored_legacy_args[@]}")
    bootstrap_args+=("${restored_legacy_args[@]}")
  fi
  repair_args+=(
    --include-history
    --add-active
  )
  "$inputsource_tool" "${purge_args[@]}" >/dev/null 2>&1 || true
  "$inputsource_tool" "${repair_args[@]}" >/dev/null 2>&1 || true
  "$inputsource_tool" "${bootstrap_args[@]}" >/dev/null 2>&1 || true
fi

killall cfprefsd 2>/dev/null || true
killall TextInputMenuAgent 2>/dev/null || true
killall TextInputSwitcher 2>/dev/null || true

knowtype_write_install_state \
  "bundle" \
  "$target_path" \
  "$([[ -d "$prefpane_path" ]] && printf '%s' "$prefpane_path" || true)" \
  "$backup_id" \
  "" \
  "" \
  ""

version="$(knowtype_bundle_short_version "$target_path")"
build="$(knowtype_bundle_build_version "$target_path")"
echo "Restored KnowType backup: $backup_id"
echo "Version: ${version:-<unknown>}"
echo "Build: ${build:-<unknown>}"
echo "Active input mode: $restored_active_mode_id"
echo "Run ./scripts/diagnose-inputmethod.sh --strict to verify the restored install."
