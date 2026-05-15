# Sources/KnowTypeDemo

`KnowTypeDemo` is a package-level MVP executable for exercising KnowType before the signed macOS input-method bundle exists.

It wires:

- `InputSessionController`
- `CandidatePanelRenderer`
- `InputAction` commit simulation

Supported options:

- `--locale zh-CN|en-US|mixed`
- `--action space|tab|optionN|polish`

The executable is intentionally local-only and uses the fallback provider path. Cloud provider configuration remains in `KnowTypeProviders`.
