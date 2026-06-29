# HostCompatibilityProfile

## Responsibility

`HostCompatibilityProfile` owns the bundle-id compatibility table for the host
carrier layer.

## Boundaries

- It decides only the host carrier profile: inline marked text, placeholder
  marked text, and explicit terminal-style placeholder matching.
- It does not decide candidate-panel rows, Rime state, AI behavior, key mapping,
  input-mode defaults, ASCII passthrough, or input-source registration.
- UserDefaults write-mode overrides remain in `InputClientCompatibilityPolicy`
  and take precedence over this table.

## Behavior Notes

- TextEdit, Safari, Chrome, unknown AppKit-style clients, and other unmatched
  hosts default to inline composition.
- Codex, Xcode, VS Code, Electron, ToDesktop, and JetBrains-style hosts also
  default to inline composition; their code-app punctuation and symbol defaults
  are owned by `InputModeAppPolicy`, not this carrier table.
- Terminal, iTerm, MacVim, and Emacs-style hosts use placeholder carrier during
  Chinese composition and start from the ASCII idle policy owned by
  `InputModeAppPolicy`.
- The compatibility table is deliberately close to mature IME app-option tables:
  matching by exact bundle id or stable prefix, with the effect limited to the
  carrier layer.

## Tests

- `HostCompatibilityProfileTests`
- `InputClientCompatibilityPolicyTests`
- `InputControllerCoordinatorTests`
