# Warmbuild Action

A remote compilation cache for Xcode 26+ builds on GitHub Actions. Add one step before
`xcodebuild`; the build command itself stays the same.

```yaml
permissions:
  id-token: write   # the Action signs in with GitHub's OIDC token
  contents: read
jobs:
  build:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v5
      - uses: mikitahimpel/warmbuild-action@v1
      - run: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator'
```

The Action starts a small cache server and exports `XCODE_XCCONFIG_FILE`, so every later
`xcodebuild` in the job uses it. If anything goes wrong, the build runs without the cache. Hits,
misses and bytes appear in the job summary.

After the job, the post step also reports where the job's minutes went: it reads the build logs and
result bundles Xcode wrote during the job (`Logs/Build/*.xcactivitylog`, `*.xcresult`) and the asset
catalogs in the checkout, writes a summary with findings to the job summary, and uploads it to the
dashboard. The report holds task and target names, file names without their directories, test
names, durations, counts and sizes; for type-checking, the source file's path within the checkout,
its line and the declaration the compiler named (`getter for property 'body'`). It never holds
source code, command lines, log output or environment variables (apart from the runner image's name
and version, and the Xcode and Simulator runtime versions). Set `report: false` to turn it off. `xcodebuild test` always leaves what the
report needs; a build-only step (`xcodebuild build`) keeps its log only in a result bundle, so pass
it `-resultBundlePath "$RUNNER_TEMP/build.xcresult"` to have it counted.

When a job runs on a new Xcode, runner image or Simulator runtime, its summary says so and what it means for the
caches. A new Xcode changes every compilation cache key, so that run fills the cache again and is
slow. A new image with the same Xcode keeps compiled results. A new runtime makes cached test
results run again. The dashboard marks the job on its trend with the hit rate before and after.

The summary also counts compile tasks that could not use the cache (for example,
`SWIFT_ENABLE_EXPLICIT_MODULES = NO`, which React Native below 0.87 sets on every pod target), with
the target, the setting or flag and the fix. The dashboard shows the share per job. When fetching
remote Swift packages takes 20 s or more, it suggests caching `SourcePackages` with `actions/cache`.

Reading result bundles may take `report-budget` seconds (90) in total; what does not fit is skipped
and named in the summary. A Simulator that is still running keeps the runner's CPUs busy and makes
`xcresulttool` slow to start, so shut it down at the end of the test step:

```yaml
      - run: |
          xcodebuild test -scheme App -destination 'platform=iOS Simulator,name=iPhone 17'
          xcrun simctl shutdown all
```

## Test selection on pull requests

With `select-tests: true`, a pull request runs only the tests its change can reach; pushes run
everything, so the default branch catches anything selection skipped. Pass the arguments to
`xcodebuild test` (or `swift test --filter` for a package):

```yaml
      - uses: mikitahimpel/warmbuild-action@v1
        id: warmbuild
        with:
          select-tests: true
      - if: steps.warmbuild.outputs.tests != 'none'
        run: xcodebuild test -scheme App -destination 'platform=iOS Simulator,name=iPhone 17' $WARMBUILD_ONLY_TESTING
```

The Action compares the pull request with its base branch and reads the Swift files below each
project and package (`*.xcodeproj`, `project.yml`, `Package.swift`) for the types they declare and
name. A test file runs when it changed, or when it names a type from a changed file, or a type
whose file names one (two references). UI tests (files using `XCUIApplication`) run on any app
change. Also selected: suites that failed or flaked on the default branch lately, and a 5% sample
of the rest. Everything runs when a project or package manifest, `Package.resolved`, an
`.xcconfig`, a scheme, test plan, entitlements, `Info.plist` or a workflow that runs tests
changes, when more than 40 files change, or when a resource outside a test directory changes. An
XcodeGen `project.yml` change confined to target blocks runs only the tests of the changed targets
and of the targets that depend on them; a change anywhere else in it (settings, schemes, packages,
options, includes) runs everything. `only-testing` names only test targets of the Xcode project
(with `select-tests-scheme`, of that scheme, from `project.yml` or the shared `.xcscheme` and its
test plans): `xcodebuild` refuses a whole run that names a target its scheme does not hold.
Selected tests of Swift package test targets are in `swift-filter` only. When a selected test
target is neither the project's nor a package's, or the project cannot be read, `xcodebuild` runs
everything. The
job summary lists what ran and why, and the dashboard shows tests run, minutes saved and misses
(default-branch failures in a test a merged pull request skipped). Test targets are named after
their directory (`…Tests`).

| Selection input | Default | |
| --- | --- | --- |
| `select-tests` | `false` | `true` selects tests on pull requests |
| `select-tests-ignore` | none | Paths that never affect tests, one regular expression per line |
| `select-tests-always` | none | Targets or `Target/Suite` ids to run on every pull request |
| `select-tests-sample` | `0.05` | Share of the other test files to run anyway |
| `select-tests-scheme` | none | The scheme `xcodebuild test` runs; `only-testing` names only its test targets (default: every test target of the project) |

| Selection output | |
| --- | --- |
| `tests` | `all`, `some` or `none` |
| `only-testing` | `-only-testing:Target/Suite …` for xcodebuild (empty when everything runs), also `$WARMBUILD_ONLY_TESTING` |
| `swift-filter` | the same as a `swift test --filter` pattern |

On a Mac, `warmbuild tests --changed` prints the same arguments for the working tree:
`xcodebuild test … $(warmbuild tests --changed)`.

## Test-result cache

A test target whose built products (the test bundle, its host app and every product it loads), the
destination, Xcode and its test settings are the same as in an earlier passing run is not run
again; the job summary says which run it reused. Add the `test-cache` step between
`build-for-testing` and `test-without-building`:

```yaml
      - run: xcodebuild build-for-testing -scheme App -destination "id=$UDID" -derivedDataPath "$RUNNER_TEMP/dd"
      - uses: mikitahimpel/warmbuild-action/test-cache@v1
        id: tests
        with:
          derived-data: ${{ runner.temp }}/dd
          destination: id=${{ env.UDID }}
      - if: steps.tests.outputs.tests != 'none'
        run: xcodebuild test-without-building -scheme App -destination "id=$UDID" -derivedDataPath "$RUNNER_TEMP/dd" $WARMBUILD_ONLY_TESTING
```

`WARMBUILD_ONLY_TESTING` then holds test selection's arguments, the step's `args` and a
`-skip-testing` per reused target; `tests` is `none` when every target was reused, so the
Simulator need not boot. Only passes are stored: a target that ran whole with no failed or flaky
test. Results from the default branch count for every job, a pull request's only for its own later
runs. `cache-tests: false` or `[warmbuild full tests]` in the commit message (or a pull request's
title or body) runs everything; passes are still recorded.

| Test cache input | Default | |
| --- | --- | --- |
| `derived-data` | none | The `-derivedDataPath` of build-for-testing |
| `xctestrun` | newest | The `.xctestrun`, when there are several |
| `destination` | required | The `-destination` the tests run on (its runtime and device type are part of each key) |
| `args` | none | The workflow's own `-only-testing` / `-skip-testing` arguments |
| `cache-tests` | `true` | `false` runs every target |
| `extra-key` | none | Anything else that changes results, made part of every key |
| `workspace` | the workspace | The checkout, when elsewhere |

## On a developer's Mac

The same cache for local Xcode builds, read-only: what CI compiled on the default branch.

```sh
curl -fsSL https://warmbuild-dev.mikitahimpel.com/install.sh | sh   # or: sh install.sh from this repository
~/.warmbuild/bin/warmbuild login       # GitHub device code, token in the Keychain
cd your-app && ~/.warmbuild/bin/warmbuild start   # LaunchAgent + ~/.warmbuild/warmbuild.xcconfig
export XCODE_XCCONFIG_FILE="$HOME/.warmbuild/warmbuild.xcconfig"   # for xcodebuild; restart Xcode once
~/.warmbuild/bin/warmbuild status                      # hits, misses and MB of the last build
```

### Slow type-checking

When the compiler gives up on an expression ("unable to type-check this expression in reasonable
time"), the job summary names the file and line and GitHub marks it on the pull request.

On pull requests the Action also times type-checking with the compiler's own timers
(`-warn-long-function-bodies` and `-warn-long-expression-type-checking`, from 100 ms), and the
summary lists the slowest functions, what the pull request added against the base branch ("this
pull request added about 1.4 s of type-checking, the most in `ListScreen.swift:97`"), and a warning
on changed code that takes over a second. You change nothing in your project for this. What it costs:

- The timers are part of the compilation cache key, so they go only to the targets whose Swift files
  the pull request changes, and those targets compile without the cache in that job. A target with
  more than 60 unchanged Swift files is left out (`typecheck-max-files`); the summary names it.
- The default branch never gets them, so the cache it fills is the same as without this.
- The timings are compiler warnings, so a target that treats warnings as errors
  (`SWIFT_TREAT_WARNINGS_AS_ERRORS`, `-warnings-as-errors`) is left out.
- The timers themselves cost no measurable compile time (within run-to-run noise on 7,400 lines).

Set `typecheck: false` to turn timing off.

For AI coding agents, `skills/warmbuild/SKILL.md` is a skill (copy it to `~/.claude/skills/warmbuild/`
or a repository's `.claude/skills/warmbuild/`), and `skills/warmbuild/AGENTS-snippet.md` is the same
for an `AGENTS.md`.

Your GitHub account or organisation needs the Warmbuild GitHub App and an approved account. Sign in
and set it up at the [Warmbuild dashboard](https://warmbuild-dev.mikitahimpel.com) (early access).

| Input | Default | |
| --- | --- | --- |
| `url` | the Warmbuild cache API | Cache API URL |
| `token` | none | A Warmbuild API token, for runners without GitHub OIDC |
| `workspace` | `$GITHUB_WORKSPACE` | The checkout directory, when `actions/checkout` uses `path:` |
| `report` | `true` | `false` skips the CI report (summary and upload) |
| `report-budget` | `90` | Seconds the post step may spend reading result bundles; the rest is skipped and named |
| `typecheck` | `true` | `false` turns off type-check timing on pull requests (failures are reported either way) |
| `typecheck-threshold` | `100` | Milliseconds from which a function or expression is timed |
| `typecheck-warn` | `1000` | Milliseconds from which changed code counts as slow (a warning on the pull request) |
| `typecheck-max-files` | `60` | Leave out a changed target with more unchanged Swift files than this |

| Output | |
| --- | --- |
| `enabled` | `true` when the cache is in use |
| `xcconfig` | path of the generated xcconfig |
| `stats` | path of a JSON file with the cache counters |

This repository holds released builds only. MIT licensed; the bundled client in
`action/client/warmbuild.mjs` includes third-party packages under their own licenses (MIT,
Apache-2.0, BSD-3-Clause), whose notices are kept at the end of that file.
