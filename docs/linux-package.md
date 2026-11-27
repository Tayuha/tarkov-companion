# Linux packaging

The first release target is Linux (design D9). `scripts/package-linux.sh` builds a
versioned AppImage, an optional `.deb`, and a `SHA256SUMS` file. Nothing is
signed, tagged, or published: the package must be launched, synced, and browsed
manually before the Windows/mobile packaging work resumes. Record the run in
[`verification.md`](verification.md), which also covers offline behaviour, a
corrupt-database recovery, the captured-request review, and the README walkthrough.

## Prerequisites

- Flutter 3.50.1 (stable), with `flutter` on `PATH` or `FLUTTER` set.
- A Linux desktop build toolchain: `cmake`, `ninja`, `clang`/`gcc`, `pkg-config`,
  and the GTK 3 development headers.
- `curl` or `wget` (downloads `appimagetool` on first use).
- `dpkg-deb` **only** for the optional `.deb`; without it the AppImage is still
  produced and the script says the `.deb` was skipped.

On Debian/Ubuntu:

```bash
sudo apt-get install -y build-essential clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev curl
```

## Build

From the repository root:

```bash
bash scripts/package-linux.sh
```

The script:

1. reads the version from `app/pubspec.yaml` (`version: 0.1.0+1`);
2. runs `flutter pub get` and `flutter build linux --release` in `app/`, and
   stops with a clear error if the build fails;
3. copies `app/build/linux/x64/release/bundle/` into an AppDir with an `AppRun`
   launcher, a `.desktop` file, and the project icon;
4. downloads `appimagetool` into `.cache/package-linux/` when missing and builds
   the AppImage with `--appimage-extract-and-run` (no FUSE required);
5. builds the `.deb` with `dpkg-deb` when available;
6. writes `dist/SHA256SUMS` for every artifact and prints the paths, sizes and
   checksums.

To repackage the existing release bundle without rebuilding (useful when only
packaging metadata changed):

```bash
SKIP_BUILD=1 bash scripts/package-linux.sh
```

## Versioning and artifact names

`app/pubspec.yaml` is the single source of truth:

```yaml
version: 0.1.0+1
```

- `0.1.0` is the artifact version used in file names, the desktop entry, and the
  AppImage version metadata.
- `+1` is the Flutter build number. It is printed during packaging but is not
  part of the artifact name.

Bump the version in `app/pubspec.yaml` before packaging a release; do not edit a
file name by hand. For the current version the script produces:

| Artifact                  | Path                                         |
| ------------------------- | -------------------------------------------- |
| AppImage                  | `dist/TarkovCompanion-0.1.0-x86_64.AppImage` |
| Debian package (optional) | `dist/TarkovCompanion-0.1.0-x86_64.deb`      |
| Checksums                 | `dist/SHA256SUMS`                            |

`dist/` is ignored by Git. The AppImage is approximately 11 MB (squashed); the
`.deb` is about 8 MB because it stores the bundle uncompressed inside an `ar`
archive.

## Verify

```bash
cd dist
file ./*.AppImage ./*.deb
sha256sum -c SHA256SUMS
```

`SHA256SUMS` uses the standard `sha256sum` format, so it works with
`sha256sum -c` on any Linux host. A mismatch means the artifact was rebuilt or
modified; rebuild and re-check rather than hand-editing the file.

The build is **unsigned**: no signing key is configured yet. The generated
release notes say so on every release and include the SHA-256 table; see
[`release.md`](release.md) for the full release process.

## CI

`.github/workflows/release-linux.yml` runs on manual dispatch and on `v*` tags.
The `package` job runs on `ubuntu-latest` with Flutter 3.50.1, installs the
GTK/CMake toolchain and `xvfb`, runs `scripts/package-linux.sh`, verifies
`SHA256SUMS`, smoke-launches the AppImage under Xvfb for up to 25 seconds,
generates `dist/RELEASE_NOTES.md`, and uploads the AppImage, optional `.deb`,
checksum file, notes, and smoke log as a workflow artifact. A tag additionally
creates a **draft** GitHub Release in a separate `contents: write` job. Nothing
is signed and nothing is published without manual approval.

`.github/workflows/ci.yml` keeps building the package on `main` and pull
requests for early failure detection. It does not create a release or tag. The
Windows job stays as a compatibility check.

## Run the AppImage

```bash
chmod +x dist/TarkovCompanion-0.1.0-x86_64.AppImage
./dist/TarkovCompanion-0.1.0-x86_64.AppImage
```

No installation or administrator rights are needed. On hosts without FUSE
(containers, minimal installs) use:

```bash
./dist/TarkovCompanion-0.1.0-x86_64.AppImage --appimage-extract-and-run
```

The same flag is used for the CI smoke run.

## Install the optional .deb

```bash
sudo apt install ./dist/TarkovCompanion-0.1.0-x86_64.deb
```

It installs the bundle under `/opt/tarkov-companion`, links
`/usr/bin/tarkov_companion`, and registers the desktop entry and icon, so
`dpkg --remove tarkov-companion` uninstalls it cleanly.

## Icon and branding (provisional)

The icon at `app/linux/packaging/tarkov-companion.svg` (rendered as 256 px and
512 px PNGs) is a neutral geometric placeholder. It deliberately contains no
official game art, logo, or trademark. Branding is provisional until the visual
design work is approved.

The `.desktop` template is `app/linux/packaging/tarkov-companion.desktop`; its
`X-AppImage-Version` placeholder is filled from `pubspec.yaml` during packaging.
To replace the icon, edit the SVG and regenerate the PNGs:

```bash
cd app/linux/packaging
rsvg-convert -w 256 -h 256 -o tarkov-companion.png tarkov-companion.svg
rsvg-convert -w 512 -h 512 -o tarkov-companion-512.png tarkov-companion.svg
```

## Manual approval checklist

Run this on a clean Linux environment with no Flutter SDK and no prior app data.
Record the result in [`verification.md`](verification.md) and the release issue;
do not publish until the manual gates pass.

1. Download the CI artifact and verify it:
   `sha256sum -c SHA256SUMS`.
2. Launch: `./TarkovCompanion-0.1.0-x86_64.AppImage`. A window opens without
   installation or root rights.
3. First run: the first-run data gate shows the download size estimate; start
   the sync and let it finish. A progress bar reports the datasets and the
   applied version.
4. Browse: open the item catalog, search for an item, apply a category filter,
   and open an item detail view. Prices and names render from the synced data.
5. Restart the app with the network disabled and confirm the catalog still
   opens from the local database.
6. Record the environment (distribution, display server, GPU) and the result in
   the task comment. Only then tick 8.9 and resume Windows/mobile packaging.

The automated smoke test in this repository only proves that the AppImage
starts and reaches the Flutter engine; it does not replace the sync and browse
steps above.
