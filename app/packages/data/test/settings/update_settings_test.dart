import 'dart:convert';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/database_helpers.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late List<String> warnings;

  setUp(() async {
    db = await openMemoryDatabase();
    warnings = [];
    settings = SettingsRepository(db, onWarning: warnings.add);
  });

  tearDown(() => db.close());

  test(
    'update preferences and last outcome have documented defaults',
    () async {
      final current = await settings.read();

      expect(current.updateSchedule, UpdateSchedule.daily);
      expect(current.effectiveUpdateSchedule, UpdateSchedule.daily);
      expect(current.lastUpdateCheckAt, isNull);
      expect(current.lastUpdateAttemptAt, isNull);
      expect(current.lastUpdateOutcome, isNull);
      expect(current.lastUpdateError, isNull);
    },
  );

  test('the schedule and outcome round-trip as JSON', () async {
    await settings.setUpdateSchedule(UpdateSchedule.off);
    await settings.recordUpdateOutcome(
      outcome: UpdateOutcome.failed,
      at: DateTime.utc(2026, 11, 27, 9, 30),
      error: 'manifest unreachable',
    );

    final current = await settings.read();
    expect(current.updateSchedule, UpdateSchedule.off);
    expect(current.autoUpdateEnabled, isFalse);
    expect(current.effectiveUpdateSchedule, UpdateSchedule.off);
    expect(current.lastUpdateOutcome, UpdateOutcome.failed);
    expect(current.lastUpdateCheckAt, isNull);
    expect(current.lastUpdateAttemptAt, DateTime.utc(2026, 11, 27, 9, 30));
    expect(current.lastUpdateError, 'manifest unreachable');

    final rows = await db.select(db.appSettings).get();
    final stored = {for (final row in rows) row.key: row.value};
    expect(jsonDecode(stored[AppSettingKeys.updateSchedule]!), 'off');
    expect(jsonDecode(stored[AppSettingKeys.lastUpdateOutcome]!), 'failed');
    expect(
      jsonDecode(stored[AppSettingKeys.lastUpdateAttemptAt]!),
      '2026-11-27T09:30:00.000Z',
    );
  });

  test('a successful check moves both success and attempt times', () async {
    await settings.recordUpdateOutcome(
      outcome: UpdateOutcome.failed,
      at: DateTime.utc(2026, 11, 27, 9),
      error: 'offline',
    );
    await settings.recordUpdateOutcome(
      outcome: UpdateOutcome.succeeded,
      at: DateTime.utc(2026, 11, 27, 10),
    );

    final current = await settings.read();
    expect(current.lastUpdateOutcome, UpdateOutcome.succeeded);
    expect(current.lastUpdateCheckAt, DateTime.utc(2026, 11, 27, 10));
    expect(current.lastUpdateAttemptAt, DateTime.utc(2026, 11, 27, 10));
    expect(current.lastUpdateError, isNull);
  });

  test('an unknown schedule or outcome falls back and warns', () async {
    await _putRaw(db, AppSettingKeys.updateSchedule, '"hourly"');
    await _putRaw(db, AppSettingKeys.lastUpdateOutcome, '"exploded"');
    await _putRaw(db, AppSettingKeys.lastUpdateCheckAt, '"yesterday"');

    final current = await settings.read();

    expect(current.updateSchedule, UpdateSchedule.daily);
    expect(current.lastUpdateOutcome, isNull);
    expect(current.lastUpdateCheckAt, isNull);
    expect(warnings, hasLength(3));
  });
}

Future<void> _putRaw(AppDatabase db, String key, String value) async {
  await db
      .into(db.appSettings)
      .insert(AppSettingsCompanion.insert(key: key, value: value));
}
