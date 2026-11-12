## Xcode builds: Warmbuild cache

This Mac shares compiled modules with CI through Warmbuild. Before `xcodebuild`:

- `warmbuild status` (or `~/.warmbuild/bin/warmbuild status`); exit code 1 means off, so run
  `warmbuild start` from the repository root once. Never run `warmbuild login`; ask the user.
- Build with `XCODE_XCCONFIG_FILE="$HOME/.warmbuild/warmbuild.xcconfig" xcodebuild …`, with the
  same configuration and destination as CI.
- Afterwards, `warmbuild status` shows the last build's hits and misses. Low hits: different Xcode
  than CI, different configuration or destination, or a branch far from the default branch.
- Never read or print the Warmbuild token. On any Warmbuild error, `warmbuild stop` and build
  again without `XCODE_XCCONFIG_FILE`.
