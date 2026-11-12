---
name: warmbuild
description: Use before building or testing an Xcode project (xcodebuild build/test, Swift packages in an Xcode workspace) on a Mac where Warmbuild is set up, or when asked about Warmbuild cache hits, misses or slow local builds. Makes local builds read compiled modules from the Warmbuild cache that CI fills.
---

# Warmbuild: build Xcode projects from the shared cache

Warmbuild serves Xcode's compilation cache from what CI compiled on the default branch. The cache
is optional: a build must never fail or wait because of it.

## Before building

1. Run `warmbuild status` (or `~/.warmbuild/bin/warmbuild status` when `warmbuild` is not on PATH).
   - Exit code 0: the cache is on. Go on.
   - Exit code 1 (off): run `warmbuild start` from the repository root, once. If it fails, skip
     Warmbuild and build normally.
   - `Account: not signed in`: tell the user to run `warmbuild login` themselves (it opens a GitHub
     device code). Never run it for them, and build anyway: the local cache still works.
2. In a worktree other than the one in `Source root:`, run `warmbuild link` from its root. Builds
   still hit without it; it only makes `#filePath` and the debugger point at this worktree.

## Building

- Build with the xcconfig: `XCODE_XCCONFIG_FILE="$HOME/.warmbuild/warmbuild.xcconfig" xcodebuild …`
  (skip the prefix when `XCODE_XCCONFIG_FILE` is already exported). Do not add the cache settings
  to the project or pass them on the command line.
- Use the same `-configuration` and `-destination` as the CI workflow that fills the cache (look in
  `.github/workflows`). Another configuration, platform or architecture compiles other keys.
- Running only affected tests, once `warmbuild tests` exists (`warmbuild --help` lists it):
  `xcodebuild test … $(warmbuild tests --changed)`. If the command is missing or fails, run the
  tests you would have run anyway.

## After building

Run `warmbuild status` and read the `Last build` line: hits, misses, hit rate, MB downloaded.
A clean build of code that is on the default branch should hit above 90%. If it is much lower:

1. Same Xcode? CI's `xcodebuild -version` must equal yours (`xcodebuild -version`); another Xcode
   or SDK compiles other keys.
2. Same configuration and destination as CI? See above.
3. The branch changed many files, or CI has not built the default branch since: expected misses.
4. `Mapped checkouts` must list this checkout. If not, run `warmbuild link` here. A path with a
   space cannot be mapped; say so to the user.
5. Otherwise report the numbers to the user. Do not edit build settings to chase hits.

## Rules

- Never read, print or log the token: no `security find-generic-password`, no reading
  `~/.config/warmbuild`, no echoing environment variables. `warmbuild status` shows the account.
- On any Warmbuild error (status fails, start fails, the build reports a compilation cache or
  remote service error), run `warmbuild stop` and build again without `XCODE_XCCONFIG_FILE`.
  Mention it to the user; do not try to repair Warmbuild.
- Do not pass `--write` to `warmbuild start` or `warmbuild login`: laptops read, CI writes.
