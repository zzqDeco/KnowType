# RimeUserDBLexicalProfile

## Responsibility

Maintains the AI lexical profile boundary between Rime's persisted user
frequency data and provider context documents.

## Boundaries

- Parses only Rime sync text exports shaped as `text<TAB>code<TAB>frequency`.
- Does not read Rime `.ldb` files or retain complete userdb exports.
- Persists canonical profile JSON under Application Support and a readable
  `~/.knowtype/LEXICAL_PROFILE.md` mirror.
- Filters protected text, technical-only tokens, paths, URLs, and numeric-only
  rows before terms can enter provider context.

## Tests

- `LexicalProfileStoreTests`
- `AIRecommendationRuntimeTests`
- `InputControllerCoordinatorTests`
