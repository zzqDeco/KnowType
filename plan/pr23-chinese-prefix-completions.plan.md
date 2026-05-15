# PR 23 Chinese Prefix Completions Cleanup

Goal: close the still-useful Chinese input gaps from PR #23 on top of current `dev` without rebasing the stale branch.

Context:

- PR #23 predates the candidate anchor resolver, native candidate panel, and input-mode state work now merged into `dev`.
- Rebasing it would reintroduce conflicts across `InputController`, candidate geometry, README files, and the Chinese engine.
- The safe remaining value is a set of common compact-pinyin and initial-abbreviation cases that should be handled locally by `TraditionalInputEngine`.

Implementation:

- keep the current clean-room pinyin lattice and candidate paging architecture
- add seed lexicon entries for common abbreviated questions: `sm -> 什么`, `zmb -> 怎么办`
- add compact phrase coverage for `xiansh -> 显示`, `zhongguoren -> 中国人`, and `woxiangqukan -> 我想去看`
- keep these entries local and deterministic; do not use cloud correction to mask missing basic input-method behavior
- leave any large external dictionary import for a separate authorization and performance review

Validation:

- `swift test --filter TraditionalInputEngineTests`
- `swift test`
- `git diff --check`
