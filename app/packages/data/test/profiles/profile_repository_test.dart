import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/database_helpers.dart';

const _activeKey = AppSettingKeys.activeProfileId;

void main() {
  final now = DateTime.utc(2026, 11, 26, 12);

  group('ProfileRepository (in-memory)', () {
    late AppDatabase db;
    late List<String> repairs;
    late ProfileRepository profiles;

    setUp(() async {
      db = await openMemoryDatabase();
      repairs = [];
      profiles = ProfileRepository(db, clock: () => now, onRepair: repairs.add);
    });

    tearDown(() => db.close());

    test('a fresh database has no profiles and no active profile', () async {
      expect(await profiles.list(), isEmpty);
      expect(await profiles.active(), isNull);
      expect(await db.select(db.profiles).get(), isEmpty);
      expect(await db.select(db.appSettings).get(), isEmpty);
    });

    test('first launch creates exactly one regular profile at level 1 and '
        'activates it; a second call is a no-op', () async {
      final first = await profiles.ensureFirstLaunch();

      expect(first.gameMode, GameMode.regular.wireValue);
      expect(first.playerLevel, 1);
      expect(first.createdAt.isAtSameMomentAs(now), isTrue);
      expect(first.updatedAt.isAtSameMomentAs(now), isTrue);
      expect(
        first.id,
        matches(RegExp(r'^profile-[0-9a-f]{32}$')),
        reason: 'the default generator is cryptographically random hex',
      );

      final rows = await profiles.list();
      expect(rows, hasLength(1));
      expect(rows.single, first);
      expect((await profiles.active())?.id, first.id);
      expect(await _storedActiveId(db), first.id);

      final second = await profiles.ensureFirstLaunch();

      expect(second, first, reason: 'timestamps and id must not change');
      expect(await profiles.list(), hasLength(1));
      expect(await _storedActiveId(db), first.id);
    });

    test('explicit PvE and season creation gives each mode a separate empty '
        'profile and leaves regular data untouched', () async {
      final regular = await profiles.ensureFirstLaunch();
      await (db.update(db.profiles)..where((row) => row.id.equals(regular.id)))
          .write(const ProfilesCompanion(playerLevel: Value(17)));
      await db
          .into(db.questProgress)
          .insert(
            QuestProgressCompanion.insert(
              profileId: regular.id,
              questId: 'quest-debut',
              state: 'completed',
              updatedAt: now,
            ),
          );

      final pve = await profiles.createForMode(GameMode.pve);
      expect(pve, isA<ProfileCreated>());
      expect(pve.created, isTrue);
      expect(pve.profile.gameMode, GameMode.pve.wireValue);
      expect(pve.profile.playerLevel, 1);
      expect(await _storedActiveId(db), pve.profile.id);

      final season = await profiles.createForMode(GameMode.pvpSeason);
      expect(season, isA<ProfileCreated>());
      expect(season.profile.gameMode, GameMode.pvpSeason.wireValue);
      expect(await _storedActiveId(db), season.profile.id);

      expect(await profiles.list(), hasLength(3));

      final regularAfter = await profiles.byId(regular.id);
      expect(regularAfter?.playerLevel, 17);
      expect(regularAfter?.updatedAt.isAtSameMomentAs(now), isTrue);
      final regularProgress = await (db.select(
        db.questProgress,
      )..where((row) => row.profileId.equals(regular.id))).get();
      expect(regularProgress, hasLength(1));
      for (final other in [pve.profile, season.profile]) {
        final progress = await (db.select(
          db.questProgress,
        )..where((row) => row.profileId.equals(other.id))).get();
        expect(progress, isEmpty, reason: '${other.gameMode} starts empty');
      }
    });

    test('creating an existing mode returns the existing profile and does not '
        'change the active profile', () async {
      final regular = await profiles.ensureFirstLaunch();
      final pve = await profiles.createForMode(GameMode.pve);
      await profiles.activate(regular.id);

      final duplicate = await profiles.createForMode(GameMode.pve);

      expect(duplicate, isA<ProfileAlreadyExists>());
      expect(duplicate.created, isFalse);
      expect(duplicate.profile, pve.profile);
      expect(await profiles.list(), hasLength(2));
      expect(await _storedActiveId(db), regular.id);
      expect((await profiles.active())?.id, regular.id);
    });

    test(
      'switching changes the active profile and only one is active',
      () async {
        final regular = await profiles.ensureFirstLaunch();
        final pve = await profiles.createForMode(GameMode.pve);
        expect((await profiles.active())?.id, pve.profile.id);

        final reactivated = await profiles.activate(regular.id);

        expect(reactivated, regular);
        expect((await profiles.active())?.id, regular.id);
        expect(await _storedActiveId(db), regular.id);
        final activeRows = await (db.select(
          db.appSettings,
        )..where((row) => row.key.equals(_activeKey))).get();
        expect(activeRows, hasLength(1));
        expect(jsonDecode(activeRows.single.value), regular.id);

        await profiles.activate(pve.profile.id);
        expect((await profiles.active())?.id, pve.profile.id);
        expect(await _storedActiveId(db), pve.profile.id);
        expect(
          await (db.select(
            db.appSettings,
          )..where((row) => row.key.equals(_activeKey))).get(),
          hasLength(1),
          reason:
              'the key is the primary key, so two active ids are impossible',
        );
      },
    );

    test('activating a missing id fails with a typed error and keeps the '
        'previous active profile', () async {
      final regular = await profiles.ensureFirstLaunch();
      final pve = await profiles.createForMode(GameMode.pve);

      await expectLater(
        profiles.activate('profile-missing'),
        throwsA(
          isA<ProfileNotFoundError>().having(
            (error) => error.profileId,
            'profileId',
            'profile-missing',
          ),
        ),
      );

      expect((await profiles.active())?.id, pve.profile.id);
      expect(await _storedActiveId(db), pve.profile.id);
      expect(await profiles.byId(regular.id), regular);
    });

    test('a missing active id repairs to the regular profile and rewrites the '
        'setting', () async {
      final regular = await profiles.ensureFirstLaunch();
      await (db.delete(
        db.appSettings,
      )..where((row) => row.key.equals(_activeKey))).go();

      final resolved = await profiles.active();

      expect(resolved?.id, regular.id);
      expect(await _storedActiveId(db), regular.id);
      expect(repairs.single, contains(regular.id));
    });

    test(
      'a dangling active id repairs to the regular profile even when another '
      'mode is newer',
      () async {
        final regular = await profiles.ensureFirstLaunch();
        final pve = await profiles.createForMode(GameMode.pve);
        await _putRawActive(db, '"profile-deleted"');

        final resolved = await profiles.active();

        expect(resolved?.id, regular.id);
        expect(resolved?.id, isNot(pve.profile.id));
        expect(await _storedActiveId(db), regular.id);
        expect(repairs.single, contains('profile-deleted'));
      },
    );

    test('an unreadable active value repairs without throwing', () async {
      final regular = await profiles.ensureFirstLaunch();
      await profiles.createForMode(GameMode.pve);
      await _putRawActive(db, '{not json');

      final resolved = await profiles.active();

      expect(resolved?.id, regular.id);
      expect(await _storedActiveId(db), regular.id);
      expect(repairs, hasLength(1));
    });

    test(
      'without a regular profile the oldest profile is the fallback',
      () async {
        var tick = now;
        final sequenced = ProfileRepository(
          db,
          clock: () => tick = tick.add(const Duration(minutes: 1)),
          onRepair: repairs.add,
        );

        final older = await sequenced.createForMode(GameMode.pve);
        final newer = await sequenced.createForMode(GameMode.pvpSeason);
        await (db.delete(
          db.appSettings,
        )..where((row) => row.key.equals(_activeKey))).go();

        final resolved = await sequenced.active();

        expect(resolved?.id, older.profile.id);
        expect(resolved?.id, isNot(newer.profile.id));
        expect(await _storedActiveId(db), older.profile.id);
      },
    );

    test('the oldest fallback breaks a createdAt tie by id', () async {
      final sequenced = ProfileRepository(
        db,
        clock: () => now,
        idGenerator: _SequenceIds(['profile-b', 'profile-a']).next,
        onRepair: repairs.add,
      );

      final pve = await sequenced.createForMode(GameMode.pve);
      final season = await sequenced.createForMode(GameMode.pvpSeason);
      await (db.delete(
        db.appSettings,
      )..where((row) => row.key.equals(_activeKey))).go();

      final resolved = await sequenced.active();

      expect(pve.profile.id, 'profile-b');
      expect(season.profile.id, 'profile-a');
      expect(
        resolved?.id,
        'profile-a',
        reason: 'same createdAt, lower id first',
      );
    });

    test(
      'ids are unique and every timestamp comes from the injected clock',
      () async {
        final ids = _SequenceIds(['profile-c', 'profile-a', 'profile-b']);
        final fixed = ProfileRepository(
          db,
          clock: () => now,
          idGenerator: ids.next,
        );

        final regular = await fixed.createForMode(GameMode.regular);
        final pve = await fixed.createForMode(GameMode.pve);
        final season = await fixed.createForMode(GameMode.pvpSeason);

        final all = await fixed.list();
        expect(all.map((profile) => profile.id), [
          'profile-a',
          'profile-b',
          'profile-c',
        ]);
        expect(
          all.map((profile) => profile.id).toSet(),
          hasLength(3),
          reason: 'profile ids must be unique',
        );
        for (final profile in all) {
          expect(profile.createdAt.isAtSameMomentAs(now), isTrue);
          expect(profile.updatedAt.isAtSameMomentAs(now), isTrue);
        }
        expect(
          [regular.profile.id, pve.profile.id, season.profile.id],
          ['profile-c', 'profile-a', 'profile-b'],
        );
        expect(await fixed.byId('profile-missing'), isNull);
      },
    );

    test('an injected generator that repeats an id is retried', () async {
      final ids = _SequenceIds(['profile-dup', 'profile-dup', 'profile-ok']);
      final retrying = ProfileRepository(
        db,
        clock: () => now,
        idGenerator: ids.next,
      );

      final first = await retrying.createForMode(GameMode.regular);
      final second = await retrying.createForMode(GameMode.pve);

      expect(first.profile.id, 'profile-dup');
      expect(second.profile.id, 'profile-ok');
      expect(await retrying.list(), hasLength(2));
    });
  });

  group('ProfileRepository (file-backed)', () {
    test('the active profile and profiles survive a database reopen', () async {
      final directory = createTemporaryDirectory(addTearDown);
      final path = '${directory.path}/profiles.sqlite';
      final now = DateTime.utc(2026, 11, 26, 12);

      final first = AppDatabase.atPath(path);
      final firstRepo = ProfileRepository(first, clock: () => now);
      final regular = await firstRepo.ensureFirstLaunch();
      final pve = await firstRepo.createForMode(GameMode.pve);
      await firstRepo.activate(regular.id);
      await first.close();

      final second = AppDatabase.atPath(path);
      addTearDown(second.close);
      final secondRepo = ProfileRepository(second, clock: () => now);

      expect((await secondRepo.active())?.id, regular.id);
      expect(
        (await secondRepo.list()).map((profile) => profile.id),
        unorderedEquals([regular.id, pve.profile.id]),
      );

      final ensured = await secondRepo.ensureFirstLaunch();

      expect(ensured, regular, reason: 'an existing profile is not recreated');
      expect(await secondRepo.list(), hasLength(2));
      expect(await secondRepo.active(), regular);
    });
  });
}

/// Reads the active profile id, failing when the setting is absent or invalid.
Future<String?> _storedActiveId(AppDatabase db) async {
  final row = await (db.select(
    db.appSettings,
  )..where((row) => row.key.equals(_activeKey))).getSingleOrNull();
  if (row == null) {
    return null;
  }
  final value = jsonDecode(row.value);
  return value is String ? value : null;
}

Future<void> _putRawActive(AppDatabase db, String rawValue) async {
  await db
      .into(db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion(key: Value(_activeKey), value: Value(rawValue)),
      );
}

/// A deterministic id generator that fails when the test runs out of ids.
final class _SequenceIds {
  _SequenceIds(this._values);

  final List<String> _values;
  int _index = 0;

  String next() {
    if (_index >= _values.length) {
      throw StateError('The test id sequence is exhausted.');
    }
    return _values[_index++];
  }
}
