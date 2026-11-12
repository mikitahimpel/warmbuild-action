#!/bin/sh
# Installs the Warmbuild CLI for local Xcode builds:
#   curl -fsSL https://warmbuild-dev.mikitahimpel.com/install.sh | sh
# Downloads warmbuild.mjs from a pinned release of mikitahimpel/warmbuild-action (or, while that
# release is not published yet, the latest one), checks it against the SHA-256 published beside it,
# and installs it to ~/.warmbuild/bin. No sudo. Run it again to
# update. Your shell profile is left alone unless you pass --add-to-path:
#   curl -fsSL https://warmbuild-dev.mikitahimpel.com/install.sh | sh -s -- --add-to-path
set -eu

version="1.8.0"
repo="mikitahimpel/warmbuild-action"
base="${WARMBUILD_DOWNLOAD_URL:-https://github.com/$repo/releases/download/v$version}"
latest="${WARMBUILD_LATEST_URL:-https://github.com/$repo/releases/latest/download}"
home="${WARMBUILD_HOME:-$HOME/.warmbuild}"
bin="$home/bin"

fail() {
  printf 'warmbuild install: %s\n' "$1" >&2
  exit 1
}

add_to_path=0
for arg in "$@"; do
  case "$arg" in
    --add-to-path) add_to_path=1 ;;
    *) fail "unknown option $arg (only --add-to-path)" ;;
  esac
done

if [ "$(uname -s)" != "Darwin" ] && [ "${WARMBUILD_ANY_OS:-}" != "1" ]; then
  fail "Warmbuild's local cache is for macOS with Xcode 26 or newer; this is $(uname -s)."
fi

if ! command -v node > /dev/null 2>&1; then
  fail "Node.js 20 or newer is required and was not found. Install it (https://nodejs.org, or: brew install node) and run this again."
fi
node_major="$(node -p 'process.versions.node.split(".")[0]' 2> /dev/null || echo 0)"
if [ "$node_major" -lt 20 ] 2> /dev/null; then
  fail "Node.js 20 or newer is required; found $(node --version). Update it (https://nodejs.org, or: brew upgrade node) and run this again."
fi
# The real path, so a version manager's per-shell shim does not end up in the wrapper.
node_path="$(node -p 'require("fs").realpathSync(process.execPath)')"

command -v curl > /dev/null 2>&1 || fail "curl is required."
if command -v shasum > /dev/null 2>&1; then
  sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
elif command -v sha256sum > /dev/null 2>&1; then
  sha256() { sha256sum "$1" | awk '{print $1}'; }
else
  fail "shasum or sha256sum is required to check the download."
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM

printf 'Downloading warmbuild %s…\n' "$version"
# The bundle and its checksum always come from the same release.
if ! curl -fsSL --retry 3 -o "$tmp/warmbuild.mjs.sha256" "$base/warmbuild.mjs.sha256"; then
  printf 'warmbuild %s is not published yet; installing the latest release\n' "$version"
  base="$latest"
  version="(latest release)"
  curl -fsSL --retry 3 -o "$tmp/warmbuild.mjs.sha256" "$base/warmbuild.mjs.sha256" || fail "could not download $base/warmbuild.mjs.sha256"
fi
curl -fsSL --retry 3 -o "$tmp/warmbuild.mjs" "$base/warmbuild.mjs" || fail "could not download $base/warmbuild.mjs"
expected="$(awk '{print $1}' "$tmp/warmbuild.mjs.sha256")"
actual="$(sha256 "$tmp/warmbuild.mjs")"
case "$expected" in
  *[!0-9a-f]* | "") fail "the published checksum is not a SHA-256" ;;
esac
[ ${#expected} -eq 64 ] || fail "the published checksum is not a SHA-256"
[ "$expected" = "$actual" ] || fail "checksum mismatch for warmbuild.mjs (expected $expected, got $actual); nothing was installed"

mkdir -p "$bin"
# Replace atomically: a running server keeps its open file until `warmbuild start` restarts it.
cp "$tmp/warmbuild.mjs" "$bin/warmbuild.mjs.new"
mv -f "$bin/warmbuild.mjs.new" "$bin/warmbuild.mjs"
printf '#!/bin/sh\nexec "%s" "%s" "$@"\n' "$node_path" "$bin/warmbuild.mjs" > "$bin/warmbuild.new"
chmod 755 "$bin/warmbuild.new"
mv -f "$bin/warmbuild.new" "$bin/warmbuild"
printf 'Installed warmbuild %s (sha256 %s) to %s/warmbuild\n' "$version" "$actual" "$bin"

path_line="export PATH=\"$bin:\$PATH\""
case ":$PATH:" in
  *":$bin:"*) ;;
  *)
    if [ "$add_to_path" = "1" ]; then
      case "${SHELL:-}" in
        */bash) profile="$HOME/.bash_profile" ;;
        *) profile="$HOME/.zshrc" ;;
      esac
      if ! grep -qsF "$bin" "$profile"; then
        printf '\n# Warmbuild\n%s\n' "$path_line" >> "$profile"
        printf 'Added %s to PATH in %s (open a new shell).\n' "$bin" "$profile"
      fi
    else
      printf '\nAdd it to PATH (e.g. in ~/.zshrc):\n  %s\n' "$path_line"
    fi
    ;;
esac

if [ -f "$home/warmbuild.pid" ]; then
  printf '\nThe cache is running. To restart it on this version, run in your repository: warmbuild start\n'
else
  printf '\nNext:\n  warmbuild login                  # once, GitHub device code\n  cd <your repository> && warmbuild start\n'
fi
