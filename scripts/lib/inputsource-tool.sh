#!/usr/bin/env bash

knowtype_inputsource_tool() {
  local root_dir="$1"
  local configuration="${CONFIGURATION:-debug}"
  local tool_path="${KNOWTYPE_INPUTSOURCE_TOOL:-}"

  if [[ -z "$tool_path" ]]; then
    swift build --package-path "$root_dir" --configuration "$configuration" --product knowtype-inputsource-tool >&2
    local bin_dir
    bin_dir="$(swift build --package-path "$root_dir" --configuration "$configuration" --show-bin-path 2>/dev/null)"
    tool_path="$bin_dir/knowtype-inputsource-tool"
  fi

  if [[ ! -x "$tool_path" ]]; then
    echo "error: KnowType input-source helper is missing or not executable: $tool_path" >&2
    return 1
  fi

  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$CODESIGN_IDENTITY" "$tool_path" >/dev/null
  fi

  printf '%s\n' "$tool_path"
}
