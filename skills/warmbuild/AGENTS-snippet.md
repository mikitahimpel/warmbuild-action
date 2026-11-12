## Warmbuild (Xcode compilation cache and test selection)

This Mac may have the `warmbuild` CLI (`~/.warmbuild/bin/warmbuild`). It serves Xcode's compilation
cache from what CI built.

- `warmbuild status` (`--json`): on or off (exit code 0 or 1), account, last build's hits, misses,
  hit rate and MB, and each worktree's last build. `warmbuild start` in the repository turns the
  cache on for all its worktrees; `warmbuild stop` turns it off, and builds then run without it.
- Building with it: `XCODE_XCCONFIG_FILE="$HOME/.warmbuild/warmbuild.xcconfig" xcodebuild …`. Keep
  `-derivedDataPath` out of `/tmp` (e.g. `~/Library/Caches/<name>/dd`): there it loses hits.
- `xcodebuild test … $(warmbuild tests --changed)`: only the tests the diff against the default
  branch reaches (empty output: all tests).
- CI report data, read-only, `--json` on each: `warmbuild builds`, `warmbuild report [--job <id>]`,
  `warmbuild findings`, `warmbuild why-miss <target>`, `warmbuild tests --slow|--flaky|--failing`.
- `warmbuild login` is interactive and the user's to run. Never read or print the Warmbuild token.
- If a Warmbuild command or the cache fails, `warmbuild stop` and build without it.
