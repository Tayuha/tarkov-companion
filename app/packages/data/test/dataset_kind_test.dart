import 'package:tarkov_companion_core/tarkov_companion_core.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

void main() {
  group('DatasetKind', () {
    test('parses every documented bundle dataset', () {
      const ids = [
        'items',
        'tasks',
        'traders',
        'hideout',
        'crafts',
        'barters',
        'maps',
      ];

      for (final id in ids) {
        final result = DatasetKind.parse(id);

        expect(result.isOk, isTrue, reason: id);
        expect(result.valueOrNull?.id, id);
      }
    });

    test('rejects an unknown dataset as data, not an exception', () {
      final result = DatasetKind.parse('season');

      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      final error = switch (result) {
        Err<DatasetKind>(:final error) => error,
        Ok<DatasetKind>() => fail('expected an error'),
      };
      expect(error, isA<ArgumentError>());
    });
  });
}
