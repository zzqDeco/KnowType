# Sources/KnowTypeCore

`KnowTypeCore` contains the product invariants:

- shared request/response models
- text protection and Level 0 detection
- local correction examples and ranking
- prefix-locked continuation sanitization and fallback

Level 0 detection is pure core policy. It covers URLs, emails, file paths, command-like input, code-like tokens, and protected app bundle IDs for Terminal, iTerm2, and Xcode. Level 0 correction returns local identity protection and Level 0 continuation returns no candidates.

Provider-specific protocol details must not be added here.
