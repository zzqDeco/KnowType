# KnowType Resources

This directory contains repository-level resources that are packaged into local
macOS development artifacts.

## Current Resources

- `InputMethod/Info.plist`: InputMethodKit bundle metadata used by
  `scripts/build-inputmethod-bundle.sh`.
- `InputMethod/KnowTypeInputMethodIcon.icns` and `.tiff`: local input-source
  icons.
- `InputMethod/en.lproj/InfoPlist.strings` and
  `InputMethod/zh-Hans.lproj/InfoPlist.strings`: localized input-source display
  metadata.
- `PreferencePane/Info.plist`: metadata for the user-installed
  `KnowType.prefPane` host.

The bundled clean-room seed lexicon is a SwiftPM target resource under
`Sources/KnowTypeCore/Resources/TraditionalLexicon/seed.tsv`, not this top-level
directory.

## Rules

- Do not commit third-party bulk dictionary data here.
- Input-method resources should remain small and auditable.
- When resource packaging changes, update the build scripts, acceptance docs,
  and source notes together.
