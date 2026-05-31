# Accepted Learning Lexical Profile Refresh

Status: Active

## Summary

Accepted AI learning writes full local history and a bounded summary
asynchronously. The persistent lexical profile refresh must merge that summary
after it becomes ready so `LEXICAL_PROFILE.md` and `lexical-profile.json` match
request-time lexical context.

## Implementation

- `AIAcceptedLearningStore` publishes summary-ready metadata after a summary
  rebuild is persisted.
- Summary-ready metadata is scoped to schemas whose accepted history changed
  since the previous rebuild.
- `LexicalProfileRuntime` subscribes to summary-ready events and schedules a
  second background refresh for the latest matching schema.
- Summary-ready observation is centralized per accepted-learning store, and only
  the runtime that most recently scheduled a refresh handles the event.
- Refresh task cancellation and generation assignment are serialized to avoid
  dropping the summary-triggered refresh during concurrent commit/summary paths.
- Refresh cancellation clears the latest summary-ready context and unregisters
  the runtime, so a closed controller cannot be reactivated by a delayed summary.
- Lexical context merging treats accepted-AI summary as canonical for accepted
  text and filters duplicate current recent commits before rendering the profile.
- Persistent lexical profile writes merge accepted-AI terms, bounded recent
  accepted commits, and accepted summary source lines.

## Boundaries

- Accepted history remains local-only and is never injected in full.
- Summary-ready events carry only schema id, counts, and history hash.
- Rime userdb is read through the existing snapshot provider only; this path
  does not write Rime userdb or call `sync_user_data`.
