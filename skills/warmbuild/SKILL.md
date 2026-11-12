---
name: warmbuild
description: Reference for the warmbuild CLI on a Mac — the Warmbuild compilation cache for Xcode builds (xcodebuild, Xcode app) that CI fills, and test selection. Use when building or testing an Xcode project on a machine with Warmbuild installed, or when the user asks about Warmbuild, its cache hits and misses, or which tests a change reaches.
---

# Warmbuild CLI

Warmbuild serves Xcode's compilation cache from what CI compiled on the default branch. On a Mac
the CLI runs a local cache server and an xcconfig that points Xcode and xcodebuild at it. The cache
is optional: builds work the same without it.

## Install, sign in, turn on and off

| Command | What it does |
| --- | --- |
| `curl -fsSL https://warmbuild-dev.mikitahimpel.com/install.sh \| sh` | Installs `~/.warmbuild/bin/warmbuild` (macOS, Node 20+). Re-run to update. |
| `warmbuild login` | GitHub device flow; the user enters a code in a browser. Stores a read-only token in the macOS Keychain. Interactive: the user runs it. |
| `warmbuild start` | In a repository: starts the cache server (LaunchAgent), writes `~/.warmbuild/warmbuild.xcconfig`, maps this checkout the way CI does. |
| `warmbuild stop` | Stops the server and empties the xcconfig; builds then run without the cache. |
| `warmbuild link [dir]` | Makes the checkout at `dir` (default `.`) the mapped one: one checkout at a time, as on CI. Builds in other checkouts work but do not share CI's keys. Also points `/tmp/warmbuild/src` there, which `#filePath` and the debugger resolve to. |
| `warmbuild run -- xcodebuild …` | One build with its own short-lived server, without the LaunchAgent. |

`warmbuild` may not be on PATH; `~/.warmbuild/bin/warmbuild` is the same command.

## Building with the cache

xcodebuild reads the cache settings from `XCODE_XCCONFIG_FILE`:

```sh
XCODE_XCCONFIG_FILE="$HOME/.warmbuild/warmbuild.xcconfig" xcodebuild …
```

If `XCODE_XCCONFIG_FILE` is already exported, plain `xcodebuild …` uses it. Keys equal CI's only
for the same Xcode version, configuration, destination and architecture as the CI job that filled
the cache.

## Status: hits and misses

`warmbuild status` prints whether the cache is on, the account, the mapped checkouts and the last
build. Exit code 0 means on, 1 means off. `warmbuild status --json` prints:

| Field | |
| --- | --- |
| `running` | the server answers and the xcconfig points at it |
| `mode` | `read-only` or `read-write` |
| `account`, `tokenExpiresAt` | signed-in account, or `null` |
| `sourceRoot` | where `/tmp/warmbuild/src` points |
| `checkouts`, `unmappable` | the mapped checkout (zero or one); a linked checkout with a space in its path, which cannot be mapped |
| `lastBuild` | `hits`, `misses`, `hitRate` (0–1), `remoteHits` (from Warmbuild), `localHits` (this Mac), `mbDown`, `mbUp`, `httpFailures`, `startedAt`, `endedAt` (ms) |

The last build is the last burst of cache traffic, split at 20 s without lookups. A miss is a
compilation whose key is in neither this Mac's cache nor Warmbuild's. Keys differ when the Xcode
version, SDK, configuration, destination, build settings or sources differ from what CI built, and
for code CI has not built yet. `httpFailures` above 0 means Warmbuild could not be reached or
refused (not signed in, account not approved); the build then used only this Mac's cache.

## Test selection

`warmbuild tests --changed` prints `xcodebuild` arguments for the tests the working tree's diff
reaches: the diff against the merge base with origin's default branch, including uncommitted and
untracked files. A one-line reason goes to stderr.

```sh
xcodebuild test … $(warmbuild tests --changed)
```

- Empty output: every test runs. `-skip-testing` for every target: the diff reaches no test.
- `--format xcodebuild|swift|json|markdown`. `swift` prints a `swift test --filter` pattern (empty
  when everything runs, `^$` when nothing is reached):
  `p=$(warmbuild tests --changed --format swift); swift test ${p:+--filter "$p"}`.
- `--base <ref>`, `--depth 2`, `--max-files 40`, `--ignore <regex>`, `--always Target[/Suite]`
  (always run), `--no-hints` (skip recent default-branch failures, which come from Warmbuild).

## CI reports

Read-only views of the account's CI reports (names, durations, counts; no source or logs). The
repository defaults to the checkout's GitHub origin; `--repo owner/name` overrides it. All take
`--json`; shapes are in the Warmbuild docs (`docs/dev-cache.md`, "CI reports from the command line").

| Command | Output |
| --- | --- |
| `warmbuild builds [--branch <b>] [--limit <n>]` | recent CI jobs: id, ref, duration, cache hits/misses/rate, test results |
| `warmbuild report [--job <id>]` | one job (default newest): time per category, targets by compile time with cache hits and misses, slowest tasks and tests |
| `warmbuild findings` | the dashboard's findings with estimated time per job |
| `warmbuild why-miss <target> [--jobs <n>]` | a target's hits and misses across recent jobs, and which of Xcode, runner, ref, event and commit differ from the last job without misses; it cannot see inside cache keys |

A request that fails prints `warmbuild: <reason>` on stderr and exits 1 (not signed in, no
repository, unknown job).

## Rules

- Never read, print or log the token: not with `security`, not from `~/.config/warmbuild`, not
  from the environment. `warmbuild status` shows the account.
- `warmbuild login` and `--write` are the user's to run.
- When a Warmbuild command fails, or a build reports a compilation cache or remote service error,
  `warmbuild stop` turns the cache off and the build runs as a plain local build.
