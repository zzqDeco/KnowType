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

usage() {
  cat <<'EOF'
Usage: scripts/rollback-inputmethod.sh [--list] [--latest | --to BACKUP_ID] [--dry-run]

Restores a previously backed up KnowType.app and optional KnowType.prefPane.
Rollback only swaps install artifacts; it does not modify Rime userdb, provider
profiles, Keychain secrets, ENV.md, CORRECTION.md, or LEXICAL_PROFILE.md.

Options:
  --list          List available backups.
  --latest        Restore the newest backup.
  --to BACKUP_ID  Restore a specific backup ID.
  --dry-run       Print actions without changing files or preferences.
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
restore_prefpane_staging_dir=""

cleanup_restore_staging() {
  [[ -n "$restore_app_staging_dir" && -d "$restore_app_staging_dir" ]] && rm -rf "$restore_app_staging_dir"
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
if ! knowtype_validate_inputmethod_bundle_for_install "$backup_dir/KnowType.app" 0; then
  exit 1
fi

backup_id="$(basename "$backup_dir")"

if (( DRY_RUN == 1 )); then
  echo "KnowType rollback dry run"
  echo "Backup: $backup_id"
  echo "Backup path: $backup_dir"
  echo "Target app: $target_path"
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
    --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID"
  )
  for legacy_id in "${KNOWTYPE_LEGACY_INPUT_MODE_IDS[@]}"; do
    switch_args+=(--legacy-mode-id "$legacy_id")
  done
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

if [[ -e "$target_path" || -L "$target_path" ]]; then
  knowtype_remove_local_inputmethod_bundle_if_safe "$target_path" 0
fi
mv "$restore_app_staging_dir/KnowType.app" "$target_path"
rm -rf "$restore_app_staging_dir"
restore_app_staging_dir=""

if [[ -d "$backup_dir/KnowType.prefPane" ]]; then
  rm -rf -- "$prefpane_path"
  mv "$restore_prefpane_staging_dir/KnowType.prefPane" "$prefpane_path"
  rm -rf "$restore_prefpane_staging_dir"
  restore_prefpane_staging_dir=""
else
  rm -rf -- "$prefpane_path"
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
  "$inputsource_tool" purge-legacy \
    --path "$target_path" \
    --parent-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
    --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" >/dev/null 2>&1 || true
  "$inputsource_tool" repair-preferences \
    --bundle-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
    --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" \
    --include-history \
    --add-active >/dev/null 2>&1 || true
  "$inputsource_tool" bootstrap \
    --path "$target_path" \
    --parent-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
    --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" >/dev/null 2>&1 || true
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
echo "Run ./scripts/diagnose-inputmethod.sh --strict to verify the restored install."
