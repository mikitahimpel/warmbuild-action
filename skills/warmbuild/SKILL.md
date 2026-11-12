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
| `curl -fsSL https://warmbuild-dev.mikitahimpel.com/install.sh \| sh` | Installs `~/.warmbuild/bin/warmbuild` (macOS, Node 20+), and in a repository also starts the cache. Without a terminal it does not sign in or edit the shell profile; it prints those steps. The daemon updates itself daily; `warmbuild update` does it now. |
| `warmbuild login` | GitHub device flow; the user enters a code in a browser. Stores a read-only token in the macOS Keychain. Interactive: the user runs it. |
| `warmbuild start` | In a repository: starts the cache server (LaunchAgent), writes `~/.warmbuild/warmbuild.xcconfig`, and maps every worktree of the repository the way CI maps its checkout, so builds in any worktree (also several at once) share CI's keys. Once per repository. |
| `warmbuild stop` | Stops the server and empties the xcconfig; builds then run without the cache. |
| `warmbuild link [dir]` | Links the repository at `dir` (default `.`) too, and points `/tmp/warmbuild/src` at this checkout. `#filePath` and the debugger resolve through that link; the daemon also moves it to the checkout of each `xcodebuild` it sees start. |
| `warmbuild run -- xcodebuild …` | One build with its own short-lived server, without the LaunchAgent. |

`warmbuild` may not be on PATH; `~/.warmbuild/bin/warmbuild` is the same command.

## Building with the cache

If the project's xcconfig has `#include? "warmbuild.local.xcconfig"` (`warmbuild start` offers to
add it), plain `xcodebuild …` uses the cache. Otherwise xcodebuild reads the settings from
`XCODE_XCCONFIG_FILE`:

```sh
XCODE_XCCONFIG_FILE="$HOME/.warmbuild/warmbuild.xcconfig" xcodebuild …
```

Passing it is harmless when the project includes it too. When a build hits little,
`warmbuild status` names the likely cause and `warmbuild doctor` lists every check with its fix. Keys equal CI's only
for the same Xcode version, configuration, destination and architecture as the CI job that filled
the cache. A `-derivedDataPath` or worktree below `/tmp` (or `/private/tmp`) loses hits: use
Xcode's default DerivedData or a folder in the home directory (e.g. `~/Library/Caches/<name>/dd`). `#filePath` is `/tmp/warmbuild/src/…` in every
worktree; tests that find files through it read the checkout that link points at.

## Status: hits and misses

`warmbuild status` prints whether the cache is on, the account, the linked repositories and their
projects, the last build of all worktrees together and each worktree's own last build. Exit code 0 means on, 1 means off. `warmbuild status --json` prints:

| Field | |
| --- | --- |
| `running` | the server answers and the xcconfig points at it |
| `mode` | `read-only` or `read-write` |
| `account`, `tokenExpiresAt` | signed-in account, or `null` |
| `sourceRoot` | where `/tmp/warmbuild/src` points |
| `checkouts`, `unmappable` | every mapped worktree; worktrees with a space in their path, which cannot be mapped |
| `repositories`, `projects`, `conflicts` | linked repositories (git directories); project name → directory below the checkout root; names at two places in as many worktrees each, not mapped |
| `worktrees` | each worktree: `path`, `counted` (has its own socket, so its builds are counted apart), `lastBuild` (`hits`, `misses`, `hitRate`, `startedAt`, `endedAt`) or `null` |
| `lastBuild` | all worktrees together: `hits`, `misses`, `hitRate` (0–1), `remoteHits` (from Warmbuild), `localHits` (this Mac), `mbDown`, `mbUp`, `httpFailures`, `startedAt`, `endedAt` (ms) |

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
| `warmbuild tests --slow\|--flaky\|--failing [--limit <n>]` | the slowest tests, tests that passed only on a retry, or tests that failed every run, over recent CI jobs |
| `warmbuild why-miss <target> [--jobs <n>]` | a target's hits and misses across recent jobs, and which of Xcode, runner, ref, event and commit differ from the last job without misses; it cannot see inside cache keys |

No shell? Use the MCP server: the same CI report data, read-only, as the tools `list_repositories`,
`latest_ci_report`, `why_cache_miss`, `tests`, `pr_test_selection` and `build_insights` at
`https://warmbuild-mcp-dev.mikitahimpel.com/mcp` (remote, Streamable HTTP, GitHub sign-in; the user
adds it to the client).

A request that fails prints `warmbuild: <reason>` on stderr and exits 1 (not signed in, no
repository, unknown job).

## Rules

- Never read, print or log the token: not with `security`, not from `~/.config/warmbuild`, not
  from the environment. `warmbuild status` shows the account.
- `warmbuild login` and `--write` are the user's to run.
- When a Warmbuild command fails, or a build reports a compilation cache or remote service error,
  `warmbuild stop` turns the cache off and the build runs as a plain local build.
