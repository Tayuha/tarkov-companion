import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_architecture.dart';

void main() {
  test('the client workspace has no import-boundary violations', () {
    final report = checkWorkspace(_appRoot());

    expect(report.filesChecked, greaterThanOrEqualTo(7));
    expect(
      report.violations,
      isEmpty,
      reason: report.violations.map((violation) => '$violation').join('\n'),
    );
  });
}

/// Finds `app/` from the directory `flutter test` runs in.
Directory _appRoot() {
  var directory = Directory.current;
  while (true) {
    if (File('${directory.path}/tool/check_architecture.dart').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not find app/tool/check_architecture.dart');
    }
    directory = parent;
  }
}
