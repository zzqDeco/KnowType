# KnowType AI Accepted Feedback Learning

Status: Active

## Summary

KnowType records negative AI-learning signals only when a post-accept edit can
be verified against the AI text range it just inserted. Backspace alone is not a
negative signal; unknown or stale cursor ranges are ignored.

## Key Decisions

- AI acceptance creates an `acceptID` and a short-lived accepted-text span.
- The span activates only after the post-insert caret is verified at the
  expected end of the inserted AI text.
- Verified edits append to
  `~/Library/Application Support/KnowType/AI/accepted-ai-feedback.jsonl`.
- Feedback summary JSON and `~/.knowtype/ACCEPTED_AI_FEEDBACK.md` contain only
  bounded avoid/style signals.
- Provider requests may receive `AI_FEEDBACK.md` as a soft style signal; it
  never rewrites locked prefixes, blocks useful suggestions, touches Rime
  userdb, or changes native candidate ordering.

## Implementation Notes

- `AIAcceptedFeedbackTracker` lives in the input-method runtime and observes
  only the active accepted span.
- `AIAcceptedFeedbackStore` owns JSONL append, summary rebuild, markdown mirror,
  and request snapshot rendering.
- `scripts/accepted-learning.sh status/rebuild/clear --yes` also reports and
  maintains feedback files, while still preserving Rime, provider profiles,
  Keychain data, ENV, and CORRECTION.

## Acceptance

- Accept AI, immediately delete text inside the verified span, and feedback
  history/summary should grow.
- Accept AI, move the cursor elsewhere, delete text, and feedback history should
  not grow.
- Subsequent AI requests include only bounded `AI_FEEDBACK.md` and refresh cache
  when feedback summary hash changes.
