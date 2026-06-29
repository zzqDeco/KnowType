# InputClientCompatibilityPolicy

## Responsibility

`InputClientCompatibilityPolicy` maps the focused host app, current
`InputModeState`, composition activity, and client availability to an
`InputClientWriteMode`, using `HostCompatibilityProfile` for the bundle-id
carrier table.

## Boundaries

- It decides write mode only. Host profile matching stays in
  `HostCompatibilityProfile`; key mapping, composition state, candidate rows,
  and host writes stay in `InputControllerCoordinator`.
- It must not inspect or log user text.
- Per-host overrides are read from UserDefaults, but no settings UI is owned
  here.

## Behavior Notes

- Unknown hosts use `inlineComposition` so standard AppKit clients keep marked
  text behavior.
- Codex, Xcode, VS Code, Electron, ToDesktop, and JetBrains-style hosts default
  to inline carrier; their code-app input defaults remain in
  `InputModeAppPolicy`.
- Any host uses `asciiPassthrough` while idle when the active input mode is
  ASCII. Terminal, iTerm, MacVim, and Emacs-style hosts receive that ASCII idle
  mode from `InputModeAppPolicy` by default.
- During active Chinese composition, terminal-style or override commit-only
  hosts use `commitOnlyComposition`: KnowType writes a full-width-space
  attributed marked-text placeholder to keep the host composition and candidate
  anchor alive without exposing raw pinyin in the host text field. The real
  preedit display is owned by candidate-panel state, not by this policy.
- `Option + /` is the supported session-local path for switching terminal-style
  hosts between Chinese placeholder composition and idle ASCII passthrough.
- Missing clients use `disabled`, allowing printable idle input to return
  unhandled rather than being swallowed.
- Override keys use `input.client.<bundle id>.writeMode` in the shared
  `com.knowtype.preferences` defaults domain.

## Tests

- `HostCompatibilityProfileTests`
- `InputClientCompatibilityPolicyTests`
- `InputControllerCoordinatorTests`
- `InputSymbolModeTests`
