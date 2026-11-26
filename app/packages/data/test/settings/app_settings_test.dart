import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

void main() {
  group('AppSettings', () {
    test('defaults match the documented values', () {
      const settings = AppSettings();

      expect(settings.activeProfileId, isNull);
      expect(settings.autoUpdateEnabled, isTrue);
      expect(settings.allowMeteredUpdates, isFalse);
      expect(settings.dataFreshnessHours, 24);
      expect(settings.isValid, isTrue);
    });

    test('copyWith replaces only the supplied fields', () {
      const settings = AppSettings();

      final changed = settings.copyWith(
        autoUpdateEnabled: false,
        dataFreshnessHours: 48,
      );

      expect(changed.activeProfileId, isNull);
      expect(changed.autoUpdateEnabled, isFalse);
      expect(changed.allowMeteredUpdates, isFalse);
      expect(changed.dataFreshnessHours, 48);
      expect(settings.autoUpdateEnabled, isTrue, reason: 'value type');
    });

    test('copyWith can set and explicitly clear the active profile', () {
      const settings = AppSettings();

      final assigned = settings.copyWith(activeProfileId: 'profile-pve');
      expect(assigned.activeProfileId, 'profile-pve');

      final cleared = assigned.copyWith(activeProfileId: null);
      expect(cleared.activeProfileId, isNull);
    });

    test('equality and hashCode cover every field', () {
      const base = AppSettings(activeProfileId: 'p', dataFreshnessHours: 12);
      final same = base.copyWith();

      expect(same, base);
      expect(same.hashCode, base.hashCode);
      expect(base, isNot(base.copyWith(autoUpdateEnabled: false)));
      expect(base, isNot(base.copyWith(allowMeteredUpdates: true)));
      expect(base, isNot(base.copyWith(dataFreshnessHours: 13)));
      expect(base, isNot(base.copyWith(activeProfileId: 'q')));
      expect(base, isNot(base.copyWith(activeProfileId: null)));
    });

    test('freshness range is 1 to 168 inclusive', () {
      expect(AppSettings.isValidDataFreshnessHours(0), isFalse);
      expect(AppSettings.isValidDataFreshnessHours(1), isTrue);
      expect(AppSettings.isValidDataFreshnessHours(168), isTrue);
      expect(AppSettings.isValidDataFreshnessHours(169), isFalse);
      expect(const AppSettings(dataFreshnessHours: 0).isValid, isFalse);
    });
  });
}
