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
FORCE_STOP_HOST=0
KEEP_BACKUPS="$KNOWTYPE_DEFAULT_BACKUP_RETENTION"
QUIESCE_DISABLE_STATUS="not-run"
QUIESCE_DISABLED_COUNT="0"
QUIESCE_HOST_STOP_STATUS="not-run"
QUIESCE_PROVIDER_WRITER_STATUS="not-run"
QUIESCE_MENU_AGENTS_RESTARTED="no"
QUIESCE_STARTED=0
STALE_LAUNCHSERVICES_CLEANUP_COUNT="0"
PROVIDER_MIGRATION_STATUS="not-run"
PROVIDER_MIGRATION_REVISION=""
PROVIDER_MIGRATION_ATTEMPTED=0
SOURCE_PROVIDER_STORAGE_GENERATION=""
PROVIDER_STORAGE_PREPARED_FOR_PRE_V2_SOURCE=0

usage() {
  cat <<'EOF'
Usage: scripts/install-inputmethod.sh [options]

Builds and installs KnowType.app into ~/Library/Input Methods, then uses the
dedicated input-source helper to register and enable the input source without
launching the input method host. KnowType-specific settings are opened from the
input-method menu's KnowType 设置 item (KnowType Settings in explicit English UI).

Options:
  --configuration debug|release  SwiftPM build configuration. Defaults to CONFIGURATION or release.
  --with-prefpane                Also build/install the compatibility KnowType.prefPane.
  --from-bundle PATH             Install an existing KnowType.app instead of building from source.
  --from-release-zip PATH        Install KnowType.app from a release zip and validate release metadata when present.
  --from-dmg-payload PATH        Install from a mounted Developer Preview DMG payload root.
  --no-backup                    Replace without creating an app/prefPane backup.
  --keep-backups N               Keep the newest N app backups. Defaults to 3.
  --no-verify                    Skip codesign verification during preflight.
  --force-stop-host              After switch-away/disable, send KILL if the input-method host ignores TERM.
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
    --force-stop-host)
      FORCE_STOP_HOST=1
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

LOCAL_BUILD_VERSION="${KNOWTYPE_BUNDLE_BUILD_VERSION:-}"
LOCAL_SHORT_VERSION="${KNOWTYPE_BUNDLE_SHORT_VERSION:-}"
if [[ "$SOURCE_MODE" == "build" ]]; then
  LOCAL_BUILD_VERSION="${LOCAL_BUILD_VERSION:-$(date +%Y%m%d%H%M%S)}"
  LOCAL_SHORT_VERSION="${LOCAL_SHORT_VERSION:-$(knowtype_plist_value "CFBundleShortVersionString" "$ROOT_DIR/Resources/InputMethod/Info.plist")}"
  if [[ -z "$LOCAL_SHORT_VERSION" ]]; then
    echo "error: local build short version is missing" >&2
    exit 1
  fi
fi
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

install_source_path_summary() {
  case "$SOURCE_MODE" in
    build) printf '%s' "$ROOT_DIR/dist/KnowType.app" ;;
    bundle) printf '%s' "$FROM_BUNDLE" ;;
    release-zip) printf '%s' "$FROM_RELEASE_ZIP" ;;
    dmg-dev-preview) printf '%s' "$FROM_DMG_PAYLOAD" ;;
    *) printf '%s' "$SOURCE_MODE" ;;
  esac
}

cleanup_source_temp() {
  if [[ -n "$SOURCE_TEMP_DIR" && -d "$SOURCE_TEMP_DIR" ]]; then
    rm -rf "$SOURCE_TEMP_DIR"
  fi
}

provider_storage_generation_for_bundle() {
  local bundle_path="$1"
  knowtype_plist_value \
    "KnowTypeProviderProfileStorageGeneration" \
    "$bundle_path/Contents/Info.plist"
}

prepare_provider_storage_for_source_bundle() {
  if [[ "$SOURCE_PROVIDER_STORAGE_GENERATION" =~ ^[0-9]+$ ]] &&
     (( SOURCE_PROVIDER_STORAGE_GENERATION >= 2 )); then
    return 0
  fi

  stop_provider_profile_writer_hosts
  local current_generation=""
  current_generation="$(provider_storage_generation_for_bundle "$TARGET_PATH" || true)"
  if [[ "$current_generation" =~ ^[0-9]+$ ]] && (( current_generation >= 2 )); then
    local provider_tool=""
    local output=""
    local status=""
    provider_tool="$(inputsource_tool_path)"
    if [[ ! -x "$provider_tool" ]]; then
      echo "error: provider profile helper is unavailable for provider storage downgrade" >&2
      return 1
    fi
    if ! output="$("$provider_tool" downgrade-provider-profiles 2>&1)"; then
      [[ -n "$output" ]] && printf '%s\n' "$output" >&2
      echo "error: provider storage downgrade failed; refusing to install a pre-v2 input method" >&2
      return 1
    fi
    [[ -n "$output" ]] && printf '%s\n' "$output"
    status="$(printf '%s\n' "$output" | awk -F= '/^provider\.storage\.downgrade\.status=/{print $2; exit}')"
    case "$status" in
      downgraded|already_legacy|unmanaged)
        PROVIDER_STORAGE_PREPARED_FOR_PRE_V2_SOURCE=1
        PROVIDER_MIGRATION_STATUS="skipped-pre-v2-$status"
        return 0
        ;;
      *)
        echo "error: provider storage downgrade returned an unknown status" >&2
        return 1
        ;;
    esac
  fi

  if ! knowtype_provider_storage_is_pre_v2_compatible; then
    echo "error: provider storage is not compatible with the pre-v2 source bundle and no generation-2 installed app can downgrade it" >&2
    return 1
  fi
  PROVIDER_STORAGE_PREPARED_FOR_PRE_V2_SOURCE=1
  PROVIDER_MIGRATION_STATUS="skipped-pre-v2-compatible"
}

rollback_provider_storage_after_failed_install() {
  local provider_tool=""
  if (( PROVIDER_MIGRATION_ATTEMPTED != 1 )); then
    return 0
  fi
  provider_tool="$(inputsource_tool_path)"
  local restored_generation=""
  restored_generation="$(provider_storage_generation_for_bundle "$BACKUP_DIR/KnowType.app" || true)"
  if [[ "$restored_generation" =~ ^[0-9]+$ ]] && (( restored_generation >= 2 )); then
    return 0
  fi
  local output=""
  if [[ "$PROVIDER_MIGRATION_STATUS" == "migrated" ]]; then
    if [[ ! -x "$provider_tool" ]]; then
      echo "error: cannot roll back provider migration because the provider helper is unavailable" >&2
      return 1
    fi
    if [[ ! "$PROVIDER_MIGRATION_REVISION" =~ ^[0-9]+$ ]]; then
      echo "error: provider migration rollback is missing its expected canonical revision" >&2
      return 1
    fi
    if ! output="$("$provider_tool" rollback-provider-profile-migration --expected-revision "$PROVIDER_MIGRATION_REVISION" 2>&1)"; then
      [[ -n "$output" ]] && printf '%s\n' "$output" >&2
      echo "error: provider migration rollback failed; keeping the new app instead of restoring an incompatible old binary" >&2
      return 1
    fi
    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
    return 0
  fi

  if [[ ! -x "$provider_tool" ]]; then
    echo "error: cannot verify provider storage compatibility because the provider helper is unavailable" >&2
    return 1
  fi
  if ! output="$("$provider_tool" downgrade-provider-profiles 2>&1)"; then
    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
    echo "error: provider storage compatibility check failed; keeping the new app instead of restoring an incompatible old binary" >&2
    return 1
  fi
  [[ -n "$output" ]] && printf '%s\n' "$output" >&2
  local status=""
  status="$(printf '%s\n' "$output" | awk -F= '/^provider\.storage\.downgrade\.status=/{print $2; exit}')"
  case "$status" in
    downgraded|already_legacy|unmanaged)
      return 0
      ;;
    *)
      echo "error: provider storage compatibility check returned an unknown status; keeping the new app" >&2
      return 1
      ;;
  esac
}

reapply_provider_migration_best_effort() {
  local bundle_path="$1"
  local provider_tool=""
  local generation=""
  generation="$(provider_storage_generation_for_bundle "$bundle_path" || true)"
  provider_tool="$(inputsource_tool_path)"
  if [[ -x "$provider_tool" && "$generation" =~ ^[0-9]+$ ]] && (( generation >= 2 )); then
    if ! "$provider_tool" migrate-provider-profiles >/dev/null 2>&1; then
      echo "warning: could not reapply provider migration after artifact rollback was abandoned; rerun the installer" >&2
    fi
  fi
}

restore_existing_input_source_after_failed_quiesce() {
  if (( QUIESCE_STARTED != 1 || INSTALL_SUCCEEDED == 1 || DRY_RUN == 1 )); then
    return 0
  fi
  if [[ ! -d "$TARGET_PATH" ]]; then
    return 0
  fi

  echo "Install failed after quiescing; restoring existing KnowType input-source enablement: $TARGET_PATH" >&2
  local launchservices_cleanup_output
  launchservices_cleanup_output="$(knowtype_unregister_launchservices_records_except "$TARGET_PATH" 0)" || true
  if [[ -n "$launchservices_cleanup_output" ]]; then
    printf '%s\n' "$launchservices_cleanup_output"
  fi
  knowtype_register_launchservices_path "$TARGET_PATH" 0
  bootstrap_input_source_best_effort || true
  repair_preferences_best_effort || true
  killall cfprefsd 2>/dev/null || true
  killall TextInputMenuAgent 2>/dev/null || true
  killall TextInputSwitcher 2>/dev/null || true
  sleep 0.5
  repair_preferences_best_effort || true
  killall TextInputMenuAgent 2>/dev/null || true
  killall TextInputSwitcher 2>/dev/null || true
}

rollback_failed_install() {
  if (( INSTALL_SUCCEEDED == 1 || DRY_RUN == 1 )); then
    return 0
  fi
  if [[ -n "$BACKUP_DIR" && ( -d "$BACKUP_DIR/KnowType.app" || -d "$BACKUP_DIR/KnowType.prefPane" ) ]]; then
    echo "Install failed; restoring previous KnowType backup: $BACKUP_ID" >&2
    if ! knowtype_validate_install_backup_for_restore "$BACKUP_DIR" 0; then
      echo "error: failed-install rollback refused an invalid backup; current artifacts were left in place" >&2
      return 0
    fi
    if ! knowtype_require_safe_local_preferencepane_if_present "$PREFPANE_TARGET_PATH"; then
      echo "error: failed-install rollback left current artifacts in place to protect the foreign PreferencePane" >&2
      return 0
    fi
    local app_stage=""
    local current_stage=""
    local restored_app=0
    if [[ -d "$BACKUP_DIR/KnowType.app" ]]; then
      app_stage="$(mktemp -d "$TARGET_DIR/.KnowType.failed-install.app.XXXXXX")" || return 0
      if ! cp -R "$BACKUP_DIR/KnowType.app" "$app_stage/KnowType.app"; then
        rm -rf "$app_stage"
        return 0
      fi
      if [[ -e "$TARGET_PATH" || -L "$TARGET_PATH" ]] &&
         ! knowtype_is_safe_local_inputmethod_bundle_path "$TARGET_PATH"; then
        rm -rf "$app_stage"
        return 0
      fi
      local new_executable="$TARGET_PATH/Contents/MacOS/KnowTypeInputMethodApp"
      if ! rollback_provider_storage_after_failed_install "$new_executable"; then
        rm -rf "$app_stage"
        return 0
      fi
      if [[ -e "$TARGET_PATH" || -L "$TARGET_PATH" ]]; then
        current_stage="$(mktemp -d "$TARGET_DIR/.KnowType.failed-install.current.XXXXXX")" || {
          reapply_provider_migration_best_effort "$TARGET_PATH"
          rm -rf "$app_stage"
          return 0
        }
        if ! mv "$TARGET_PATH" "$current_stage/KnowType.app"; then
          reapply_provider_migration_best_effort "$TARGET_PATH"
          rm -rf "$app_stage" "$current_stage"
          return 0
        fi
      fi
      if ! mv "$app_stage/KnowType.app" "$TARGET_PATH"; then
        if [[ -n "$current_stage" && -d "$current_stage/KnowType.app" && ! -e "$TARGET_PATH" ]]; then
          mv "$current_stage/KnowType.app" "$TARGET_PATH" 2>/dev/null || true
        fi
        reapply_provider_migration_best_effort "$TARGET_PATH"
        rm -rf "$app_stage" "$current_stage"
        return 0
      fi
      rm -rf "$app_stage" "$current_stage"
      restored_app=1
      if (( PROVIDER_STORAGE_PREPARED_FOR_PRE_V2_SOURCE == 1 )); then
        reapply_provider_migration_best_effort "$TARGET_PATH"
      fi
    fi
    if [[ -d "$BACKUP_DIR/KnowType.prefPane" ]]; then
      mkdir -p "$PREFPANE_TARGET_DIR"
      if ! knowtype_replace_local_preferencepane_bundle_atomically \
        "$BACKUP_DIR/KnowType.prefPane" \
        "$PREFPANE_TARGET_PATH" \
        1; then
        echo "error: failed-install rollback could not restore the validated PreferencePane backup" >&2
        return 0
      fi
    else
      knowtype_remove_local_preferencepane_bundle_if_safe "$PREFPANE_TARGET_PATH" 0 || return 0
    fi
    if (( restored_app == 1 )); then
      knowtype_register_launchservices_path "$TARGET_PATH" 0
      restore_existing_input_source_after_failed_quiesce
    fi
  else
    if (( PROVIDER_STORAGE_PREPARED_FOR_PRE_V2_SOURCE == 1 )); then
      reapply_provider_migration_best_effort "$TARGET_PATH"
    fi
    restore_existing_input_source_after_failed_quiesce
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
    echo "The installer already switched away from KnowType, disabled its old input-source rows, and requested TERM." >&2
    echo "Quit the remaining host process manually, or rerun with --force-stop-host for local development." >&2
    echo "The default installer will not KILL the host because process shutdown can flush Rime user data." >&2
    exit 1
  fi
}

knowtype_input_method_host_pids() {
  local pid command
  while read -r pid command; do
    [[ -n "${pid:-}" && -n "${command:-}" ]] || continue
    case "$command" in
      KnowTypeInputMethodApp|KnowTypeInputMethodApp\ *|*/KnowTypeInputMethodApp|*/KnowTypeInputMethodApp\ *)
        printf '%s\n' "$pid"
        ;;
    esac
  done < <(ps -axo pid=,command= 2>/dev/null)
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

knowtype_settings_host_is_running() {
  [[ -n "$(knowtype_settings_host_pids)" ]]
}

stop_provider_profile_writer_hosts() {
  local pids=""
  pids="$(knowtype_settings_host_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [[ -n "$pids" ]]; then
    echo "Requesting KnowType Settings shutdown before provider profile migration: $pids"
    # shellcheck disable=SC2086
    kill -TERM $pids 2>/dev/null || true
  fi
  knowtype_quit_system_settings_if_running 0

  local attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if ! knowtype_settings_host_is_running && ! knowtype_system_settings_is_running; then
      if [[ -n "$pids" ]]; then
        QUIESCE_PROVIDER_WRITER_STATUS="stopped"
      elif [[ "$QUIESCE_PROVIDER_WRITER_STATUS" == "not-run" ]]; then
        QUIESCE_PROVIDER_WRITER_STATUS="not-running"
      fi
      return 0
    fi
    sleep 0.2
  done

  QUIESCE_PROVIDER_WRITER_STATUS="still-running"
  echo "error: close KnowType Settings and System Settings before installing so provider profiles can migrate safely" >&2
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

disable_input_sources_before_replace() {
  local tool output count
  if ! tool="$(inputsource_tool_path)"; then
    QUIESCE_DISABLE_STATUS="helper-unavailable"
    echo "warning: input-source helper is unavailable; continuing without pre-install disable" >&2
    return 0
  fi

  if output="$("$tool" disable --bundle-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" 2>&1)"; then
    count="$(printf '%s\n' "$output" | awk -F= '/^disabled.count=/{print $2; exit}')"
    QUIESCE_DISABLED_COUNT="${count:-unknown}"
    QUIESCE_DISABLE_STATUS="ok"
    echo "Disabled existing KnowType input-source rows before install: ${QUIESCE_DISABLED_COUNT}"
  else
    QUIESCE_DISABLE_STATUS="warning"
    echo "warning: input-source disable failed before install; continuing so diagnostics can report state" >&2
    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
  fi
}

restart_text_input_agents_for_quiesce() {
  killall cfprefsd 2>/dev/null || true
  killall TextInputMenuAgent 2>/dev/null || true
  killall TextInputSwitcher 2>/dev/null || true
  QUIESCE_MENU_AGENTS_RESTARTED="yes"
  sleep 0.5
}

stop_input_method_host_after_quiesce() {
  if ! knowtype_input_method_host_is_running; then
    if [[ "$QUIESCE_HOST_STOP_STATUS" == "not-run" ]]; then
      QUIESCE_HOST_STOP_STATUS="not-running"
    fi
    return 0
  fi

  local pids=""
  pids="$(knowtype_input_method_host_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [[ -z "$pids" ]]; then
    QUIESCE_HOST_STOP_STATUS="unknown-running"
    return 0
  fi

  echo "Requesting KnowTypeInputMethodApp shutdown after switch-away/disable: $pids"
  # shellcheck disable=SC2086
  kill -TERM $pids 2>/dev/null || true
  QUIESCE_HOST_STOP_STATUS="term-sent"

  local attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.2
    if ! knowtype_input_method_host_is_running; then
      QUIESCE_HOST_STOP_STATUS="stopped"
      return 0
    fi
  done

  if (( FORCE_STOP_HOST == 1 )); then
    pids="$(knowtype_input_method_host_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    if [[ -n "$pids" ]]; then
      echo "Force-stopping KnowTypeInputMethodApp after TERM did not exit: $pids"
      # shellcheck disable=SC2086
      kill -KILL $pids 2>/dev/null || true
    fi
    QUIESCE_HOST_STOP_STATUS="kill-sent"
    for attempt in 1 2 3 4 5; do
      sleep 0.2
      if ! knowtype_input_method_host_is_running; then
        QUIESCE_HOST_STOP_STATUS="force-stopped"
        return 0
      fi
    done
  fi
}

quiesce_before_replace() {
  QUIESCE_STARTED=1
  switch_away_before_replace
  disable_input_sources_before_replace
  restart_text_input_agents_for_quiesce
  stop_input_method_host_after_quiesce
  require_input_method_host_stopped
  stop_provider_profile_writer_hosts
}

migrate_provider_profiles() {
  local provider_tool=""
  local output=""
  local installed_generation=""
  installed_generation="$(provider_storage_generation_for_bundle "$TARGET_PATH" || true)"
  if [[ ! "$installed_generation" =~ ^[0-9]+$ ]] || (( installed_generation < 2 )); then
    if [[ "$PROVIDER_MIGRATION_STATUS" == "not-run" ]]; then
      PROVIDER_MIGRATION_STATUS="skipped-pre-v2-compatible"
    fi
    return 0
  fi
  provider_tool="$(inputsource_tool_path)"
  if [[ ! -x "$provider_tool" ]]; then
    echo "error: provider profile helper is unavailable for migration" >&2
    return 1
  fi
  stop_provider_profile_writer_hosts
  PROVIDER_MIGRATION_ATTEMPTED=1
  if ! output="$("$provider_tool" migrate-provider-profiles 2>&1)"; then
    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
    echo "error: provider profile migration failed; refusing to register the new input method" >&2
    return 1
  fi
  [[ -n "$output" ]] && printf '%s\n' "$output"
  PROVIDER_MIGRATION_STATUS="$(printf '%s\n' "$output" | awk -F= '/^provider\.migration\.status=/{print $2; exit}')"
  PROVIDER_MIGRATION_STATUS="${PROVIDER_MIGRATION_STATUS:-unknown}"
  PROVIDER_MIGRATION_REVISION="$(printf '%s\n' "$output" | awk -F= '/^provider\.migration\.revision=/{print $2; exit}')"
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
  /usr/bin/plutil -extract "$field_path" raw -o - "$manifest_path" 2>/dev/null || true
}

release_manifest_bundle_count() {
  local manifest_path="$1"
  local count
  count="$(/usr/bin/plutil -extract bundles raw -o - "$manifest_path" 2>/dev/null || true)"
  if [[ "$count" =~ ^[0-9]+$ ]]; then
    printf '%s' "$count"
  else
    printf '0'
  fi
}

release_manifest_bundle_field() {
  local manifest_path="$1"
  local index="$2"
  local key="$3"
  /usr/bin/plutil -extract "bundles.$index.$key" raw -o - "$manifest_path" 2>/dev/null || true
}

release_manifest_bundle_index_for_path() {
  local manifest_path="$1"
  local expected_path="$2"
  local count
  local match_count=0
  local match_index=""
  local index
  local path
  count="$(release_manifest_bundle_count "$manifest_path")"
  for ((index = 0; index < count; index++)); do
    path="$(release_manifest_bundle_field "$manifest_path" "$index" "path")"
    if [[ "$path" == "$expected_path" ]]; then
      match_count=$((match_count + 1))
      match_index="$index"
    fi
  done
  if (( match_count == 1 )); then
    printf '%s' "$match_index"
    return 0
  fi
  printf '%s' "$match_count"
  return 1
}

require_release_manifest_match() {
  local manifest_path="$1"
  local index="$2"
  local key="$3"
  local expected="$4"
  local label="$5"
  local path
  local actual
  path="$(release_manifest_bundle_field "$manifest_path" "$index" "path")"
  actual="$(release_manifest_bundle_field "$manifest_path" "$index" "$key")"
  if [[ "$actual" != "$expected" ]]; then
    echo "error: release-manifest.json validation failed: $label mismatch for ${path:-<unknown>}: manifest has '${actual:-<missing>}', bundle has '$expected'" >&2
    exit 1
  fi
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

  local bundle_count
  bundle_count="$(release_manifest_bundle_count "$manifest_path")"
  if (( bundle_count == 0 )); then
    echo "error: release-manifest.json validation failed: missing bundles array" >&2
    exit 1
  fi

  local app_index
  if ! app_index="$(release_manifest_bundle_index_for_path "$manifest_path" "KnowType.app")"; then
    echo "error: release-manifest.json validation failed: expected exactly one KnowType.app metadata entry, found $app_index" >&2
    exit 1
  fi
  require_release_manifest_match "$manifest_path" "$app_index" "bundleIdentifier" "$app_bundle_id" "bundleIdentifier"
  require_release_manifest_match "$manifest_path" "$app_index" "shortVersion" "$app_version" "shortVersion"
  require_release_manifest_match "$manifest_path" "$app_index" "buildVersion" "$app_build" "buildVersion"

  if [[ -n "$prefpane_path" && -d "$prefpane_path" ]]; then
    local prefpane_index
    if ! prefpane_index="$(release_manifest_bundle_index_for_path "$manifest_path" "KnowType.prefPane")"; then
      echo "error: release-manifest.json validation failed: expected exactly one KnowType.prefPane metadata entry, found $prefpane_index" >&2
      exit 1
    fi
    require_release_manifest_match "$manifest_path" "$prefpane_index" "bundleIdentifier" "$prefpane_bundle_id" "prefPane bundleIdentifier"
    require_release_manifest_match "$manifest_path" "$prefpane_index" "shortVersion" "$prefpane_version" "prefPane shortVersion"
    require_release_manifest_match "$manifest_path" "$prefpane_index" "buildVersion" "$prefpane_build" "prefPane buildVersion"
  fi
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
      SOURCE_BUNDLE_PATH="$("$SCRIPTS_DIR/build-inputmethod-bundle.sh" --configuration "$CONFIGURATION" --version "$LOCAL_SHORT_VERSION" --build "$LOCAL_BUILD_VERSION" | tail -n 1)"
      if (( WITH_PREFPANE == 1 )); then
        SOURCE_PREFPANE_PATH="$("$SCRIPTS_DIR/build-preference-pane.sh" --configuration "$CONFIGURATION" --version "$LOCAL_SHORT_VERSION" --build "$LOCAL_BUILD_VERSION" | tail -n 1)"
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
  SOURCE_PROVIDER_STORAGE_GENERATION="$(provider_storage_generation_for_bundle "$SOURCE_BUNDLE_PATH" || true)"

  if (( WITH_PREFPANE == 1 )) && [[ -z "$SOURCE_PREFPANE_PATH" ]]; then
    echo "error: --with-prefpane requested but source KnowType.prefPane was not found" >&2
    exit 1
  fi
  if (( WITH_PREFPANE == 1 )); then
    knowtype_validate_preferencepane_bundle_for_install "$SOURCE_PREFPANE_PATH" "$VERIFY_ENABLED"
    knowtype_validate_app_preferencepane_version_consistency "$SOURCE_BUNDLE_PATH" "$SOURCE_PREFPANE_PATH"
  fi
}

knowtype_require_safe_local_preferencepane_if_present "$PREFPANE_TARGET_PATH"

if (( DRY_RUN == 1 )); then
  if [[ "$SOURCE_MODE" != "build" ]]; then
    prepare_source_artifacts
  fi
  echo "KnowType input-method install dry run"
  echo "Source mode: $(install_state_source)"
  echo "Source path: $(install_source_path_summary)"
  [[ -n "$FROM_BUNDLE" ]] && echo "Source bundle: $FROM_BUNDLE"
  [[ -n "$FROM_RELEASE_ZIP" ]] && echo "Source release zip: $FROM_RELEASE_ZIP"
  [[ -n "$FROM_DMG_PAYLOAD" ]] && echo "Source DMG payload: $FROM_DMG_PAYLOAD"
  [[ -n "$SOURCE_BUNDLE_PATH" ]] && echo "Resolved source app: $SOURCE_BUNDLE_PATH"
  [[ -n "$SOURCE_GIT_TAG" ]] && echo "Release tag: $SOURCE_GIT_TAG"
  [[ -n "$SOURCE_GIT_COMMIT" ]] && echo "Release commit: $SOURCE_GIT_COMMIT"
  echo "Target bundle: $TARGET_PATH"
  echo "Quiesce plan: switch away from KnowType, disable old KnowType input-source rows, restart text-input agents, TERM the host, and close Settings writers."
  if (( FORCE_STOP_HOST == 1 )); then
    echo "Quiesce plan: --force-stop-host would KILL the host only after TERM fails."
  fi
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
  canonical_target_path="$(knowtype_canonical_bundle_path "$TARGET_PATH")"
  while IFS= read -r bundle_path; do
    [[ -n "$bundle_path" ]] || continue
    expanded_bundle_path="$(knowtype_expand_home_path "$(knowtype_strip_lsregister_suffix "$bundle_path")")"
    canonical_bundle_path="$(knowtype_canonical_bundle_path "$expanded_bundle_path")"
    if [[ -n "$canonical_target_path" && "$canonical_bundle_path" == "$canonical_target_path" ]]; then
      continue
    fi
    ls_count=$((ls_count + 1))
    echo "  $expanded_bundle_path"
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
  echo "Only the canonical installed app would be registered with LaunchServices: $TARGET_PATH"
  if [[ "$SOURCE_PROVIDER_STORAGE_GENERATION" =~ ^[0-9]+$ ]] &&
     (( SOURCE_PROVIDER_STORAGE_GENERATION >= 2 )); then
    echo "The installed app would migrate provider profiles to providers.v2.json before LaunchServices/TIS registration."
  else
    echo "The source app is pre-v2; current provider metadata would be downgraded or verified compatible before replacement, and the old migration CLI would not be invoked."
  fi
  echo "Menu acceptance would still require the real macOS input menu to show the K icon and 知键 entry."
  exit 0
fi

if (( DRY_RUN == 0 )); then
  quiesce_before_replace
fi

prepare_source_artifacts

mkdir -p "$TARGET_DIR"
if (( WITH_PREFPANE == 1 )); then
  mkdir -p "$PREFPANE_TARGET_DIR"
fi

stop_input_method_host_after_quiesce
require_input_method_host_stopped

if (( BACKUP_ENABLED == 1 )); then
  knowtype_create_install_backup "$TARGET_PATH" "$PREFPANE_TARGET_PATH" 0 "$KEEP_BACKUPS"
  BACKUP_ID="$KNOWTYPE_CREATED_BACKUP_ID"
  BACKUP_DIR="$KNOWTYPE_CREATED_BACKUP_DIR"
fi

prepare_provider_storage_for_source_bundle

if [[ -e "$TARGET_PATH" || -L "$TARGET_PATH" ]]; then
  knowtype_remove_local_inputmethod_bundle_if_safe "$TARGET_PATH" 0
fi
knowtype_cleanup_local_duplicate_bundles_except "" 0
cp -R "$SOURCE_BUNDLE_PATH" "$TARGET_PATH"
if [[ "$SOURCE_MODE" == "build" ]]; then
  rm -rf "$SOURCE_BUNDLE_PATH"
fi

if (( WITH_PREFPANE == 1 )); then
  knowtype_replace_local_preferencepane_bundle_atomically \
    "$SOURCE_PREFPANE_PATH" \
    "$PREFPANE_TARGET_PATH" \
    "$VERIFY_ENABLED"
  if [[ "$SOURCE_MODE" == "build" ]]; then
    rm -rf "$SOURCE_PREFPANE_PATH"
  fi
elif [[ -e "$PREFPANE_TARGET_PATH" || -L "$PREFPANE_TARGET_PATH" ]]; then
  knowtype_remove_local_preferencepane_bundle_if_safe "$PREFPANE_TARGET_PATH" 0
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

migrate_provider_profiles

launchservices_cleanup_output="$(knowtype_unregister_launchservices_records_except "$TARGET_PATH" 0)"
if [[ -n "$launchservices_cleanup_output" ]]; then
  printf '%s\n' "$launchservices_cleanup_output"
fi
STALE_LAUNCHSERVICES_CLEANUP_COUNT="$(printf '%s\n' "$launchservices_cleanup_output" | awk '/^Unregistered LaunchServices record:/{count++} END{print count+0}')"
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
repair_preferences_best_effort
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
elif command -v "$KNOWTYPE_PYTHON3" >/dev/null 2>&1; then
  if ! "$KNOWTYPE_PYTHON3" -c 'import json,sys; data=json.load(sys.stdin); sys.exit(1 if data.get("failures") else 0)' <<<"$postflight_json"; then
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
printf '  %-18s %s\n' "Source path:" "$(install_source_path_summary)"
printf '  %-18s %s\n' "Version:" "${installed_version:-<unknown>}"
printf '  %-18s %s\n' "Build:" "${installed_build:-<unknown>}"
printf '  %-18s %s\n' "Target:" "$TARGET_PATH"
printf '  %-18s %s\n' "Canonical target:" "$TARGET_PATH"
printf '  %-18s %s\n' "Install state:" "$(knowtype_install_state_path)"
printf '  %-18s %s\n' "Backup:" "${BACKUP_ID:-<none>}"
printf '  %-18s %s\n' "Postflight:" "$postflight_result"
printf '  %-18s disable=%s disabledCount=%s hostStop=%s menuAgentsRestarted=%s\n' \
  "Quiesce:" "$QUIESCE_DISABLE_STATUS" "$QUIESCE_DISABLED_COUNT" "$QUIESCE_HOST_STOP_STATUS" "$QUIESCE_MENU_AGENTS_RESTARTED"
printf '  %-18s writerStop=%s migration=%s\n' \
  "Provider profiles:" "$QUIESCE_PROVIDER_WRITER_STATUS" "$PROVIDER_MIGRATION_STATUS"
printf '  %-18s %s\n' "Stale LS cleanup:" "$STALE_LAUNCHSERVICES_CLEANUP_COUNT"

if (( WITH_PREFPANE == 1 )); then
  echo "Installed KnowType compatibility PreferencePane to: $PREFPANE_TARGET_PATH"
  echo "System Settings may show the compatibility KnowType pane after reopening."
else
  echo "KnowType settings are available from the input-method menu: KnowType 设置... (KnowType Settings... in explicit English UI)"
  echo "Default install keeps System Settings free of stale KnowType PreferencePane entries."
  if (( REMOVED_STALE_PREFPANE == 1 )); then
    echo "Removed stale KnowType compatibility PreferencePane from: $PREFPANE_TARGET_PATH"
  fi
fi

echo "Registered and enabled input source via standalone helper: $KNOWTYPE_ACTIVE_INPUT_MODE_ID"
echo "Postflight uses the JSON install snapshot only; run ./scripts/diagnose-inputmethod.sh --strict for full TIS diagnostics."
if [[ -n "$BACKUP_ID" ]]; then
  echo "Rollback command: ./scripts/rollback-inputmethod.sh --to $BACKUP_ID"
fi
echo "Menu acceptance required: the real macOS input menu must show the K icon and a 知键/KnowType entry; helper selection alone is not sufficient."
echo "Activate the target text app, select KnowType or run ./scripts/select-inputmethod.sh --require-selected, then type a real probe before manual acceptance."
echo "If System Settings asks to allow 知键/KnowType as an input method, click Allow before testing selection."
echo "If diagnostics show HIToolbox selected preference is still another source, choose KnowType from the active app's input menu/System Settings."
