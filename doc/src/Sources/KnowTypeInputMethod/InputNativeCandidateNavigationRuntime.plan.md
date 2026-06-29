# InputNativeCandidateNavigationRuntime

## Responsibility

`InputNativeCandidateNavigationRuntime` owns Rime/native candidate navigation
state for the IMK coordinator.

It keeps the displayed candidate cache and currently selected
`InputCandidateSelection`, maps custom candidate-panel selections back to input
selection identities, resolves stable native candidate indexes, and drives Rime
highlight/page/select keys for navigation.

## Boundaries

- It may inspect `ConversionEngineSnapshot` and call
  `KnowTypeConversionEngine.process` for native highlight, page, and
  current-page selection keys.
- It may return navigation effects asking the coordinator to publish current
  local suggestions or refresh native highlight presentation.
- It must not call `insertText`, `setMarkedText`, `CandidatePanelPresenter`,
  AI runtimes, learning/feedback runtimes, lexical profile refresh, or host
  compatibility policy.
- The coordinator still owns Space priority, AI-row commit priority,
  selection-history learning, native conversion result handling, composition
  lifecycle, host writes, and candidate-panel publication requests.

## Behavior Notes

- Native prefix/full selections prefer encoded current-page native indexes.
  Duplicate surface text without a stable index is not treated as an implicit
  native selection.
- Hover and keyboard highlight update Rime's current-page highlight and ask the
  coordinator to refresh marked text and panel state; they never commit text.
- Arrow navigation moves within the current page first. Right/down at the end
  pages down then highlights row 1; left/up at the start pages up then
  highlights the previous page's last row.
- Explicit PageUp/PageDown and Rime-compatible paging symbols are delegated to
  the native engine. Paging symbols are not consumed when the native snapshot
  does not change, preserving punctuation fallback at page boundaries.
- Out-of-range numeric selection during active native composition is consumed
  without appending a literal digit.

## Tests

- `InputNativeCandidateNavigationRuntimeTests`
- `InputControllerCoordinatorTests`
- `InputCandidatePanelPublicationRuntimeTests`
- `InputHotPathPerformanceTests`
- `swift test`
