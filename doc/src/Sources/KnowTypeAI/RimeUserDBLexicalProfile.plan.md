# RimeUserDBLexicalProfile

## Responsibility

Maintains the AI lexical profile boundary between Rime's persisted user
frequency data and provider context documents.

## Boundaries

- Parses Rime sync text exports shaped as standard
  `code<TAB>text<TAB>c=... d=... t=...` rows and keeps compatibility with the
  older `text<TAB>code<TAB>frequency` fixture format used by tests.
- Metadata rows select the lexical text column by identifying ASCII Rime code
  columns, avoiding code strings in `LEXICAL_PROFILE.md` when row order differs.
- Does not read Rime `.ldb` files or retain complete userdb exports.
- Persists canonical profile JSON under Application Support and a readable
  `~/.knowtype/LEXICAL_PROFILE.md` mirror.
- Stages JSON/Markdown writes to temporary files first; conditional commits
  re-check freshness before, during, and after publish, and roll back any
  promoted files if a refresh becomes stale before the transaction completes.
- Carries the Rime schema id with the persisted profile; the input method merges
  persisted terms into AI requests only when it matches the active schema.
- Filters protected text, technical-only tokens, paths, URLs, and numeric-only
  rows before terms can enter provider context.

## Tests

- `LexicalProfileStoreTests`
- `AIRecommendationRuntimeTests`
- `InputControllerCoordinatorTests`
