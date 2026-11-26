import 'package:flutter_test/flutter_test.dart';

import '../tool/check_architecture.dart';

void main() {
  group('import boundary rules', () {
    test('core may not import data', () {
      final violations = analyzeSource(
        layer: PackageLayer.core,
        filePath: 'packages/core/lib/src/leak.dart',
        source: '''
import 'dart:async';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
''',
      );

      expect(violations, hasLength(1));
      expect(violations.single.directive, 'import');
      expect(violations.single.line, 3);
      expect(violations.single.reason, contains('core may not import data'));
    });

    test('data may not import features', () {
      final violations = analyzeSource(
        layer: PackageLayer.data,
        filePath: 'packages/data/lib/src/leak.dart',
        source: '''
import 'package:tarkov_companion_features/tarkov_companion_features.dart';
''',
      );

      expect(violations, hasLength(1));
      expect(
        violations.single.reason,
        contains('data may not import features'),
      );
    });

    test('features may not import the app shell', () {
      final violations = analyzeSource(
        layer: PackageLayer.features,
        filePath: 'packages/features/lib/src/leak.dart',
        source: '''
export 'package:tarkov_companion/main.dart';
''',
      );

      expect(violations, hasLength(1));
      expect(violations.single.directive, 'export');
      expect(
        violations.single.reason,
        contains('the app shell is not a library'),
      );
    });

    test('app may import every workspace sibling', () {
      final violations = analyzeSource(
        layer: PackageLayer.app,
        filePath: 'lib/composition.dart',
        source: '''
import 'package:tarkov_companion_core/tarkov_companion_core.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';
import 'package:tarkov_companion/main.dart';
''',
      );

      expect(violations, isEmpty);
    });

    test('a relative import may not escape its package lib directory', () {
      final violations = analyzeSource(
        layer: PackageLayer.data,
        filePath: 'packages/data/lib/src/leak.dart',
        source: '''
import '../../../core/lib/tarkov_companion_core.dart';
''',
      );

      expect(violations, hasLength(1));
      expect(
        violations.single.uri,
        '../../../core/lib/tarkov_companion_core.dart',
      );
      expect(
        violations.single.reason,
        contains('relative import escapes packages/data/lib/'),
      );
    });

    test('relative imports inside one package lib are allowed', () {
      final violations = analyzeSource(
        layer: PackageLayer.data,
        filePath: 'packages/data/lib/src/deep/loader.dart',
        source: '''
import '../dataset_kind.dart';
import 'reader.dart';
''',
      );

      expect(violations, isEmpty);
    });

    test('pure Dart packages may not import Flutter or dart:ui', () {
      final violations = analyzeSource(
        layer: PackageLayer.core,
        filePath: 'packages/core/lib/src/leak.dart',
        source: '''
import 'dart:ui';
import 'package:flutter/widgets.dart';
''',
      );

      expect(violations, hasLength(2));
      expect(violations.first.reason, contains('must stay pure Dart'));
      expect(violations.last.reason, contains('must stay pure Dart'));
    });
  });

  group('checkWorkspace', () {
    test('finds the deliberate violation and reports exit-worthy count', () {
      // The real tree test lives in architecture_test.dart; this documents that
      // the same engine produces a non-empty result for a failing file set.
      final violations = analyzeSource(
        layer: PackageLayer.core,
        filePath: 'packages/core/lib/src/leak.dart',
        source: "import 'package:tarkov_companion_data/data.dart';\n",
      );

      expect(violations, isNotEmpty);
      expect(
        violations.first.toString(),
        startsWith('packages/core/lib/src/leak.dart:1:'),
      );
    });
  });
}
