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

## Adding dependencies

Keep the dependency set minimal. Every runtime package must work on Windows and stay compatible
with Android/iOS later; prefer pure-Dart packages so logic remains testable without a UI.
