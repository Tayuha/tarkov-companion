#!/usr/bin/env bash
#
# Build the Linux release artifacts for Tarkov Companion.
#
# Run from anywhere; paths are resolved from the repository root:
#
#   bash scripts/package-linux.sh
#
# Produces, under dist/:
#   TarkovCompanion-<version>-x86_64.AppImage
#   TarkovCompanion-<version>-x86_64.deb     (only when dpkg-deb is available)
#   SHA256SUMS
#
# The version comes from app/pubspec.yaml. This script does not tag, sign or
# publish anything; see docs/linux-package.md for the manual approval gate.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/app"
DIST="$ROOT/dist"
CACHE="$ROOT/.cache/package-linux"
PACKAGING="$APP_DIR/linux/packaging"

BINARY_NAME="tarkov_companion"
APP_NAME="Tarkov Companion"
APP_ID="dev.tarkovcompanion.tarkov_companion"
ARCH="x86_64"
APPIMAGETOOL_URL="${APPIMAGETOOL_URL:-https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

# --- Toolchain ------------------------------------------------------------

# Prefer an explicit FLUTTER, then PATH, then the common per-user install.
if [[ -n "${FLUTTER:-}" ]]; then
  FLUTTER_BIN="$FLUTTER"
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN="$(command -v flutter)"
elif [[ -x "$HOME/.local/flutter/bin/flutter" ]]; then
  FLUTTER_BIN="$HOME/.local/flutter/bin/flutter"
else
  die "flutter not found; put it on PATH or set FLUTTER=/path/to/flutter"
fi

command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required"

# --- Version metadata -----------------------------------------------------

VERSION_LINE="$(sed -n 's/^version:[[:space:]]*//p' "$APP_DIR/pubspec.yaml" | head -n 1 | tr -d '\r')"
[[ -n "$VERSION_LINE" ]] || die "no 'version:' line in app/pubspec.yaml"

VERSION="${VERSION_LINE%%+*}"
BUILD_NUMBER="${VERSION_LINE#*+}"
if [[ "$BUILD_NUMBER" == "$VERSION_LINE" ]]; then
  BUILD_NUMBER="0"
fi

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die "unsupported version '$VERSION_LINE' in app/pubspec.yaml (expected MAJOR.MINOR.PATCH[+BUILD])"

APPIMAGE="$DIST/TarkovCompanion-${VERSION}-${ARCH}.AppImage"
DEB="$DIST/TarkovCompanion-${VERSION}-${ARCH}.deb"
CHECKSUMS="$DIST/SHA256SUMS"

log "Version $VERSION (build $BUILD_NUMBER) from app/pubspec.yaml"
log "Flutter: $FLUTTER_BIN"

mkdir -p "$DIST" "$CACHE"

# --- Flutter release build ------------------------------------------------

if [[ "${SKIP_BUILD:-0}" == "1" ]]; then
  log "SKIP_BUILD=1: reusing the existing release bundle"
else
  log "Building Linux release bundle"
  if ! ( cd "$APP_DIR" && "$FLUTTER_BIN" pub get && "$FLUTTER_BIN" build linux --release ); then
    die "flutter build linux --release failed; no package was produced"
  fi
fi

BUNDLE="$APP_DIR/build/linux/x64/release/bundle"
[[ -x "$BUNDLE/$BINARY_NAME" ]] \
  || die "release bundle missing $BUNDLE/$BINARY_NAME; run without SKIP_BUILD=1"

# --- Assembling the AppDir ------------------------------------------------

APPDIR="$DIST/AppDir-${ARCH}"
log "Assembling AppDir at $APPDIR"
rm -rf "$APPDIR"
mkdir -p \
  "$APPDIR/usr/bin" \
  "$APPDIR/usr/share/applications" \
  "$APPDIR/usr/share/icons/hicolor/256x256/apps" \
  "$APPDIR/usr/share/icons/hicolor/512x512/apps"

# Flutter resolves data/ and lib/ relative to the real executable, so keeping
# the whole bundle together under usr/bin is the least surprising layout.
cp -a "$BUNDLE/." "$APPDIR/usr/bin/"

cp "$PACKAGING/tarkov-companion.png" "$APPDIR/tarkov-companion.png"
cp "$PACKAGING/tarkov-companion-512.png" "$APPDIR/tarkov-companion-512.png"
cp "$PACKAGING/tarkov-companion.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/tarkov-companion.png"
cp "$PACKAGING/tarkov-companion-512.png" "$APPDIR/usr/share/icons/hicolor/512x512/apps/tarkov-companion.png"
ln -sf tarkov-companion.png "$APPDIR/.DirIcon"

# The desktop template carries an @VERSION@ placeholder so the menu entry and
# the AppImage metadata always agree with pubspec.yaml.
sed "s/@VERSION@/$VERSION/" "$PACKAGING/tarkov-companion.desktop" > "$APPDIR/tarkov-companion.desktop"
cp "$APPDIR/tarkov-companion.desktop" "$APPDIR/usr/share/applications/tarkov-companion.desktop"

cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
set -eu
HERE="$(dirname "$(readlink -f "$0")")"
export APPDIR="$HERE"
exec "$HERE/usr/bin/tarkov_companion" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

# --- AppImage -------------------------------------------------------------

APPIMAGETOOL="${APPIMAGETOOL:-$CACHE/appimagetool-${ARCH}.AppImage}"

if [[ ! -x "$APPIMAGETOOL" ]]; then
  log "Downloading appimagetool into $CACHE"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 2 "$APPIMAGETOOL_URL" -o "$APPIMAGETOOL.part"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$APPIMAGETOOL_URL" -O "$APPIMAGETOOL.part"
  else
    die "curl or wget is required to download appimagetool"
  fi
  mv "$APPIMAGETOOL.part" "$APPIMAGETOOL"
  chmod +x "$APPIMAGETOOL"
fi

log "Building $APPIMAGE"
rm -f "$APPIMAGE"
# --appimage-extract-and-run avoids a FUSE mount, so this works in containers
# and on hosts without libfuse2 installed.
if ! ARCH="$ARCH" "$APPIMAGETOOL" --appimage-extract-and-run "$APPDIR" "$APPIMAGE"; then
  die "appimagetool failed; no AppImage was produced"
fi
[[ -f "$APPIMAGE" ]] || die "appimagetool reported success but $APPIMAGE is missing"
chmod +x "$APPIMAGE"

# --- Optional .deb --------------------------------------------------------

ARTIFACTS=("$(basename "$APPIMAGE")")

if command -v dpkg-deb >/dev/null 2>&1; then
  log "Building $DEB"
  DEBROOT="$DIST/.deb-${ARCH}"
  rm -rf "$DEBROOT"
  mkdir -p \
    "$DEBROOT/DEBIAN" \
    "$DEBROOT/opt/tarkov-companion" \
    "$DEBROOT/usr/bin" \
    "$DEBROOT/usr/share/applications" \
    "$DEBROOT/usr/share/icons/hicolor/256x256/apps" \
    "$DEBROOT/usr/share/icons/hicolor/512x512/apps"

  cp -a "$BUNDLE/." "$DEBROOT/opt/tarkov-companion/"
  ln -sf /opt/tarkov-companion/"$BINARY_NAME" "$DEBROOT/usr/bin/$BINARY_NAME"
  cp "$APPDIR/tarkov-companion.desktop" "$DEBROOT/usr/share/applications/"
  cp "$PACKAGING/tarkov-companion.png" "$DEBROOT/usr/share/icons/hicolor/256x256/apps/"
  cp "$PACKAGING/tarkov-companion-512.png" "$DEBROOT/usr/share/icons/hicolor/512x512/apps/"

  INSTALLED_KB="$(du -sk "$DEBROOT/opt/tarkov-companion" | cut -f1)"
  cat > "$DEBROOT/DEBIAN/control" <<CONTROL
Package: tarkov-companion
Version: $VERSION
Architecture: amd64
Maintainer: Tarkov Companion contributors
Installed-Size: $INSTALLED_KB
Depends: libgtk-3-0 | libgtk-3-0t64, libstdc++6
Section: games
Priority: optional
Description: Local-first Escape from Tarkov companion
 Browse items, follow flea prices, and track quest progress offline.
 Game data is updated from signed bundles published on GitHub Releases.
 Not affiliated with Battlestate Games.
CONTROL

  rm -f "$DEB"
  dpkg-deb --build --root-owner-group "$DEBROOT" "$DEB" >/dev/null
  rm -rf "$DEBROOT"
  ARTIFACTS+=("$(basename "$DEB")")
else
  log "dpkg-deb not found: skipping the optional .deb"
fi

# --- Checksums ------------------------------------------------------------

log "Writing $CHECKSUMS"
(
  cd "$DIST"
  sha256sum "${ARTIFACTS[@]}" | sort -k2 > SHA256SUMS
)
rm -rf "$APPDIR"

printf '\nArtifacts in %s:\n' "$DIST"
for artifact in "${ARTIFACTS[@]}"; do
  printf '  %s  %s\n' "$(stat -c '%s' "$DIST/$artifact" | numfmt --to=iec 2>/dev/null || stat -c '%s' "$DIST/$artifact")" "$DIST/$artifact"
done
printf '  checksums: %s\n\n' "$CHECKSUMS"
cat "$CHECKSUMS"
printf '\nVerify with: (cd dist && sha256sum -c SHA256SUMS)\n'
