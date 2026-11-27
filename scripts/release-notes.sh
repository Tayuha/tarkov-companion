#!/usr/bin/env bash
#
# Generate the release notes that ship next to the Linux artifacts.
#
# The notes are deliberately plain: artifact names, their SHA-256 checksums and
# an explicit statement that nothing is signed. Run it after
# scripts/package-linux.sh wrote dist/SHA256SUMS:
#
#   bash scripts/release-notes.sh
#   bash scripts/release-notes.sh --tag v0.1.0 --commit "$GITHUB_SHA"
#   bash scripts/release-notes.sh --checksums dist/SHA256SUMS --out /tmp/notes.md
#
# This script never tags, signs or publishes anything. It only reads files.
# The release workflow (`.github/workflows/release-linux.yml`) uploads the
# result as a workflow artifact and, for a version tag, attaches it to a draft
# GitHub Release.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PUBSPEC="$ROOT/app/pubspec.yaml"

CHECKSUMS="$ROOT/dist/SHA256SUMS"
OUT="$ROOT/dist/RELEASE_NOTES.md"
TAG=""
COMMIT=""
PRINT_STDOUT=0

usage() {
  cat <<'USAGE'
usage: scripts/release-notes.sh [options]

  --checksums PATH   sha256sum file to embed (default: dist/SHA256SUMS)
  --out PATH         write notes here (default: dist/RELEASE_NOTES.md)
  --tag TAG          release tag to validate, e.g. v0.1.0
  --commit SHA       commit being released (default: git rev-parse HEAD)
  --stdout           also print the notes to stdout
  -h, --help         show this help
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --checksums)
      [[ $# -ge 2 ]] || die "--checksums needs a path"
      CHECKSUMS="$2"
      shift 2
      ;;
    --out)
      [[ $# -ge 2 ]] || die "--out needs a path"
      OUT="$2"
      shift 2
      ;;
    --tag)
      [[ $# -ge 2 ]] || die "--tag needs a value"
      TAG="$2"
      shift 2
      ;;
    --commit)
      [[ $# -ge 2 ]] || die "--commit needs a value"
      COMMIT="$2"
      shift 2
      ;;
    --stdout)
      PRINT_STDOUT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument '$1'"
      ;;
  esac
done

[[ -f "$APP_PUBSPEC" ]] || die "missing $APP_PUBSPEC"
[[ -f "$CHECKSUMS" ]] || die "missing $CHECKSUMS; run scripts/package-linux.sh first"

VERSION_LINE="$(sed -n 's/^version:[[:space:]]*//p' "$APP_PUBSPEC" | head -n 1 | tr -d '\r')"
[[ -n "$VERSION_LINE" ]] || die "no 'version:' line in app/pubspec.yaml"

VERSION="${VERSION_LINE%%+*}"
BUILD_NUMBER="${VERSION_LINE#*+}"
if [[ "$BUILD_NUMBER" == "$VERSION_LINE" ]]; then
  BUILD_NUMBER="0"
fi

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die "unsupported version '$VERSION_LINE' (expected MAJOR.MINOR.PATCH[+BUILD])"

if [[ -n "$TAG" ]]; then
  [[ "$TAG" == "v$VERSION" ]] \
    || die "tag '$TAG' does not match app/pubspec.yaml version 'v$VERSION'"
fi

if [[ -z "$COMMIT" ]]; then
  COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
fi

# Refuse a checksum file that is empty or not in sha256sum format; a release
# note with a stale or hand-written checksum is worse than no note at all.
if ! awk 'NF == 2 && $1 ~ /^[0-9a-f]{64}$/ {ok = 1} END {exit ok ? 0 : 1}' "$CHECKSUMS"; then
  die "$CHECKSUMS is not a sha256sum file produced by scripts/package-linux.sh"
fi

ARTIFACT_COUNT="$(awk 'NF == 2 && $1 ~ /^[0-9a-f]{64}$/ {n++} END {print n + 0}' "$CHECKSUMS")"
[[ "$ARTIFACT_COUNT" -gt 0 ]] || die "$CHECKSUMS lists no artifacts"

mkdir -p "$(dirname "$OUT")"

TAG_LINE="${TAG:-v$VERSION}"
NOW_UTC="$(date -u +'%Y-%m-%d')"

{
  cat <<EOF
# Tarkov Companion ${TAG_LINE} — Linux preview

Local-first Escape from Tarkov companion. This release contains the Linux
x86_64 desktop build, built from commit \`${COMMIT}\`.

- App version: \`${VERSION}\` (Flutter build \`${BUILD_NUMBER}\`)
- Target: Linux x86_64
- Release date: ${NOW_UTC}

## Signing status

**The Linux artifacts are not signed.** No code-signing key, GPG key or
notarization is configured for this release. GitHub also does not publish
build provenance for these files, so the SHA-256 checksums below and the
workflow run linked on the release page are the only integrity evidence.

Do not install an artifact whose checksum does not match. If a signature is
required in your environment, build from source with
\`bash scripts/package-linux.sh\` and compare the result yourself.

## Artifacts and SHA-256

EOF

  printf '| File | SHA-256 |\n|---|---|\n'
  while read -r sum name; do
    [[ -n "${sum:-}" && -n "${name:-}" ]] || continue
    printf '| `%s` | `%s` |\n' "$name" "$sum"
  done < "$CHECKSUMS"

  cat <<'EOF'

`SHA256SUMS` in the release assets uses the standard `sha256sum` format.

## Verify before running

```bash
sha256sum -c SHA256SUMS
chmod +x TarkovCompanion-*-x86_64.AppImage
./TarkovCompanion-*-x86_64.AppImage
```

On hosts without FUSE (containers or minimal installs):

```bash
./TarkovCompanion-*-x86_64.AppImage --appimage-extract-and-run
```

The optional `.deb` is installed with
`sudo apt install ./TarkovCompanion-*-x86_64.deb`. See
[`docs/linux-package.md`](https://github.com/Tayuha/tarkov-companion/blob/main/docs/linux-package.md)
for the full packaging and approval checklist.

## First-run gate

The app downloads game data on first run. The first-run screen shows the size
estimate before anything is downloaded; the sync can be cancelled and resumed.
Game data comes from [tarkov.dev](https://tarkov.dev). No account is needed and
the app sends no telemetry.

## Manual approval required

This is a preview release. Before it is promoted beyond a draft, a maintainer
must launch the artifact on a clean Linux environment and complete the
sync/browse checklist in `docs/linux-package.md`. Automated CI only proves the
AppImage starts and reaches the Flutter engine.

---

Not affiliated with, endorsed by, or sponsored by Battlestate Games.
Escape from Tarkov and related marks are the property of their respective
owners. See [NOTICE](https://github.com/Tayuha/tarkov-companion/blob/main/NOTICE).
EOF
} > "$OUT"

log "Wrote $OUT (version $VERSION, $ARTIFACT_COUNT artifact(s))"

if [[ "$PRINT_STDOUT" == "1" ]]; then
  cat "$OUT"
fi
