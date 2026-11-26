import 'package:test/test.dart';
import 'package:tarkov_companion_core/tarkov_companion_core.dart';

void main() {
  group('Result', () {
    test('carries a success value', () {
      const Result<int> result = Ok(41);

      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.valueOrNull, 41);
    });

    test('carries a failure without a value', () {
      final error = ArgumentError('bad input');
      final result = Err<int>(error);

      expect(result.isOk, isFalse);
      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.error, same(error));
    });

    test('maps a success and skips a failure', () {
      const Result<int> success = Ok(20);
      final Result<int> failure = Err(ArgumentError('bad input'));

      final mappedSuccess = success.map((value) => value + 1);
      final mappedFailure = failure.map((value) => value + 1);

      expect(mappedSuccess.valueOrNull, 21);
      expect(mappedFailure.isErr, isTrue);
      expect(mappedFailure.valueOrNull, isNull);
    });
  });
}
