# Accepted Learning Controls

Status: Active

## Summary

Accepted AI learning now has a local control surface. Users and diagnostics can
inspect whether history, summary, mirror, and lexical-profile injection are
current, rebuild the bounded summary from local history, or clear accepted
learning data explicitly.

## Delivered Shape

- `scripts/accepted-learning.sh` wraps `knowtype-accepted-learning-tool`.
- `status [--json]` is read-only and reports counts, hashes, mtimes, summary
  freshness, and whether `LEXICAL_PROFILE.md` contains accepted-AI summary.
- `rebuild [--json]` rebuilds `accepted-ai-summary.json` and
  `ACCEPTED_AI_LEARNING.md` from full local history.
- `clear --yes [--json]` deletes accepted-learning history, summary, and mirror
  files, writes a clear marker for running stores, and scrubs accepted-AI
  lexical-profile terms/source lines plus matching accepted recent commits
  without deleting Rime, provider, Keychain, ENV, CORRECTION, or non-AI lexical
  recent/tone data.
- Runtime startup repair and maintenance writes share an interprocess lock file
  so rebuild, clear, startup repair, and accepted-record appends do not publish
  stale summaries.
- Runtime snapshot reads observe clear markers before returning accepted-AI
  summaries, so active input-method processes stop injecting cleared learning.
- Diagnostics and Settings display accepted-learning status without showing raw
  input or accepted text.

## Validation

- `swift test --quiet --filter AIAcceptedLearning`
- `swift test --quiet --filter InstallationDiagnosticsStatusTests`
- `bash -n scripts/accepted-learning.sh scripts/diagnose-inputmethod.sh`
- `git diff --check`
