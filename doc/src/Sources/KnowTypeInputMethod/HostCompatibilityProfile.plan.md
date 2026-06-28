# HostCompatibilityProfile

## Responsibility

`HostCompatibilityProfile` owns the bundle-id compatibility table for the host
carrier layer.

## Boundaries

- It decides only the host carrier profile: inline marked text, placeholder
  marked text, and terminal-style idle ASCII default metadata.
- It does not decide candidate-panel rows, Rime state, AI behavior, key mapping,
  or input-source registration.
- UserDefaults write-mode overrides remain in `InputClientCompatibilityPolicy`
  and take precedence over this table.

## Behavior Notes

- TextEdit, Safari, Chrome, unknown AppKit-style clients, and other unmatched
  hosts default to inline composition.
- Codex, Xcode, VS Code, Electron, ToDesktop, and JetBrains-style hosts default
  to placeholder composition for Chinese input.
- Terminal, iTerm, MacVim, and Emacs-style hosts use the same placeholder
  carrier during Chinese composition but start from the ASCII idle policy owned
  by `InputModeAppPolicy`.
- The compatibility table is deliberately close to mature IME app-option tables:
  matching by exact bundle id or stable prefix, with the effect limited to the
  carrier layer.

## Tests

- `HostCompatibilityProfileTests`
- `InputClientCompatibilityPolicyTests`
- `InputControllerCoordinatorTests`
