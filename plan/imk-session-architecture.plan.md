# IMK Session Architecture

Goal: make the InputMethodKit frontend a thin bridge over explicit KnowType input session state and shared commit policies.

Scope:

- model session modes as `empty`, `composing`, `candidate`, `aiPending`, `polish`, and `ascii`
- keep `InputController` focused on IMK lifecycle, client lookup, marked text, commit insertion, palette visibility, and candidate window anchoring
- route product commit decisions through session-level policy so native candidate selection, stale fallback, and shortcuts stay consistent
- model key-down, key-up, and flag-change input intents without AppKit dependencies in unit tests
- preserve MVP rules: `Space` commits best prefix, `Tab` commits prefix plus first continuation, `Option+number` commits continuation, `Option+R` requests polish only, and Level 0 never calls providers

Validation:

- `swift test --filter KnowTypeInputMethodTests`
- manual IMK smoke test in TextEdit after bundle install when exercising AppKit UI behavior
