# CLAUDE.md

Follow [AGENTS.md](AGENTS.md) as the authoritative repository guide.

Project-specific reminders:

- Do not turn continuation candidates into full-sentence rewrites.
- Keep provider-specific code inside `KnowTypeProviders`.
- Keep IMK host integration and candidate-window behavior inside `KnowTypeInputMethod`.
- Keep user-visible Chinese product docs in `README_CN.md`.
- Keep code comments and identifiers in English unless existing source context requires otherwise.
- Use the templates under `doc/templates/` and `plan/templates/` for new documentation.
- Keep stable current behavior in `doc/`; keep implementation sequencing and branch-local decisions in `plan/`.
- Update `doc/README.md`, `doc/src/README.md`, or `plan/README.md` when adding, absorbing, or retiring docs.
- Keep `README.md` and `README_CN.md` as GitHub project entry pages, not design-history documents.
- Run `swift test` after code changes; for docs-only changes, run `git diff --check`.
