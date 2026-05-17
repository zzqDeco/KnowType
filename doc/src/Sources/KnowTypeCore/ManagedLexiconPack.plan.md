# ManagedLexiconPack

`ManagedLexiconPack.swift` owns license-aware local dictionary pack installation.

- `ManagedLexiconPack` describes a pinned source URL, SHA256, output filename, license, and source format.
- `RimeDictionaryConverter` converts Rime `.dict.yaml` rows into KnowType TSV without importing the source dictionary into the repository.
- `ManagedLexiconPackInstaller` downloads, verifies, converts, and atomically writes the TSV plus `*.metadata.json`.
- `InstalledLexiconPackMetadata` records source, version, checksum, license, entry count, output file, and install date for settings display.

The installer is explicit-user-action infrastructure. It should not silently download dictionaries during input-method startup.
