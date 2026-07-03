# KnowType Documentation

This directory keeps current project documentation. It should describe how the system works now, not preserve every historical planning detail.

## Start Here

- [Architecture](architecture.plan.md): package boundaries, input pipeline, provider runtime, privacy rules, and IMK front-end shape.
- [Interfaces](interfaces.plan.md): provider contracts, profile schema, candidate data, keyboard shortcuts, and Level 0 behavior.
- [MVP Acceptance](mvp-acceptance.plan.md): manual test matrix for local input method builds.
- [MVP Test Acceptance Matrix](mvp-test-acceptance-matrix.plan.md): what `swift test`, CI script smoke, provider live smoke, and manual local IME acceptance prove.
- [Local Input Method Testing](local-inputmethod-testing.plan.md): macOS 15 local Apple Development policy and selection diagnostics.
- [Debug Diagnostics](debug-diagnostics.plan.md): privacy-safe debug/performance logging switches and issue-specific recipes.
- [Source Notes](src/README.md): short file-level notes organized to mirror source and script directories.
- [Documentation Template](templates/documentation.template.md): template for new current-state docs under `doc/`.
- [Source Note Template](templates/source-note.template.md): template for source notes under `doc/src/`.

## Documentation Rules

- Keep product-facing setup and behavior in `README.md` and `README_CN.md`.
- Keep current engineering contracts in `doc/`.
- Keep active or recently delivered work plans in `plan/`.
- Use templates when adding new docs or source notes.
- Update the relevant index in the same change that adds, retires, or moves a document.
- Prefer concise current-state documentation over long historical narratives.
- When behavior changes, update the narrowest relevant document and link out instead of duplicating the same explanation everywhere.
- For documentation-only cleanup, run at least `git diff --check`.

## Related Project Files

- [AGENTS.md](../AGENTS.md): coding-agent rules, branch naming, review checklist.
- [CLAUDE.md](../CLAUDE.md): compatibility pointer for Claude-oriented agents.
- [plan/README.md](../plan/README.md): index of implementation plans.
