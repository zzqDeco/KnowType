# CorrectionEngine

## Responsibility

`CorrectionEngine` owns local prefix correction and candidate ranking before any
continuation is considered.

## Boundaries

- It may call a configured correction provider only through the core
  `LLMProvider` protocol and only when the input is eligible.
- It must not know provider-specific request or response shapes.
- It must not create continuation candidates; that belongs to
  `PrefixContinuationEngine`.

## Behavior Notes

- Level 0 protected input returns local identity candidates and stays on the
  no-provider path.
- Chinese input routes through `TraditionalInputEngine` when the locale allows
  it. English input stays on the English correction path.
- `InputContext.userSelectionHistory` can boost already-generated local
  candidates, but it must not manufacture candidates or leave the local process.
- Technical tokens such as `API`, `JSON`, `macOS`, `snake_case`, and
  `camelCase` must be preserved.

## Tests

- `CorrectionEngineTests`
- `ChineseInputRegressionCorpusTests`
- `TraditionalInputEngineTests` for local Chinese candidate behavior
