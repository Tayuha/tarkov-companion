import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/database_helpers.dart';

void main() {
  group('SettingsRepository (in-memory)', () {
    late AppDatabase db;
    late SettingsRepository settings;
    late List<String> warnings;

    setUp(() async {
      db = await openMemoryDatabase();
      warnings = [];
      settings = SettingsRepository(db, onWarning: warnings.add);
    });

    tearDown(() => db.close());

    test('a fresh database returns the documented defaults', () async {
      expect(await settings.read(), const AppSettings());
      expect(await db.select(db.appSettings).get(), isEmpty);
      expect(warnings, isEmpty);
    });

    test('values are JSON-encoded under the settings. prefix', () async {
      const expected = AppSettings(
        activeProfileId: 'profile-regular',
        autoUpdateEnabled: false,
        allowMeteredUpdates: true,
        dataFreshnessHours: 72,
      );

      await settings.write(expected);

      final rows = await db.select(db.appSettings).get();
      final stored = {for (final row in rows) row.key: row.value};
      expect(stored.keys, unorderedEquals(AppSettingKeys.all));
      expect(
        jsonDecode(stored[AppSettingKeys.activeProfileId]!),
        'profile-regular',
      );
      expect(jsonDecode(stored[AppSettingKeys.autoUpdateEnabled]!), isFalse);
      expect(jsonDecode(stored[AppSettingKeys.allowMeteredUpdates]!), isTrue);
      expect(jsonDecode(stored[AppSettingKeys.dataFreshnessHours]!), 72);
    });

    test('each convenience setter persists its field', () async {
      await settings.setActiveProfileId('profile-pve');
      await settings.setAutoUpdateEnabled(false);
      await settings.setAllowMeteredUpdates(true);
      await settings.setDataFreshnessHours(6);

      expect(
        await settings.read(),
        const AppSettings(
          activeProfileId: 'profile-pve',
          autoUpdateEnabled: false,
          allowMeteredUpdates: true,
          dataFreshnessHours: 6,
        ),
      );
    });

    test('the active profile id round-trips exactly, including null', () async {
      await settings.setActiveProfileId('profile-äö-42');
      expect((await settings.read()).activeProfileId, 'profile-äö-42');

      await settings.setActiveProfileId(null);
      expect((await settings.read()).activeProfileId, isNull);
      expect(
        (await db.select(db.appSettings).get()).map((row) => row.key),
        contains(AppSettingKeys.activeProfileId),
        reason: 'null is stored explicitly, not by deleting the key',
      );
    });

    test(
      'write rejects an out-of-range freshness and writes nothing',
      () async {
        await expectLater(
          settings.write(const AppSettings(dataFreshnessHours: 0)),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          settings.write(const AppSettings(dataFreshnessHours: 169)),
          throwsA(isA<ArgumentError>()),
        );

        expect(await db.select(db.appSettings).get(), isEmpty);
        expect(await settings.read(), const AppSettings());
      },
    );

    test('a rejected write keeps the previous values', () async {
      const previous = AppSettings(
        activeProfileId: 'profile-regular',
        autoUpdateEnabled: false,
      );
      await settings.write(previous);

      await expectLater(
        settings.setDataFreshnessHours(0),
        throwsA(isA<ArgumentError>()),
      );

      expect(await settings.read(), previous);
    });

    test('corrupt JSON falls back to defaults and warns', () async {
      await _putRaw(db, AppSettingKeys.activeProfileId, '{not json');
      await _putRaw(db, AppSettingKeys.autoUpdateEnabled, 'yes');
      await _putRaw(db, AppSettingKeys.allowMeteredUpdates, 'oauth');
      await _putRaw(db, AppSettingKeys.dataFreshnessHours, '24h');

      expect(await settings.read(), const AppSettings());
      expect(warnings, hasLength(4));
      expect(
        warnings.join('\n'),
        allOf(
          contains(AppSettingKeys.activeProfileId),
          contains(AppSettingKeys.autoUpdateEnabled),
          contains(AppSettingKeys.allowMeteredUpdates),
          contains(AppSettingKeys.dataFreshnessHours),
        ),
      );
    });

    test('wrong JSON types fall back to defaults and warn', () async {
      await _putRaw(db, AppSettingKeys.activeProfileId, '7');
      await _putRaw(db, AppSettingKeys.autoUpdateEnabled, '"true"');
      await _putRaw(db, AppSettingKeys.allowMeteredUpdates, '1');
      await _putRaw(db, AppSettingKeys.dataFreshnessHours, '"24"');

      expect(await settings.read(), const AppSettings());
      expect(warnings, hasLength(4));
    });

    test(
      'an out-of-range stored freshness falls back to 24 and warns',
      () async {
        await _putRaw(db, AppSettingKeys.dataFreshnessHours, '999');

        final read = await settings.read();

        expect(read.dataFreshnessHours, 24);
        expect(warnings, hasLength(1));
        expect(warnings.single, contains(AppSettingKeys.dataFreshnessHours));
        expect(warnings.single, contains('999'));
        expect(warnings.single, isNot(contains('Exception')));
      },
    );

    test('unknown keys are ignored on read and removed by write', () async {
      await settings.setDataFreshnessHours(12);
      await _putRaw(db, 'settings.hideoutOverlay', 'true');
      await _putRaw(db, 'activeProfile', '"profile-legacy"');

      final read = await settings.read();
      expect(read.dataFreshnessHours, 12);
      expect(warnings, isEmpty, reason: 'unknown keys are not errors');
      final beforeWrite = (await db.select(db.appSettings).get()).map(
        (row) => row.key,
      );
      expect(beforeWrite, contains('settings.hideoutOverlay'));
      expect(beforeWrite, contains('activeProfile'));

      await settings.write(read);

      final keys = (await db.select(db.appSettings).get()).map(
        (row) => row.key,
      );
      expect(keys, unorderedEquals(AppSettingKeys.all));
      expect(keys, isNot(contains('settings.hideoutOverlay')));
      expect(keys, isNot(contains('activeProfile')));
    });

    test(
      'write removes obsolete settings.* keys from an older version',
      () async {
        for (final key in const [
          'settings.downloadOnWifiOnly',
          'settings.updateIntervalMinutes',
          'settings.firstRunCompleted',
        ]) {
          await _putRaw(db, key, 'true');
        }

        await settings.write(const AppSettings());

        final rows = await db.select(db.appSettings).get();
        expect(rows.map((row) => row.key), unorderedEquals(AppSettingKeys.all));
      },
    );

    test('reset deletes every settings row and restores defaults', () async {
      await settings.write(
        const AppSettings(
          activeProfileId: 'profile-regular',
          autoUpdateEnabled: false,
          allowMeteredUpdates: true,
          dataFreshnessHours: 168,
        ),
      );
      await _putRaw(db, 'settings.obsolete', '1');

      final afterReset = await settings.reset();

      expect(afterReset, const AppSettings());
      expect(await db.select(db.appSettings).get(), isEmpty);
      expect(await settings.read(), const AppSettings());
    });
  });

  group('SettingsRepository (file-backed)', () {
    test('every setting survives closing and reopening the database', () async {
      final directory = createTemporaryDirectory(addTearDown);
      final path = '${directory.path}/settings.sqlite';

      final first = AppDatabase.atPath(path);
      final firstSettings = SettingsRepository(first);
      await firstSettings.setActiveProfileId('profile-pve-42');
      await firstSettings.setAutoUpdateEnabled(false);
      await firstSettings.setAllowMeteredUpdates(true);
      await firstSettings.setDataFreshnessHours(168);
      await first.close();

      final second = AppDatabase.atPath(path);
      addTearDown(second.close);

      expect(
        await SettingsRepository(second).read(),
        const AppSettings(
          activeProfileId: 'profile-pve-42',
          autoUpdateEnabled: false,
          allowMeteredUpdates: true,
          dataFreshnessHours: 168,
        ),
      );
    });

    test('a cleared active profile survives a restart as null', () async {
      final directory = createTemporaryDirectory(addTearDown);
      final path = '${directory.path}/settings.sqlite';

      final first = AppDatabase.atPath(path);
      final firstSettings = SettingsRepository(first);
      await firstSettings.setActiveProfileId('profile-regular');
      await firstSettings.setActiveProfileId(null);
      await first.close();

      final second = AppDatabase.atPath(path);
      addTearDown(second.close);

      expect((await SettingsRepository(second).read()).activeProfileId, isNull);
    });

    test('reset survives a restart', () async {
      final directory = createTemporaryDirectory(addTearDown);
      final path = '${directory.path}/settings.sqlite';

      final first = AppDatabase.atPath(path);
      final firstSettings = SettingsRepository(first);
      await firstSettings.setDataFreshnessHours(48);
      await firstSettings.reset();
      await first.close();

      final second = AppDatabase.atPath(path);
      addTearDown(second.close);

      expect(await SettingsRepository(second).read(), const AppSettings());
    });
  });
}

Future<void> _putRaw(AppDatabase db, String key, String value) async {
  await db
      .into(db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion(key: Value(key), value: Value(value)),
      );
}
