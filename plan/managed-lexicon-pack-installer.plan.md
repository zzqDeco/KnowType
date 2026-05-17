# Managed Lexicon Pack Installer

## Summary

This slice upgrades local lexicon loading from "drop a JSON/TSV file into a directory" to a managed, license-aware lexicon pack flow.

KnowType still does not vendor third-party bulk dictionaries into the repository. Instead, it can install the recommended Rime Pinyin Simplified dictionary from a pinned source URL, verify the source SHA256, convert Rime `.dict.yaml` rows into KnowType TSV, and write both the TSV and metadata into the user's local lexicon directory.

## Scope

- Add `ManagedLexiconPack`, `InstalledLexiconPackMetadata`, `RimeDictionaryConverter`, and `ManagedLexiconPackInstaller` in `KnowTypeCore`.
- Add the recommended `rime-pinyin-simp` pack, pinned to Rime commit `0c6861ef7420ee780270ca6d993d18d4101049d0` with SHA256 verification.
- Add `knowtype-lexicon-tool` and `scripts/install-lexicon-pack.sh` for command-line installation.
- Add a settings action for installing the recommended pack and displaying installed pack metadata.
- Skip `*.metadata.json` during lexicon resource scans so metadata is not parsed as dictionary data.
- Keep non-recommended dictionary sources out of this slice.

## Tests

- Rime conversion skips headers/comments and turns rows into valid KnowType TSV.
- Converted entries feed `TraditionalInputEngine` for `nishishei`, `weishenme`, and `xianzai`.
- Installer rejects checksum mismatches, refuses overwrites by default, and supports force replacement.
- Runtime and settings scans skip managed-pack metadata JSON.
- Settings reports installed pack metadata and keeps current status when installation fails.
