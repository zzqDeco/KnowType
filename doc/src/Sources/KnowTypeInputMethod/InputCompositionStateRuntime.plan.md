# InputCompositionStateRuntime

## Responsibility

`InputCompositionStateRuntime` stores the text half of
`InputActiveSessionRuntime`: raw input, `CompositionBuffer`, composition id,
raw revision, and delete count before commit.

## Boundaries

- It mutates only in-memory composition state.
- It exposes immutable `TextComposition` snapshots through the active-session
  runtime for coordinator code that builds Rime, AI,
  candidate-panel, write, and learning contexts.
- It must not call Rime, host clients, marked-text writers, candidate-panel
  presenters, AI runtimes, lexical runtimes, preference stores, or anchor
  resolvers.

## Behavior Notes

- `appendText`, `deleteBackward`, `applySegmentCandidate`, native raw sync, and
  lifecycle reset are the only mutation entry points for raw/buffer state.
- `deleteBackward` reports whether it removed a raw character, only undid a
  resolved segment, or emptied the raw input so the coordinator can keep Rime
  and anchor reset side effects in the old order.
- Lifecycle commit text is read before coordinator reset side effects; reset
  clears raw/buffer/delete count and advances raw revision without inserting
  text or hiding panels.
- Requested composition ids let the active-session runtime keep text and symbol
  sessions in one monotonic id domain.

## Tests

- `InputCompositionStateRuntimeTests`
- `InputControllerCoordinatorTests`
- `InputHotPathPerformanceTests`
