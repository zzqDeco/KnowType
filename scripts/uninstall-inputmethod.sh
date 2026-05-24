#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"
source "$ROOT_DIR/scripts/lib/inputmethod-installation.sh"
DRY_RUN=0
BACKUP_ENABLED=1
PURGE_BACKUPS=0

usage() {
  cat <<'EOF'
Usage: scripts/uninstall-inputmethod.sh [--dry-run] [--no-backup] [--purge-backups]

Removes all local KnowType input method bundles from ~/Library/Input Methods
and removes the optional compatibility KnowType PreferencePane when installed.

Options:
  --dry-run        Print removal actions without changing files or preferences.
  --no-backup      Remove install artifacts without creating an app/prefPane backup.
  --purge-backups  Delete existing KnowType install backups. User data is still preserved.
  -h, --help       Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-backup)
      BACKUP_ENABLED=0
      shift
      ;;
    --purge-backups)
      PURGE_BACKUPS=1
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

PREFPANE_TARGET_PATH="$(knowtype_preferencepane_target_path)"
TARGET_PATH="$(knowtype_inputmethod_target_path)"
BACKUP_ROOT="$(knowtype_backup_root_dir)"
INSTALL_STATE_PATH="$(knowtype_install_state_path)"

if (( BACKUP_ENABLED == 1 )); then
  knowtype_create_install_backup "$TARGET_PATH" "$PREFPANE_TARGET_PATH" "$DRY_RUN" "$KNOWTYPE_DEFAULT_BACKUP_RETENTION"
  knowtype_prune_install_backups "$KNOWTYPE_DEFAULT_BACKUP_RETENTION" "$DRY_RUN"
fi

if (( DRY_RUN == 0 )); then
  INPUTSOURCE_TOOL="$(knowtype_inputsource_tool "$ROOT_DIR")"
  "$INPUTSOURCE_TOOL" switch-away \
    --prefix "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
    --fallback-id "$KNOWTYPE_FALLBACK_INPUT_SOURCE_ID" >/dev/null 2>&1 || true
  killall KnowTypeInputMethodApp 2>/dev/null || true
fi

bundle_count=0
while IFS= read -r bundle_path; do
  [[ -n "$bundle_path" ]] || continue
  bundle_count=$((bundle_count + 1))
  knowtype_unregister_launchservices_path "$bundle_path" "$DRY_RUN"
  knowtype_remove_local_inputmethod_bundle_if_safe "$bundle_path" "$DRY_RUN"
done < <(knowtype_find_local_inputmethod_bundle_paths)

knowtype_unregister_launchservices_records_except "" "$DRY_RUN"

if [[ -d "$PREFPANE_TARGET_PATH" ]]; then
  if (( DRY_RUN == 1 )); then
    echo "[dry-run] Would remove KnowType compatibility PreferencePane: $PREFPANE_TARGET_PATH"
  else
    rm -rf -- "$PREFPANE_TARGET_PATH"
    echo "Removed KnowType compatibility PreferencePane: $PREFPANE_TARGET_PATH"
  fi
fi

knowtype_clean_preferencepane_caches "$DRY_RUN"
knowtype_quit_system_settings_if_running "$DRY_RUN"

if [[ -f "$INSTALL_STATE_PATH" ]]; then
  if (( DRY_RUN == 1 )); then
    echo "[dry-run] Would remove KnowType install state: $INSTALL_STATE_PATH"
  else
    rm -f -- "$INSTALL_STATE_PATH"
    echo "Removed KnowType install state: $INSTALL_STATE_PATH"
  fi
fi

if (( PURGE_BACKUPS == 1 )); then
  if [[ -d "$BACKUP_ROOT" ]]; then
    if (( DRY_RUN == 1 )); then
      echo "[dry-run] Would delete KnowType install backups: $BACKUP_ROOT"
    else
      rm -rf -- "$BACKUP_ROOT"
      echo "Deleted KnowType install backups: $BACKUP_ROOT"
    fi
  fi
elif [[ -d "$BACKUP_ROOT" ]]; then
  echo "Preserved KnowType install backups: $BACKUP_ROOT"
fi

if (( DRY_RUN == 0 )); then
  INPUTSOURCE_TOOL="$(knowtype_inputsource_tool "$ROOT_DIR")"
  "$INPUTSOURCE_TOOL" repair-preferences \
    --bundle-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
    --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" \
    --include-history >/dev/null 2>&1 || true
fi

if (( bundle_count == 0 )); then
  echo "No local KnowType input method bundles were found."
elif (( DRY_RUN == 1 )); then
  echo "Would remove $bundle_count local KnowType input method bundle(s)."
else
  echo "Removed $bundle_count local KnowType input method bundle(s)."
fi
