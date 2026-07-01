# InputAIRecommendationSchedulePolicy

## Responsibility

`InputAIRecommendationSchedulePolicy` owns the pure decision for whether the
input-method coordinator should start a real-time AI recommendation request.

It evaluates raw-input stability, locked-prefix length, secret-like text,
runtime cloud-continuation preference, and recommendation-provider availability,
then returns either `schedule` or a skipped AI state plus diagnostic stage and
reason.

## Boundaries

- It does not construct `AIRecommendationRequest`.
- It does not start, cancel, or apply asynchronous AI tasks.
- It does not update the candidate panel.
- It does not read lexical profiles, accepted-feedback snapshots, provider
  profiles, or user data.

Those side effects remain in `InputAIRecommendationRuntime`, `KnowTypeAI`, and
the coordinator's candidate-panel state application boundary.

## Behavior Notes

- Partially resolved composition skips as `skipped_ineligible` with
  `no_stable_prefix`, preserving the rule that half-pinyin marked text is not
  sent as a locked prefix.
- Secret-like raw input or locked prefixes produce `AI 已禁用`.
- Disabled cloud continuation produces `AI 已关闭`.
- Missing provider state preserves the existing distinction between an absent
  recommendation runtime and an unavailable provider.

## Tests

- `InputAIRecommendationSchedulePolicyTests`
- `InputControllerCoordinatorTests`
- `swift test`
