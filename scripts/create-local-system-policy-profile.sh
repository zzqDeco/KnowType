#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_BUNDLE_PATH="$HOME/Library/Input Methods/KnowType.app"
BUNDLE_PATH="${KNOWTYPE_BUNDLE_PATH:-$DEFAULT_BUNDLE_PATH}"
OUTPUT_PATH="$ROOT_DIR/dist/KnowTypeLocalSystemPolicy.mobileconfig"
OPEN_AFTER_CREATE=0

usage() {
  cat <<'EOF'
Usage: scripts/create-local-system-policy-profile.sh [--path /path/to/KnowType.app] [--output file.mobileconfig] [--open]

Creates a macOS SystemPolicyRule configuration profile that allows the currently
installed KnowType local development build to pass Gatekeeper execute
assessment. This is for local Apple Development testing on macOS 15+, where
spctl --add is no longer supported.

Options:
  --path    KnowType.app bundle to inspect. Defaults to ~/Library/Input Methods/KnowType.app.
  --output  Profile path to write. Defaults to dist/KnowTypeLocalSystemPolicy.mobileconfig.
  --open    Open the generated profile so macOS can show the manual install UI.
  -h, --help
            Show this help.
EOF
}

xml_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

while (($# > 0)); do
  case "$1" in
    --path)
      if (($# < 2)); then
        echo "error: --path requires a value" >&2
        exit 2
      fi
      BUNDLE_PATH="$2"
      shift 2
      ;;
    --output)
      if (($# < 2)); then
        echo "error: --output requires a value" >&2
        exit 2
      fi
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --open)
      OPEN_AFTER_CREATE=1
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

if [[ ! -d "$BUNDLE_PATH" ]]; then
  echo "error: bundle does not exist: $BUNDLE_PATH" >&2
  echo "Run ./scripts/install-inputmethod.sh first." >&2
  exit 1
fi

if ! command -v codesign >/dev/null 2>&1; then
  echo "error: codesign is unavailable" >&2
  exit 1
fi

CODESIGN_DETAILS="$(codesign -dvvv "$BUNDLE_PATH" 2>&1 || true)"

codesign_value() {
  local key="$1"
  printf '%s\n' "$CODESIGN_DETAILS" |
    awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }'
}

DESIGNATED_REQUIREMENT_OUTPUT="$(codesign -dr - "$BUNDLE_PATH" 2>&1 || true)"
DESIGNATED_REQUIREMENT="$(
  printf '%s\n' "$DESIGNATED_REQUIREMENT_OUTPUT" |
    sed -n 's/^designated => //p' |
    head -n 1
)"
REQUIREMENT_SOURCE="codesign designated requirement"

if [[ -z "$DESIGNATED_REQUIREMENT" ]]; then
  DESIGNATED_REQUIREMENT="$(
    printf '%s\n' "$DESIGNATED_REQUIREMENT_OUTPUT" |
      sed -n 's/^# designated => //p' |
      head -n 1
  )"
  REQUIREMENT_SOURCE="codesign implied designated requirement"
fi

if [[ -z "$DESIGNATED_REQUIREMENT" ]]; then
  CD_HASH="$(codesign_value "CDHash")"
  if [[ -n "$CD_HASH" ]]; then
    DESIGNATED_REQUIREMENT="cdhash H\"$CD_HASH\""
    REQUIREMENT_SOURCE="codesign CDHash fallback"
  fi
fi

if [[ -z "$DESIGNATED_REQUIREMENT" ]]; then
  echo "error: could not read or derive the bundle designated requirement" >&2
  exit 1
fi

SIGNING_IDENTIFIER="$(codesign_value "Identifier")"
TEAM_IDENTIFIER="$(codesign_value "TeamIdentifier")"
SIGNATURE_KIND="$(codesign_value "Signature")"
AUTHORITY_SUMMARY="$(
  printf '%s\n' "$CODESIGN_DETAILS" |
    awk -F= '$1 == "Authority" {
      value = substr($0, index($0, "=") + 1)
      if (out != "") {
        out = out ", "
      }
      out = out value
    } END {
      print out
    }'
)"

SIGNING_IDENTIFIER="${SIGNING_IDENTIFIER:-unknown}"
TEAM_IDENTIFIER="${TEAM_IDENTIFIER:-not set}"
SIGNATURE_KIND="${SIGNATURE_KIND:-unknown}"
AUTHORITY_SUMMARY="${AUTHORITY_SUMMARY:-none}"
SIGNING_SUMMARY="identifier=$SIGNING_IDENTIFIER; team=$TEAM_IDENTIFIER; signature=$SIGNATURE_KIND"
if [[ "$AUTHORITY_SUMMARY" != "none" ]]; then
  SIGNING_SUMMARY="$SIGNING_SUMMARY; authority=$AUTHORITY_SUMMARY"
fi

PROFILE_UUID="$(uuidgen)"
PAYLOAD_UUID="$(uuidgen)"
RULE_COMMENT="Allow local KnowType input method build at $BUNDLE_PATH ($SIGNING_SUMMARY)"
ESCAPED_RULE_COMMENT="$(printf '%s' "$RULE_COMMENT" | xml_escape)"
ESCAPED_REQUIREMENT="$(printf '%s' "$DESIGNATED_REQUIREMENT" | xml_escape)"
mkdir -p "$(dirname "$OUTPUT_PATH")"

cat > "$OUTPUT_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>Comment</key>
      <string>$ESCAPED_RULE_COMMENT</string>
      <key>OperationType</key>
      <string>operation:execute</string>
      <key>PayloadDescription</key>
      <string>Allows the locally signed KnowType input method bundle to pass Gatekeeper execute assessment for local development testing.</string>
      <key>PayloadDisplayName</key>
      <string>KnowType Local Development System Policy Rule</string>
      <key>PayloadIdentifier</key>
      <string>com.knowtype.local.systempolicy.rule</string>
      <key>PayloadType</key>
      <string>com.apple.systempolicy.rule</string>
      <key>PayloadUUID</key>
      <string>$PAYLOAD_UUID</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>Priority</key>
      <real>1000.0</real>
      <key>Requirement</key>
      <string>$ESCAPED_REQUIREMENT</string>
    </dict>
  </array>
  <key>PayloadDescription</key>
  <string>Local development policy for testing KnowType input method builds signed with the current Apple Development identity.</string>
  <key>PayloadDisplayName</key>
  <string>KnowType Local Development Policy</string>
  <key>PayloadIdentifier</key>
  <string>com.knowtype.local.systempolicy</string>
  <key>PayloadOrganization</key>
  <string>KnowType</string>
  <key>PayloadRemovalDisallowed</key>
  <false/>
  <key>PayloadScope</key>
  <string>System</string>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>$PROFILE_UUID</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
</dict>
</plist>
EOF

plutil -lint "$OUTPUT_PATH" >/dev/null

cat <<EOF
Created: $OUTPUT_PATH
Bundle: $BUNDLE_PATH
Requirement: $DESIGNATED_REQUIREMENT
Requirement Source: $REQUIREMENT_SOURCE
PayloadIdentifier: com.knowtype.local.systempolicy
Rule PayloadIdentifier: com.knowtype.local.systempolicy.rule
Rule PayloadType: com.apple.systempolicy.rule
Signing Identifier: $SIGNING_IDENTIFIER
Team Identifier: $TEAM_IDENTIFIER
Signature: $SIGNATURE_KIND
Authority: $AUTHORITY_SUMMARY

macOS 11+ does not allow installing configuration profiles from the profiles
CLI. Install this profile through System Settings, then run:

  spctl --assess --type execute --verbose=4 "$BUNDLE_PATH"
  ./scripts/select-inputmethod.sh --require-selected

Remove the profile after local testing if you no longer need this Apple
Development build allow rule.
EOF

if (( OPEN_AFTER_CREATE == 1 )); then
  open "$OUTPUT_PATH"
fi
