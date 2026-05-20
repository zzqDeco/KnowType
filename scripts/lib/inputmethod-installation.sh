#!/usr/bin/env bash

KNOWTYPE_INSTALLATION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$KNOWTYPE_INSTALLATION_LIB_DIR/inputsource-ids.sh"

KNOWTYPE_PREFPANE_BUNDLE_ID="com.knowtype.preferencepane"
KNOWTYPE_LSREGISTER="${KNOWTYPE_LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"
KNOWTYPE_PLIST_BUDDY="${KNOWTYPE_PLIST_BUDDY:-/usr/libexec/PlistBuddy}"

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

knowtype_plistbuddy_value() {
  local key_path="$1"
  local plist="$2"
  local output
  if [[ -x "$KNOWTYPE_PLIST_BUDDY" ]] &&
     output="$("$KNOWTYPE_PLIST_BUDDY" -c "Print $key_path" "$plist" 2>/dev/null)"; then
    printf '%s' "$output"
  fi
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
