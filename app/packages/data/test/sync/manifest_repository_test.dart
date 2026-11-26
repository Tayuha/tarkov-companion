import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/database_helpers.dart';

const _bodyA = '{"manifestVersion":1,"mode":"regular"}';
const _bodyB = '{"manifestVersion":1,"mode":"regular","generatedAt":"x"}';

void main() {
  late AppDatabase db;
  late ManifestRepository repository;

  var now = DateTime.utc(2026, 11, 26, 12);
  DateTime clock() => now;

  setUp(() async {
    now = DateTime.utc(2026, 11, 26, 12);
    db = await openMemoryDatabase();
    repository = ManifestRepository(db, clock: clock);
  });

  tearDown(() => db.close());

  test('an unchecked mode has no cached manifest', () async {
    expect(await repository.read(GameMode.regular), isNull);
  });

  test('the first check inserts the raw body and both timestamps', () async {
    now = DateTime.utc(2026, 11, 26, 12, 30);

    final result = await repository.recordCheck(
      GameMode.regular,
      manifestJson: _bodyA,
      contentHash: ManifestRepository.hashBytes(_bodyA.codeUnits),
      etag: '"v1"',
      lastModified: 'Thu, 26 Nov 2026 10:30:24 GMT',
      generatedAt: '2026-11-26T10:32:14.883Z',
    );

    expect(result.outcome, ManifestRecordOutcome.inserted);
    expect(result.cache.lastCheckedAt, now);
    expect(result.cache.lastChangedAt, now);

    final cached = await repository.read(GameMode.regular);
    expect(cached, isNotNull);
    expect(cached!.mode, GameMode.regular);
    expect(cached.manifestJson, _bodyA);
    expect(cached.etag, '"v1"');
    expect(cached.lastModified, 'Thu, 26 Nov 2026 10:30:24 GMT');
    expect(cached.manifestGeneratedAt, '2026-11-26T10:32:14.883Z');
    expect(cached.contentHash, ManifestRepository.hashBytes(_bodyA.codeUnits));
    expect(cached.conditionalHeaders, {
      'if-none-match': '"v1"',
      'if-modified-since': 'Thu, 26 Nov 2026 10:30:24 GMT',
    });
  });

  test(
    'the same body with a new ETag updates metadata but not lastChangedAt',
    () async {
      final hash = ManifestRepository.hashBytes(_bodyA.codeUnits);
      await repository.recordCheck(
        GameMode.regular,
        manifestJson: _bodyA,
        contentHash: hash,
        etag: '"v1"',
      );
      final inserted = await repository.read(GameMode.regular);

      now = DateTime.utc(2026, 11, 26, 13);
      final result = await repository.recordCheck(
        GameMode.regular,
        manifestJson: _bodyA,
        contentHash: hash,
        etag: '"v2"',
        lastModified: 'Thu, 26 Nov 2026 12:00:00 GMT',
      );

      expect(result.outcome, ManifestRecordOutcome.unchanged);
      expect(result.cache.lastCheckedAt, now);
      expect(result.cache.lastChangedAt, inserted!.lastChangedAt);
      expect(result.cache.etag, '"v2"');
      expect(result.cache.lastModified, 'Thu, 26 Nov 2026 12:00:00 GMT');
    },
  );

  test('a different body replaces the cache and moves lastChangedAt', () async {
    await repository.recordCheck(
      GameMode.regular,
      manifestJson: _bodyA,
      contentHash: ManifestRepository.hashBytes(_bodyA.codeUnits),
      etag: '"v1"',
    );
    final inserted = await repository.read(GameMode.regular);

    now = DateTime.utc(2026, 11, 26, 14);
    final result = await repository.recordCheck(
      GameMode.regular,
      manifestJson: _bodyB,
      contentHash: ManifestRepository.hashBytes(_bodyB.codeUnits),
      etag: '"v2"',
    );

    expect(result.outcome, ManifestRecordOutcome.changed);
    expect(result.cache.manifestJson, _bodyB);
    expect(result.cache.lastCheckedAt, now);
    expect(result.cache.lastChangedAt, now);
    expect(result.cache.lastChangedAt, isNot(inserted!.lastChangedAt));
  });

  test('markChecked moves only lastCheckedAt', () async {
    await repository.recordCheck(
      GameMode.regular,
      manifestJson: _bodyA,
      contentHash: ManifestRepository.hashBytes(_bodyA.codeUnits),
      etag: '"v1"',
    );
    final before = await repository.read(GameMode.regular);

    now = DateTime.utc(2026, 11, 26, 15);
    final after = await repository.markChecked(GameMode.regular, now);

    expect(after!.lastCheckedAt, now);
    expect(after.lastChangedAt, before!.lastChangedAt);
    expect(after.contentHash, before.contentHash);
    expect(after.etag, before.etag);
    expect(after.manifestJson, before.manifestJson);
  });

  test(
    'markChecked on an uncached mode returns null and writes nothing',
    () async {
      expect(
        await repository.markChecked(GameMode.pve, DateTime.utc(2026, 11, 26)),
        isNull,
      );
      expect(await repository.read(GameMode.pve), isNull);
    },
  );

  test('each mode has its own cache row and validators', () async {
    await repository.recordCheck(
      GameMode.regular,
      manifestJson: _bodyA,
      contentHash: ManifestRepository.hashBytes(_bodyA.codeUnits),
      etag: '"regular"',
    );
    await repository.recordCheck(
      GameMode.pve,
      manifestJson: _bodyB,
      contentHash: ManifestRepository.hashBytes(_bodyB.codeUnits),
      etag: '"pve"',
    );

    expect((await repository.read(GameMode.regular))!.etag, '"regular"');
    expect((await repository.read(GameMode.pve))!.etag, '"pve"');
    expect((await repository.read(GameMode.pvpSeason)), isNull);
  });

  test('hashBytes is a stable SHA-256 over the exact bytes', () {
    expect(
      ManifestRepository.hashBytes(_bodyA.codeUnits),
      '0cc62df0156c0fa2ddc23152354e09499ff6f45aa82a260243d8ccc218775e69',
    );
  });
}
