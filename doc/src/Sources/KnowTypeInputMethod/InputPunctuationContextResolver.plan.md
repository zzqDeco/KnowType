# InputPunctuationContextResolver

## Responsibility

`InputPunctuationContextResolver` classifies the character before the caret for
the narrow numeric-period exception.

## Boundaries

- It receives optional client context and returns only `asciiDigit`, `other`,
  or `unknown` plus a privacy-safe source.
- It does not parse numbers, URLs, IP addresses, list syntax, or document text.
- `InputPunctuatorRuntime` owns the final punctuation decision.

## Behavior Notes

- Active composition, non-collapsed selection, unknown ranges, missing clients,
  and moved carets return unknown.
- A client query has priority. If unavailable, the resolver may use the last
  KnowType insertion only when client identity and expected caret both match.
- Fallback evidence is invalidated by external navigation, deletion, or other
  unowned changes.
- Diagnostics may record classification and source but never the character or
  surrounding text.

## Tests

- `InputPunctuationContextResolverTests`
- `InputControllerCoordinatorTests`
- `InputHotPathPerformanceTests`
