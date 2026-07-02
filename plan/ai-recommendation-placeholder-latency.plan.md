# AI Recommendation Placeholder Latency

## Status

Active

## Summary

Keep the candidate panel visually stable while real-time AI recommendations wait
for input to settle. Eligible input should immediately show a fixed AI pending
row with a spinner, while provider transport still starts only after a shorter
input-method debounce.

## Scope

- Shorten the IMK-side AI dispatch debounce from 850 ms to 450 ms.
- Treat `.pending` as the current input's AI waiting state, covering both
  debounce and transport phases.
- Render pending AI rows with a fixed spinner accessory and keep them
  non-selectable.
- Keep provider requests stale-dropped rather than actively cancelled once
  transport has started.
- Do not change provider prompts, model selection, proxy configuration, Rime,
  candidate ranking, host writes, Settings UI, or install scripts.

## Implementation

- `InputAIRecommendationRuntime.schedule` returns `.pending(requestID)` as soon
  as scheduling is eligible, except for provider-availability probes and skip
  paths.
- The runtime still cancels only pre-transport debounce tasks on new input; old
  transport results continue through the existing generation/raw-revision stale
  gate.
- `CandidatePanelRowBuilder` marks pending AI rows with a spinner accessory.
  `CandidatePanelRenderer` carries the accessory to AppKit render rows.
- `CandidatePanelLayoutEngine` reserves spinner width in text measurement, and
  `CandidatePanelContentView` creates a small indeterminate `NSProgressIndicator`
  for the row.
- AI diagnostics add a privacy-safe `pending_placeholder` stage; logs include
  request ids, lengths, revisions, elapsed timings, and reasons, never raw text
  or provider output.

## Test Plan

- `swift test --quiet --filter InputAIRecommendationRuntimeTests`
- `swift test --quiet --filter CandidatePanelRowBuilderTests`
- `swift test --quiet --filter CandidatePanelRendererTests`
- `swift test --quiet --filter CandidatePanelStateTests`
- `swift test --quiet --filter CandidatePanelWindowControllerTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

Manual acceptance: install the branch build, enable `KNOWTYPE_AI_DEBUG=1` and
`KNOWTYPE_PANEL_DEBUG=1`, type a long pinyin string, pause briefly, then continue
typing after AI appears. The AI row should become a spinner placeholder instead
of disappearing, and stale provider results must not interrupt the current input.

## Assumptions

- 450 ms is the first user-facing default for the IMK-side debounce.
- Pending rows reserve one row of height and spinner width; full panel width
  still follows existing candidate layout rules.
- Too-short, disabled, protected, and unavailable-provider states are not
  eligible AI waits and do not show the spinner placeholder.
