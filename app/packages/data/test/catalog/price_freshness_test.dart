import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

void main() {
  final observedAt = DateTime.utc(2026, 11, 25, 12);
  const day = Duration(hours: 24);

  group('FreshnessPolicy', () {
    test(
      'an age exactly at the threshold is fresh (strictly-greater rule)',
      () {
        final verdict = FreshnessPolicy(day)
            .evaluate(observedAt, observedAt.add(day));

        expect(verdict.status, FreshnessStatus.fresh);
        expect(verdict.isFresh, isTrue);
        expect(verdict.isStale, isFalse);
        expect(verdict.age, day);
        expect(verdict.threshold, day);
        expect(verdict.observedAt, observedAt);
      },
    );

    test('one second past the threshold is stale', () {
      final verdict = FreshnessPolicy(
        day,
      ).evaluate(observedAt, observedAt.add(day + const Duration(seconds: 1)));

      expect(verdict.status, FreshnessStatus.stale);
      expect(verdict.isStale, isTrue);
      expect(verdict.isFresh, isFalse);
      expect(verdict.age, day + const Duration(seconds: 1));
    });

    test('just under the threshold is fresh', () {
      final verdict = FreshnessPolicy(day).evaluate(
        observedAt,
        observedAt.add(const Duration(hours: 23, minutes: 59)),
      );

      expect(verdict.status, FreshnessStatus.fresh);
      expect(verdict.age, const Duration(hours: 23, minutes: 59));
    });

    test('a custom one-hour threshold moves both boundaries', () {
      final policy = FreshnessPolicy(const Duration(hours: 1));

      expect(
        policy
            .evaluate(observedAt, observedAt.add(const Duration(hours: 1)))
            .status,
        FreshnessStatus.fresh,
        reason: 'equal to the threshold is fresh',
      );
      expect(
        policy
            .evaluate(
              observedAt,
              observedAt.add(const Duration(hours: 1, seconds: 1)),
            )
            .status,
        FreshnessStatus.stale,
      );
      // The same two-hour-old observation is fresh under the 24 h policy.
      expect(
        FreshnessPolicy(day)
            .evaluate(observedAt, observedAt.add(const Duration(hours: 2)))
            .status,
        FreshnessStatus.fresh,
      );
    });

    test('a null observation is unknown, not fresh', () {
      final verdict = FreshnessPolicy(day).evaluate(null, observedAt);

      expect(verdict.status, FreshnessStatus.unknown);
      expect(verdict.isUnknown, isTrue);
      expect(verdict.isStale, isFalse);
      expect(verdict.isFresh, isFalse);
      expect(verdict.observedAt, isNull);
      expect(verdict.age, isNull);
      expect(verdict.threshold, day);
      expect(verdict.requiresObservationTime, isFalse);
    });

    test('a future observation is fresh and its age is clamped to zero', () {
      final verdict = FreshnessPolicy(day)
          .evaluate(observedAt, observedAt.subtract(const Duration(hours: 3)));

      expect(verdict.status, FreshnessStatus.fresh);
      expect(verdict.age, Duration.zero);
      expect(verdict.observedAt, observedAt);
      expect(verdict.requiresObservationTime, isTrue);
    });

    test('the default threshold is the 24-hour setting default', () {
      const policy = FreshnessPolicy.defaults();

      expect(policy.threshold, const Duration(hours: 24));
      expect(
        policy.threshold,
        const Duration(hours: AppSettings.defaultDataFreshnessHours),
      );
    });

    test('fromSettings follows dataFreshnessHours', () {
      expect(
        FreshnessPolicy.fromSettings(const AppSettings()).threshold,
        const Duration(hours: 24),
      );
      expect(
        FreshnessPolicy.fromSettings(const AppSettings(dataFreshnessHours: 1))
            .threshold,
        const Duration(hours: 1),
      );
      expect(
        FreshnessPolicy.fromSettings(
          const AppSettings().copyWith(dataFreshnessHours: 168),
        ).threshold,
        const Duration(hours: 168),
      );
    });

    test('rejects a negative threshold', () {
      expect(
        () => FreshnessPolicy(const Duration(seconds: -1)),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
