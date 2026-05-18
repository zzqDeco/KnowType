# KnowTypeLexiconTool

## Responsibility

`KnowTypeLexiconTool` builds the `knowtype-lexicon-tool` executable used to
install managed local lexicon packs.

## Boundaries

- Download, checksum verification, conversion, and metadata writing are owned by
  `ManagedLexiconPackInstaller` in `KnowTypeCore`.
- The shell wrapper `scripts/install-lexicon-pack.sh` should stay a thin command
  entry point.

## Behavior Notes

- The default command installs the recommended `rime-pinyin-simp` pack.
- `--directory` targets a custom local lexicon directory.
- `--force` replaces an existing pack output file.
- Third-party dictionary data is downloaded and converted locally; bulk
  dictionary contents are not committed to this repository.

## Tests

- `ManagedLexiconPackTests`
- `LexiconSettingsViewModelTests`
- `git diff --check` for command documentation updates
