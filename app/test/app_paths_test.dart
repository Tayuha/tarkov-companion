import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tarkov_companion/src/app_paths.dart';

void main() {
  final separator = Platform.pathSeparator;

  test('XDG_DATA_HOME wins when it is set', () {
    final paths = AppPaths.resolve(
      environment: {
        'XDG_DATA_HOME': '${separator}xdg-data',
        'HOME': '${separator}home${separator}someone',
      },
    );

    expect(paths.root.path, '${separator}xdg-data${separator}tarkov_companion');
    expect(
      paths.databasePath,
      '${separator}xdg-data${separator}tarkov_companion${separator}db'
      '${separator}tarkov_companion.sqlite',
    );
    expect(
      paths.logsDirectory.path,
      '${separator}xdg-data${separator}tarkov_companion${separator}logs',
    );
    expect(
      paths.downloadsDirectory.path,
      '${separator}xdg-data${separator}tarkov_companion${separator}downloads',
    );
  });

  test('HOME/.local/share is the fallback when XDG_DATA_HOME is empty', () {
    final paths = AppPaths.resolve(
      environment: {
        'XDG_DATA_HOME': '   ',
        'HOME': '${separator}home${separator}someone',
      },
    );

    expect(
      paths.root.path,
      '${separator}home${separator}someone$separator.local'
      '${separator}share${separator}tarkov_companion',
    );
    expect(paths.downloadsDirectory.parent.path, paths.root.path);
  });

  test('an environment without a data location fails loudly', () {
    expect(
      () => AppPaths.resolve(environment: const {}),
      throwsA(isA<StateError>()),
    );
  });
}
