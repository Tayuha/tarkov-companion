# Tarkov Companion — Flutter client

The desktop client for Tarkov Companion. Windows is the launch target; Linux is the development
host; Android stays buildable for a later release.

## Toolchain

- Flutter 3.50.1 (stable channel)
- Dart 3.14.0
- Project constraint: `sdk: ^3.14.0`

Platform folders for `windows`, `linux`, and `android` are checked in.

## Linux (development host)

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d linux
flutter build linux --debug
```

The Linux debug bundle is written to `build/linux/x64/debug/bundle/`.

## Windows (CI only)

Windows builds are verified in GitHub Actions because the development host is Linux. The `app` job in
`.github/workflows/ci.yml` runs on a `windows-latest` runner pinned to Flutter 3.50.1 and executes
`flutter pub get`, `flutter analyze`, `flutter test`, and `flutter build windows --debug`. The Windows
runner sources are generated and tracked, but they cannot be compiled or launched locally. On a Windows
machine:

```powershell
flutter pub get
flutter test
flutter run -d windows
flutter build windows --debug
```

## Package structure

`app/pubspec.yaml` is the root of a Dart pub workspace. All four packages resolve against one lockfile
(`app/pubspec.lock`); the package folders do not have their own lockfiles.

```
app/                          Flutter shell: UI composition, navigation, platform wiring
  lib/
  packages/
    core/                     tarkov_companion_core   pure Dart primitives, no dependencies
    data/                     tarkov_companion_data   bundles, SQLite, repositories (pure Dart for now)
    features/                 tarkov_companion_features  Flutter feature modules
```

Dependency rules, enforced by `tool/check_architecture.dart`, a unit test, and CI:

| Package | May import | Must not import |
|---|---|---|
| `core` | `core` | Flutter, `dart:ui`, `data`, `features`, `app` |
| `data` | `core`, `data` | Flutter, `dart:ui`, `features`, `app` |
| `features` | `core`, `data`, `features` | `app` |
| `app` | `core`, `data`, `features`, `app` | — (the shell composes everything) |

No package may import `app`, no feature may import another feature (there is only one features package so
far), and relative imports may not cross a package's `lib/` boundary. Use `package:` imports across
packages.

Run the checker from `app/`:

```bash
dart run tool/check_architecture.dart
```

It scans `lib/` and `packages/*/lib/`, prints every violation as `file:line: directive 'uri': reason`, and
exits 1 on failure. The rule engine is a pure function over source text; `test/check_architecture_test.dart`
proves that a core-to-data import, a data-to-features import, a features-to-app import, and a
cross-package relative import (among others) are each rejected.

The app's own tests run with `flutter test`. The package tests run from `app/` too:

```bash
dart test packages/core
dart test packages/data
flutter test packages/features
```

## Adding dependencies

Keep the dependency set minimal. Every runtime package must work on Windows and stay compatible
with Android/iOS later; prefer pure-Dart packages so logic remains testable without a UI.
