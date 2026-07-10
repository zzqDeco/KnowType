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
- Browser, editor, IDE, Electron/ToDesktop, JetBrains-style, and unknown hosts
  default to inline carrier. Host identity does not choose text or punctuation
  mode.
- Any host uses `asciiPassthrough` while idle when the shared input mode is
  ASCII and width is half. Full-width printable ASCII is transformed and
  inserted before this policy runs. Terminal, iTerm, MacVim, and Emacs-style
  hosts begin in the same linked Chinese mode as all other apps.
- During active Chinese composition, terminal-style or override commit-only
  hosts use `commitOnlyComposition`: KnowType writes a full-width-space
  attributed marked-text placeholder to keep the host composition and candidate
  anchor alive without exposing raw pinyin in the host text field. The real
  preedit display is owned by candidate-panel state, not by this policy.
- `Option + /` switches the process-wide mode between Chinese composition and
  ASCII input for every host; half-width ASCII passes through and full-width
  ASCII is inserted by KnowType.
- Missing clients use `disabled`, allowing printable idle input to return
  unhandled rather than being swallowed.
- Override keys use `input.client.<bundle id>.writeMode` in the shared
  `com.knowtype.preferences` defaults domain.

## Tests

- `HostCompatibilityProfileTests`
- `InputClientCompatibilityPolicyTests`
- `InputControllerCoordinatorTests`
- `InputSymbolModeTests`
