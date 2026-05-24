# Models

## Responsibility

`Models.swift` owns cross-layer product data structures used by core,
providers, settings, and the input-method package.

## Boundaries

- Provider-native JSON shapes do not belong here.
- AppKit, SwiftUI, and InputMethodKit types should not leak into these models.

## Behavior Notes

- `LLMRequest` and `LLMResponse` are the normalized provider boundary.
- `LLMRequest.candidateHints` carries current-page Rime candidates as provider
  context; hints are not confirmed text and do not imply a locked prefix.
- Correction, locked-prefix, continuation, protection, and suggestion models
  encode the product rule that continuation appends after a locked prefix.
- Local-only ranking hints such as user selection history are input context, not
  provider payload.

## Tests

- Provider adapter tests for normalized request/response behavior
- Core correction and continuation tests for model invariants
- Input-method tests for `SuggestionResponse` rendering and commit behavior
