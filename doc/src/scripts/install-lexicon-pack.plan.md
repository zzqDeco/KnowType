# install-lexicon-pack.sh

`scripts/install-lexicon-pack.sh` is the user-facing wrapper for managed lexicon pack installation.

- It defaults to `rime-pinyin-simp`.
- It delegates parsing, checksum verification, conversion, and atomic writes to `knowtype-lexicon-tool`.
- It supports `--directory` for smoke tests or custom local directories.
- It supports `--force` when an existing managed pack output should be replaced.

This script performs a real network download. CI should validate shell syntax and help output, while fixture-based Swift tests validate conversion and installer behavior without network dependency.
