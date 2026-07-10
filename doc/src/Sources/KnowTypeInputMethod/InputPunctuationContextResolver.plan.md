# InputPunctuationContextResolver

## Responsibility

`InputPunctuationContextResolver` classifies the character before the caret for
Chinese quote context and reuses recorded insertion context for the numeric-period
exception.

## Boundaries

- It returns ASCII digit, whitespace, opening punctuation, closing punctuation,
  text, or unknown plus a privacy-safe source and a selection/focus-change bit.
- It does not parse numbers, URLs, IP addresses, list syntax, or document text.
- `InputPunctuatorRuntime` owns the final punctuation decision.

## Behavior Notes

- Active composition behaves as preceding text for quote closure. Non-collapsed
  selection, unknown ranges, and missing clients return unknown; a known
  document start is opening context.
- A client query has priority. If unavailable, the resolver may use the last
  KnowType insertion only when client identity and expected caret both match.
- Client document text is queried only for contextual Chinese half-width quote
  keys. English and full-width quotes skip the query. Period decisions use the
  recorded insertion path so the decimal exception does not add a document read.
- Whitespace and Unicode opening/initial punctuation open quotes. Text, digits,
  and closing/final punctuation close quotes. Unknown context remains available
  to the punctuator's session alternation.
- Fallback evidence is invalidated by external navigation, deletion, focus
  change, or other unowned changes.
- Diagnostics may record classification and source but never the character or
  surrounding text.

## Tests

- `InputPunctuationContextResolverTests`
- `InputControllerCoordinatorTests`
- `InputHotPathPerformanceTests`
