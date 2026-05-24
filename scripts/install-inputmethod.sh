#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/inputsource-ids.sh"
source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"
source "$ROOT_DIR/scripts/lib/inputmethod-installation.sh"

DRY_RUN=0
CONFIGURATION="${CONFIGURATION:-release}"
WITH_PREFPANE="${KNOWTYPE_INSTALL_PREFPANE:-0}"
SOURCE_MODE="build"
FROM_BUNDLE=""
FROM_RELEASE_ZIP=""
BACKUP_ENABLED=1
VERIFY_ENABLED=1
KEEP_BACKUPS="$KNOWTYPE_DEFAULT_BACKUP_RETENTION"

usage() {
  cat <<'EOF'
Usage: scripts/install-inputmethod.sh [options]

Builds and installs KnowType.app into ~/Library/Input Methods, then asks the
installed app to register and enable the input source. KnowType-specific
settings are opened from the input-method menu's KnowType Settings item.

Options:
  --configuration debug|release  SwiftPM build configuration. Defaults to CONFIGURATION or release.
  --with-prefpane                Also build/install the compatibility KnowType.prefPane.
  --from-bundle PATH             Install an existing KnowType.app instead of building from source.
  --from-release-zip PATH        Install KnowType.app from a release zip and validate release metadata when present.
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

if [[ "$SOURCE_MODE" != "build" && -n "$FROM_BUNDLE" && -n "$FROM_RELEASE_ZIP" ]]; then
  echo "error: --from-bundle and --from-release-zip are mutually exclusive" >&2
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
INSTALLED_EXECUTABLE="$TARGET_PATH/Contents/MacOS/KnowTypeInputMethodApp"
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
  if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR/KnowType.app" ]]; then
    echo "Install failed; restoring previous KnowType backup: $BACKUP_ID" >&2
    rm -rf -- "$TARGET_PATH"
    cp -R "$BACKUP_DIR/KnowType.app" "$TARGET_PATH"
    if [[ -d "$BACKUP_DIR/KnowType.prefPane" ]]; then
      mkdir -p "$PREFPANE_TARGET_DIR"
      rm -rf -- "$PREFPANE_TARGET_PATH"
      cp -R "$BACKUP_DIR/KnowType.prefPane" "$PREFPANE_TARGET_PATH"
    else
      rm -rf -- "$PREFPANE_TARGET_PATH"
    fi
    knowtype_register_launchservices_path "$TARGET_PATH" 0
  fi
}

trap 'rollback_failed_install; cleanup_source_temp' EXIT

inputsource_tool_path() {
  if [[ -z "$INPUTSOURCE_TOOL" ]]; then
    INPUTSOURCE_TOOL="$(knowtype_inputsource_tool "$ROOT_DIR")"
  fi
  printf '%s\n' "$INPUTSOURCE_TOOL"
}

switch_away_before_replace() {
  local switched=1
  if [[ -x "$INSTALLED_EXECUTABLE" ]]; then
    "$INSTALLED_EXECUTABLE" --knowtype-switch-away >/dev/null 2>&1 &
    local switch_pid=$!
    for _ in {1..20}; do
      if ! kill -0 "$switch_pid" >/dev/null 2>&1; then
        wait "$switch_pid" || true
        switched=0
        break
      fi
      sleep 0.1
    done
    if [[ "$switched" -ne 0 ]]; then
      kill "$switch_pid" >/dev/null 2>&1 || true
      wait "$switch_pid" 2>/dev/null || true
      echo "warning: installed app did not finish switch-away request; falling back to helper" >&2
    fi
  fi
  if [[ "$switched" -ne 0 ]]; then
    local tool
    tool="$(inputsource_tool_path)" || return 0
    "$tool" switch-away \
      --prefix "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
      --fallback-id "$KNOWTYPE_FALLBACK_INPUT_SOURCE_ID" >/dev/null 2>&1 || true
  fi
}

repair_preferences_best_effort() {
  local tool
  if ! tool="$(inputsource_tool_path)"; then
    echo "warning: input-source helper is unavailable; continuing so installed app activation and diagnostics can run" >&2
    return 0
  fi
  if ! "$tool" repair-preferences \
    --bundle-id "$KNOWTYPE_PARENT_INPUT_SOURCE_ID" \
    --mode-id "$KNOWTYPE_ACTIVE_INPUT_MODE_ID" \
    --include-history \
    --add-active; then
    echo "warning: input-source preference repair failed; continuing so installed app activation and diagnostics can run" >&2
  fi
}

discover_release_manifest() {
  local zip_path="$1"
  local extracted_root="$2"
  local candidate
  candidate="$(find "$extracted_root" -maxdepth 4 -type f -name 'release-manifest.json' -print 2>/dev/null | head -n 1)"
  if [[ -z "$candidate" ]]; then
    local sibling
    sibling="$(dirname "$zip_path")/release-manifest.json"
    [[ -f "$sibling" ]] && candidate="$sibling"
  fi
  printf '%s' "$candidate"
}

prepare_source_artifacts() {
  case "$SOURCE_MODE" in
    build)
      SOURCE_GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true)"
      SOURCE_GIT_TAG="$(git -C "$ROOT_DIR" describe --tags --exact-match HEAD 2>/dev/null || true)"
      SOURCE_BUNDLE_PATH="$(KNOWTYPE_BUNDLE_BUILD_VERSION="$LOCAL_BUILD_VERSION" "$ROOT_DIR/scripts/build-inputmethod-bundle.sh" --configuration "$CONFIGURATION" | tail -n 1)"
      if (( WITH_PREFPANE == 1 )); then
        SOURCE_PREFPANE_PATH="$("$ROOT_DIR/scripts/build-preference-pane.sh" --configuration "$CONFIGURATION" | tail -n 1)"
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
      SOURCE_BUNDLE_PATH="$(find "$SOURCE_TEMP_DIR" -maxdepth 4 -type d -name 'KnowType.app' -print 2>/dev/null | head -n 1)"
      SOURCE_PREFPANE_PATH="$(find "$SOURCE_TEMP_DIR" -maxdepth 4 -type d -name 'KnowType.prefPane' -print 2>/dev/null | head -n 1)"
      SOURCE_RELEASE_MANIFEST="$(discover_release_manifest "$FROM_RELEASE_ZIP" "$SOURCE_TEMP_DIR")"
      if [[ -n "$SOURCE_RELEASE_MANIFEST" ]]; then
        SOURCE_RELEASE_MANIFEST_DIGEST="$(shasum -a 256 "$SOURCE_RELEASE_MANIFEST" | awk '{print $1}')"
        SOURCE_GIT_COMMIT="$(KNOWTYPE_RELEASE_MANIFEST="$SOURCE_RELEASE_MANIFEST" python3 - <<'PY'
import json, os
with open(os.environ["KNOWTYPE_RELEASE_MANIFEST"], encoding="utf-8") as handle:
    print(json.load(handle).get("releaseCommit", ""))
PY
)"
        SOURCE_GIT_TAG="$(KNOWTYPE_RELEASE_MANIFEST="$SOURCE_RELEASE_MANIFEST" python3 - <<'PY'
import json, os
with open(os.environ["KNOWTYPE_RELEASE_MANIFEST"], encoding="utf-8") as handle:
    print(json.load(handle).get("tag", ""))
PY
)"
      else
        echo "warning: release-manifest.json was not found in or beside the release zip; install-state will record release-zip without commit metadata" >&2
      fi
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
  echo "KnowType input-method install dry run"
  echo "Source mode: $(install_state_source)"
  [[ -n "$FROM_BUNDLE" ]] && echo "Source bundle: $FROM_BUNDLE"
  [[ -n "$FROM_RELEASE_ZIP" ]] && echo "Source release zip: $FROM_RELEASE_ZIP"
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

prepare_source_artifacts

mkdir -p "$TARGET_DIR"
if (( WITH_PREFPANE == 1 )); then
  mkdir -p "$PREFPANE_TARGET_DIR"
fi

switch_away_before_replace
sleep 0.2

killall KnowTypeInputMethodApp 2>/dev/null || true
for _ in {1..30}; do
  if ! pgrep -x KnowTypeInputMethodApp >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

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

"$INSTALLED_EXECUTABLE" --knowtype-purge-legacy

repair_preferences_best_effort

if ! "$INSTALLED_EXECUTABLE" --knowtype-install-activate; then
  echo "warning: installed app could not select KnowType in this process context; continuing so diagnostics can report the persisted state" >&2
fi

repair_preferences_best_effort

sleep 0.75
killall cfprefsd 2>/dev/null || true
killall TextInputMenuAgent 2>/dev/null || true
killall TextInputSwitcher 2>/dev/null || true
sleep 0.5
open -g "$TARGET_PATH" >/dev/null 2>&1 || true
sleep 0.5

knowtype_write_install_state \
  "$(install_state_source)" \
  "$TARGET_PATH" \
  "$([[ "$WITH_PREFPANE" == "1" ]] && printf '%s' "$PREFPANE_TARGET_PATH" || true)" \
  "$BACKUP_ID" \
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
if ! "$ROOT_DIR/scripts/diagnose-inputmethod.sh" --strict --path "$TARGET_PATH" >/dev/null 2>&1; then
  postflight_result="warning"
fi

INSTALL_SUCCEEDED=1

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

echo "Requested input source activation from installed app: $KNOWTYPE_ACTIVE_INPUT_MODE_ID"
echo "Run ./scripts/diagnose-inputmethod.sh --strict for the read-only install status check."
if [[ -n "$BACKUP_ID" ]]; then
  echo "Rollback command: ./scripts/rollback-inputmethod.sh --to $BACKUP_ID"
fi
echo "Activate the target text app, run ./scripts/select-inputmethod.sh --require-selected, then type a real probe before manual acceptance."
echo "If System Settings asks to allow 知键/KnowType as an input method, click Allow before testing selection."
echo "If diagnostics show HIToolbox selected preference is still another source, choose KnowType from the active app's input menu/System Settings."
