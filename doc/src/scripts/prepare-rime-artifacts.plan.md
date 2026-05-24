# scripts/prepare-rime-artifacts.sh

## Responsibility

Downloads and verifies the pinned macOS universal `librime` artifacts for the
optional native Rime conversion bridge.

## Boundaries

- The script writes ignored artifacts under `Vendor/Rime` by default.
- It does not install Homebrew packages and does not commit downloaded binaries.
- It prepares runtime dylibs/plugins, OpenCC data, and a pinned shared-data
  recipe set.

## Behavior Notes

- The pinned default is `librime 1.16.1` at git hash `de4700e`.
- Both the core Rime archive and dependency archive are SHA256-checked before
  extraction.
- The default shared-data recipes are `rime/rime-prelude` and
  `rime/rime-pinyin-simp`; set `RIME_DATA_RECIPES=""` to skip recipe install.
- Default shared-data recipe repositories are fetched by exact commit through
  `RIME_DATA_RECIPE_REFS`, and the script fails if a configured recipe lacks a
  pin unless `RIME_ALLOW_UNPINNED_DATA_RECIPES=1` is explicitly set.
- The script writes a KnowType `default.custom.yaml` so the bundled schema list
  is limited to `RIME_DEFAULT_SCHEMA`, which defaults to `pinyin_simp`.
- Cached plum checkouts are fetched, force-checked out, reset, and cleaned to
  the pinned `RIME_PLUM_REF` only for explicit unpinned override installs.
- `scripts/build-inputmethod-bundle.sh` copies prepared artifacts into
  `KnowType.app` before signing when the vendor directory exists.

## Tests

- `scripts/prepare-rime-artifacts.sh --help`
- local fake-archive extraction smoke with `RIME_DATA_RECIPES=""` and
  `RIME_DEFAULT_SCHEMA=""`
- `git diff --check`
