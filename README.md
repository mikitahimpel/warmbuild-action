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

Your GitHub account or organisation needs the Warmbuild GitHub App and an approved account. Sign in
and set it up at the [Warmbuild dashboard](https://warmbuild-dev.mikitahimpel.com) (early access).

| Input | Default | |
| --- | --- | --- |
| `url` | the Warmbuild cache API | Cache API URL |
| `token` | none | A Warmbuild API token, for runners without GitHub OIDC |
| `workspace` | `$GITHUB_WORKSPACE` | The checkout directory, when `actions/checkout` uses `path:` |

| Output | |
| --- | --- |
| `enabled` | `true` when the cache is in use |
| `xcconfig` | path of the generated xcconfig |
| `stats` | path of a JSON file with the cache counters |

This repository holds released builds only. MIT licensed; the bundled client in
`action/client/warmbuild.mjs` includes third-party packages under their own licenses (MIT,
Apache-2.0, BSD-3-Clause), whose notices are kept at the end of that file.
