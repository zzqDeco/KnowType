# InputMethodRuntimePreferences

`InputMethodRuntimePreferences` is the shared preference model for runtime behavior that must be visible in settings and consumed by the input method.

It persists through the same `com.knowtype.preferences` defaults domain as punctuation preferences. The stored values cover input scheme, candidate page size, candidate layout mode, cloud continuation enablement, local fallback continuation enablement, continuation length, and maximum continuation candidates.

The input method reads these preferences at startup and at new composition boundaries. It does not reload them on every key event and does not mutate an active marked-text composition when a setting changes.
