# KnowType AI Secret-Only Privacy Gate

## Status

Active

## Summary

KnowType keeps the existing Level 0 correction-protection rules for local
correction, but real-time cloud AI recommendation now uses a narrower hard
block: only secret-like credentials in raw input or confirmed locked prefix
show `AI 已禁用`.

Technical tokens, code-like text, normal commands, paths, URLs, and app context
such as Terminal, iTerm, or Xcode do not directly disable AI recommendation.
Realtime continuation no longer sends unconfirmed candidate hints to providers.

## Branch

- `fix/ai-secret-only-privacy-gate`
- Base PR target: `dev`

## Scope

- Add `TextProtection.containsSecretLikeContent` and
  `detectSecretLikeRanges`.
- Change `AIRecommendationRuntime` to hard-block only secret-like raw input or
  locked prefix.
- Keep candidate hints out of realtime provider requests.
- Change provider-backed continuation paths to use the secret-only gate.
- Keep `requiresNoCorrection` unchanged for correction/local-protection paths.

## Validation

- Secret shapes include OpenAI/GitHub/AWS tokens, bearer headers, JWTs, PEM
  private keys, credential assignments, and sensitive URL query values.
- Normal technical text such as `ijust`, `InputMethodKit`, `iOS`, `JSON`,
  `git status`, `/Users/zq/project`, `example.com`, `snake_case`, and
  `camelCase` is not secret-like.
- `AI 已禁用` maps to `secret_like_text`.
