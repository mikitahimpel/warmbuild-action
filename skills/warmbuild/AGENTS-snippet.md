## Warmbuild (Xcode compilation cache and test selection)

This Mac may have the `warmbuild` CLI (`~/.warmbuild/bin/warmbuild`). It serves Xcode's compilation
cache from what CI built.

- `warmbuild status` (`--json`): on or off (exit code 0 or 1), account, last build's hits, misses,
  hit rate and MB. `warmbuild start` in the repository turns the cache on; `warmbuild stop` turns
  it off, and builds then run without it.
- Building with it: `XCODE_XCCONFIG_FILE="$HOME/.warmbuild/warmbuild.xcconfig" xcodebuild …`.
- `xcodebuild test … $(warmbuild tests --changed)`: only the tests the diff against the default
  branch reaches (empty output: all tests).
- `warmbuild login` is interactive and the user's to run. Never read or print the Warmbuild token.
- If a Warmbuild command or the cache fails, `warmbuild stop` and build without it.
