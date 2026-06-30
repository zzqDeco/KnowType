# LexicalContext

## Responsibility

`LexicalContextBuilder` creates the bounded lexical and tone summary that can
be attached to real-time AI recommendation requests after the input-method
schedule policy says the request is eligible.

## Boundaries

- It summarizes recent commits, recent selection history, accepted-AI summaries,
  and Rime userdb terms. It does not read the active Rime session, AppKit host
  state, provider credentials, or candidate panel state.
- Input-method callers should not construct lexical context for schedule-skip
  paths such as short raw input, disabled cloud continuation, partial
  composition, or no provider.

## Behavior Notes

- Sanitization removes protected-looking fragments and keeps only bounded
  profile text suitable for provider context.
- Repeated sanitization checks use cached regular expressions rather than
  compiling regexes on every key event.
- Accepted-AI summary terms are canonical when the same text also appears in
  current recent commits.

## Tests

- `InputAIRecommendationRuntimeTests`
- `InputControllerCoordinatorTests`
- `InputHotPathPerformanceTests`
- `swift test`
