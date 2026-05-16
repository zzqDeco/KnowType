#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

usage() {
  cat <<'EOF'
Usage: scripts/smoke-inputmethod-install.sh

Runs deterministic install/profile smoke checks without installing KnowType,
selecting an input source, or installing a configuration profile.

Options:
  -h, --help  Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
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

assert_file() {
  local path="$1"
  [[ -f "$path" ]] || die "missing file: $path"
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

if [[ ! -x "$PLIST_BUDDY" ]]; then
  die "PlistBuddy is unavailable at $PLIST_BUDDY"
fi

while IFS= read -r script_path; do
  bash -n "$script_path"
done < <(find "$ROOT_DIR/scripts" -type f -name '*.sh' | sort)

help_scripts=(
  "$ROOT_DIR/scripts/build-inputmethod-bundle.sh"
  "$ROOT_DIR/scripts/create-local-system-policy-profile.sh"
  "$ROOT_DIR/scripts/diagnose-inputmethod.sh"
  "$ROOT_DIR/scripts/install-inputmethod.sh"
  "$ROOT_DIR/scripts/select-inputmethod.sh"
  "$ROOT_DIR/scripts/smoke-inputmethod-install.sh"
  "$ROOT_DIR/scripts/uninstall-inputmethod.sh"
)

for script_path in "${help_scripts[@]}"; do
  "$script_path" --help >/dev/null
done

source "$ROOT_DIR/scripts/lib/inputsource-tool.sh"
declare -F knowtype_inputsource_tool >/dev/null ||
  die "scripts/lib/inputsource-tool.sh did not load knowtype_inputsource_tool"

bundle_path="$("$ROOT_DIR/scripts/build-inputmethod-bundle.sh")"
assert_equals "$ROOT_DIR/dist/KnowType.app" "$bundle_path" "bundle path"
assert_dir "$bundle_path"
assert_file "$bundle_path/Contents/Info.plist"
assert_file "$bundle_path/Contents/MacOS/KnowTypeInputMethodApp"
[[ -x "$bundle_path/Contents/MacOS/KnowTypeInputMethodApp" ]] ||
  die "input-method executable is not executable"
assert_dir "$bundle_path/Contents/Resources/KnowType_KnowTypeCore.bundle"
assert_file "$bundle_path/Contents/Resources/KnowTypeInputMethodIcon.tiff"
assert_equals "com.knowtype.inputmethod.KnowType" \
  "$(plist_read ":CFBundleIdentifier" "$bundle_path/Contents/Info.plist")" \
  "CFBundleIdentifier"
assert_equals "KnowTypeInputMethodApp" \
  "$(plist_read ":CFBundleExecutable" "$bundle_path/Contents/Info.plist")" \
  "CFBundleExecutable"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/knowtype-profile-smoke.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
profile_path="$tmp_dir/KnowTypeLocalSystemPolicy.mobileconfig"
profile_output="$("$ROOT_DIR/scripts/create-local-system-policy-profile.sh" --path "$bundle_path" --output "$profile_path")"

assert_file "$profile_path"
plutil -lint "$profile_path" >/dev/null

expected_requirement="$(codesign -dr - "$bundle_path" 2>&1 | sed -n 's/^designated => //p')"
[[ -n "$expected_requirement" ]] || die "codesign did not return a designated requirement"
actual_requirement="$(plist_read ":PayloadContent:0:Requirement" "$profile_path")"
assert_equals "$expected_requirement" "$actual_requirement" "SystemPolicyRule requirement"

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

codesign_details="$(codesign -dv "$bundle_path" 2>&1)"
signing_identifier="$(codesign_value "Identifier" "$codesign_details")"
team_identifier="$(codesign_value "TeamIdentifier" "$codesign_details")"
signature_kind="$(codesign_value "Signature" "$codesign_details")"

if [[ -n "$signing_identifier" ]]; then
  assert_contains "$actual_requirement" "$signing_identifier" "designated requirement"
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
