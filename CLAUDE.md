# CLAUDE.md

Follow [AGENTS.md](AGENTS.md) as the authoritative repository guide.

Project-specific reminders:

- Do not turn continuation candidates into full-sentence rewrites.
- Keep provider-specific code inside `KnowTypeProviders`.
- Keep IMK host integration and candidate-window behavior inside `KnowTypeInputMethod`.
- Keep user-visible Chinese product docs in `README_CN.md`.
- Keep code comments and identifiers in English unless existing source context requires otherwise.
- Run `swift test` after code changes; for docs-only changes, run `git diff --check`.
