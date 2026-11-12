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
names, durations, counts and sizes. It never holds source code, command lines, log output or
environment variables. Set `report: false` to turn it off. `xcodebuild test` always leaves what the
report needs; a build-only step (`xcodebuild build`) keeps its log only in a result bundle, so pass
it `-resultBundlePath "$RUNNER_TEMP/build.xcresult"` to have it counted.

## On a developer's Mac

The same cache for local Xcode builds, read-only: what CI compiled on the default branch.

```sh
cd your-app
npx -y github:mikitahimpel/warmbuild-action#v1 login   # GitHub device code, token in the Keychain
npx -y github:mikitahimpel/warmbuild-action#v1 start   # LaunchAgent + ~/.warmbuild/warmbuild.xcconfig
export XCODE_XCCONFIG_FILE="$HOME/.warmbuild/warmbuild.xcconfig"   # for xcodebuild; restart Xcode once
~/.warmbuild/bin/warmbuild status                      # hits, misses and MB of the last build
```

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

| Output | |
| --- | --- |
| `enabled` | `true` when the cache is in use |
| `xcconfig` | path of the generated xcconfig |
| `stats` | path of a JSON file with the cache counters |

This repository holds released builds only. MIT licensed; the bundled client in
`action/client/warmbuild.mjs` includes third-party packages under their own licenses (MIT,
Apache-2.0, BSD-3-Clause), whose notices are kept at the end of that file.
