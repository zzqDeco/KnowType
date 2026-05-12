# KnowType MVP Acceptance

The MVP is accepted when these flows pass through package-level tests and then through manual macOS IMK verification.

## Automated Scenarios

- Chinese typo correction: `wo jue de zhege fagnan -> 我觉得这个方案`
- Mixed technical input: `zhege api latnecy youdian gao -> 这个 API latency 有点高`
- English correction: `I thikn this approch -> I think this approach`
- Level 0 path input: `/Users/zq/project/KnowType` is not rewritten
- Explicit polish only: `Option + R` is the only default path that requests rewriting

## Manual macOS Scenarios

- TextEdit: candidate panel appears and `Space` commits prefix only.
- Safari or Chrome text field: `Tab` commits prefix plus first continuation.
- Xcode editor: technical tokens and code-like identifiers are preserved.
- Terminal: path and command-like input stays Level 0.
- WeChat or Feishu: candidate window remains usable in common chat input fields.

## Current Automation

`Tests/KnowTypeInputMethodTests/MVPAcceptanceTests.swift` verifies the product-level flow through `InputMethodPipeline` and `InputCompositionController`.
