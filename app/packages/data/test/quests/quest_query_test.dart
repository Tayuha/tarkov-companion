import 'dart:convert';
import 'dart:io';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/bundle_fixture.dart';
import '../support/database_helpers.dart';
import '../support/quest_fixture.dart';

/// The committed fixture ids used by the assertions below.
const _debut = '5936d90786f7742b1420ba5b';
const _backgroundCheck = '5936da9e86f7742d65037edf';
const _shootoutPicnic = '59674cd986f7744ab26e32f2';
const _postmanPart1 = '59675ea386f77414b32bded2';
const _antiqueEnthusiast = '5c1141f386f77430ff393792';

/// Prapor, the trader of the two Punisher quests.
const _prapor = '54cb50c76803fa8b248b4571';

/// Customs, one of the maps the fixture quests point at.
const _customs = '56f40101d2720b2a4d8b45d6';

List<String> _tokens(String text) => RegExp(
  r'[\p{L}\p{N}]+',
  unicode: true,
).allMatches(text.toLowerCase()).map((match) => match[0]!).toList();

/// Approximates the query contract for a fixture record: every query token must
/// be a substring of the bundle's normalized name.
bool _matchesText(Map<String, Object?> record, String text) {
  final normalized = (record['normalizedName'] as String).toLowerCase();
  return _tokens(text).every(normalized.contains);
}

Set<String> _ids(Iterable<QuestSummary> quests) => {
  for (final quest in quests) quest.id,
};

/// Asserts nulls are last in both directions and the non-null prefix is sorted.
void _expectSorted<T extends Comparable<dynamic>>(
  List<T?> values, {
  required bool descending,
}) {
  final firstNull = values.indexOf(null);
  if (firstNull != -1) {
    expect(
      values.skip(firstNull).every((value) => value == null),
      isTrue,
      reason: 'a non-null appeared after a null: $values',
    );
  }

  final present = values.whereType<T>().toList();
  for (var index = 1; index < present.length; index++) {
    final comparison = present[index - 1].compareTo(present[index]);
    if (descending) {
      expect(
        comparison,
        greaterThanOrEqualTo(0),
        reason: 'value $index breaks descending order: $present',
      );
    } else {
      expect(
        comparison,
        lessThanOrEqualTo(0),
        reason: 'value $index breaks ascending order: $present',
      );
    }
  }
}

void main() {
  late AppDatabase db;
  late QuestRepository repository;
  late Directory temporary;
  late List<Map<String, Object?>> fixture;

  setUpAll(() async {
    db = await openMemoryDatabase();
    temporary = Directory.systemTemp.createTempSync('tarkov_quests_');
    await ingestNormalizedTasksFixture(db, temporary);
    repository = QuestRepository(db);
    fixture = await readNormalizedTasksFixture();
  });

  tearDownAll(() async {
    await db.close();
    if (temporary.existsSync()) {
      temporary.deleteSync(recursive: true);
    }
  });

  Future<QuestPage> query(
    QuestFilters filters, {
    QuestSort? sort,
    String? profileId,
    int limit = QuestQuery.maxLimit,
    int offset = 0,
  }) => repository.query(
    QuestQuery(
      filters: filters,
      sort: sort,
      limit: limit,
      offset: offset,
      profileId: profileId,
    ),
  );

  Set<String> expected(bool Function(Map<String, Object?> record) matches) => {
    for (final record in fixture)
      if (matches(record)) record['id']! as String,
  };

  group('published fixture', () {
    test('the pipeline corpus is what the quest queries read', () async {
      expect(fixture, hasLength(80));

      final page = await query(const QuestFilters());
      expect(page.total, 80);
      expect(page.quests, hasLength(80));
      expect(_ids(page.quests), expected((_) => true));

      final debut = page.quests.singleWhere((quest) => quest.id == _debut);
      expect(debut.name, 'Debut');
      expect(debut.traderId, _prapor);
      expect(debut.mapId, isNull);
      expect(debut.minPlayerLevel, 0);
      expect(debut.experience, 3000);
      expect(debut.kappaRequired, isFalse);
      expect(debut.progressState, QuestProgressState.notStarted);

      final postman = page.quests.singleWhere(
        (quest) => quest.id == _postmanPart1,
      );
      expect(postman.kappaRequired, isTrue);
      expect(postman.experience, 10000);

      // Every summary is typed: no raw drift row, no raw state string.
      for (final quest in page.quests) {
        expect(quest.name, isNotEmpty, reason: quest.id);
        expect(quest.progressState, QuestProgressState.notStarted);
      }
    });

    test('the total count ignores pagination', () async {
      expect(await repository.count(const QuestQuery()), 80);
      expect(
        await repository.count(
          const QuestQuery(filters: QuestFilters(traderId: _prapor)),
        ),
        15,
      );
    });
  });

  group('each filter alone', () {
    test('text search', () async {
      final page = await query(const QuestFilters(text: 'punisher'));
      final expectedIds = expected(
        (record) => _matchesText(record, 'punisher'),
      );

      expect(expectedIds, hasLength(2));
      expect(_ids(page.quests), expectedIds);
      expect(page.total, 2);
    });

    test('text tokens are ANDed, not a contiguous phrase', () async {
      final page = await query(const QuestFilters(text: 'part 1'));
      final expectedIds = expected((record) => _matchesText(record, 'part 1'));

      expect(expectedIds, hasLength(5));
      expect(_ids(page.quests), expectedIds);
    });

    test('text search is case-insensitive', () async {
      final page = await query(const QuestFilters(text: 'DEBUT'));
      expect(_ids(page.quests), {_debut});
    });

    test('a text with no letter/digit token matches nothing', () async {
      final page = await query(const QuestFilters(text: '---'));
      expect(page.total, 0);
      expect(page.isEmpty, isTrue);
      expect(page.quests, isEmpty);
    });

    test('trader', () async {
      final page = await query(const QuestFilters(traderId: _prapor));
      final expectedIds = expected((record) => record['traderId'] == _prapor);

      expect(expectedIds, hasLength(15));
      expect(_ids(page.quests), expectedIds);
      expect(page.quests.every((quest) => quest.traderId == _prapor), isTrue);
    });

    test('map', () async {
      final page = await query(const QuestFilters(mapId: _customs));
      final expectedIds = expected((record) => record['mapId'] == _customs);

      expect(expectedIds, hasLength(10));
      expect(_ids(page.quests), expectedIds);
      expect(page.quests.every((quest) => quest.mapId == _customs), isTrue);
      expect(
        page.quests.any((quest) => quest.mapId == null),
        isFalse,
        reason: 'a map filter never returns a quest without a map',
      );
    });

    test('exact minimum player level', () async {
      final page = await query(const QuestFilters(minPlayerLevel: 42));
      final expectedIds = expected((record) => record['minPlayerLevel'] == 42);

      expect(expectedIds, hasLength(5));
      expect(_ids(page.quests), expectedIds);
      expect(_ids(page.quests), contains(_antiqueEnthusiast));
      expect(page.quests.every((quest) => quest.minPlayerLevel == 42), isTrue);
    });

    test('at-or-below minimum player level', () async {
      final page = await query(const QuestFilters(maxPlayerLevel: 9));
      final expectedIds = expected(
        (record) => (record['minPlayerLevel']! as int) <= 9,
      );

      expect(expectedIds, hasLength(49));
      expect(_ids(page.quests), expectedIds);
      expect(page.quests.every((quest) => quest.minPlayerLevel! <= 9), isTrue);
    });

    test(
      'an exact and an at-or-below bound at the same level intersect',
      () async {
        final page = await query(
          const QuestFilters(minPlayerLevel: 42, maxPlayerLevel: 42),
        );
        expect(page.total, 5);
        expect(
          page.quests.every((quest) => quest.minPlayerLevel == 42),
          isTrue,
        );
      },
    );

    test('a blank filter is no filter', () async {
      final page = await query(
        const QuestFilters(text: '   ', traderId: ' ', mapId: ''),
      );
      expect(page.total, 80);
      expect(const QuestFilters().isEmpty, isTrue);
      expect(
        const QuestFilters(state: QuestProgressState.notStarted).isNotEmpty,
        isTrue,
      );
    });
  });

  group('combined filters', () {
    test('text + trader', () async {
      final page = await query(
        const QuestFilters(text: 'punisher', traderId: _prapor),
      );
      expect(_ids(page.quests), {
        '59c512ad86f7741f0d09de9b',
        '59c50a9e86f7745fef66f4ff',
      });
    });

    test('trader + map', () async {
      final page = await query(
        const QuestFilters(traderId: _prapor, mapId: _customs),
      );
      expect(_ids(page.quests), {
        _backgroundCheck,
        '5967725e86f774601a446662',
        '59c512ad86f7741f0d09de9b',
      });
    });

    test('trader + at-or-below level', () async {
      final page = await query(
        const QuestFilters(traderId: _prapor, maxPlayerLevel: 9),
      );
      final expectedIds = expected(
        (record) =>
            record['traderId'] == _prapor &&
            (record['minPlayerLevel']! as int) <= 9,
      );

      expect(expectedIds, hasLength(12));
      expect(_ids(page.quests), expectedIds);
    });

    test('map + exact level', () async {
      final page = await query(
        const QuestFilters(mapId: _customs, minPlayerLevel: 0),
      );
      final expectedIds = expected(
        (record) =>
            record['mapId'] == _customs && record['minPlayerLevel'] == 0,
      );

      expect(expectedIds, hasLength(8));
      expect(_ids(page.quests), expectedIds);
    });

    test('search + trader + map + level bound', () async {
      final page = await query(
        const QuestFilters(
          text: 'punisher',
          traderId: _prapor,
          mapId: _customs,
          minPlayerLevel: 0,
          maxPlayerLevel: 9,
        ),
      );
      expect(_ids(page.quests), {'59c512ad86f7741f0d09de9b'});
    });

    test('contradictory level bounds match nothing', () async {
      final page = await query(
        const QuestFilters(minPlayerLevel: 42, maxPlayerLevel: 9),
      );
      expect(page.total, 0);
      expect(page.isEmpty, isTrue);
    });

    test('clearing one filter keeps the others', () async {
      const filters = QuestFilters(text: 'punisher', traderId: _prapor);
      expect((await query(filters)).total, 2);

      final withoutTrader = await query(filters.withTrader(null));
      expect(withoutTrader.total, 2);
      expect(
        _ids(withoutTrader.quests),
        containsAll(<String>[
          '59c512ad86f7741f0d09de9b',
          '59c50a9e86f7745fef66f4ff',
        ]),
      );

      final withoutText = await query(filters.withText(null));
      expect(withoutText.total, 15);
      expect(
        withoutText.quests.every((quest) => quest.traderId == _prapor),
        isTrue,
      );

      expect((await query(filters.clear())).total, 80);
    });

    test('filters cannot resurrect rows the search rejected', () async {
      final page = await query(
        const QuestFilters(text: 'zzzz', traderId: _prapor, mapId: _customs),
      );
      expect(page.total, 0);
    });
  });

  group('sorting', () {
    final normalizedById = <String, String>{};

    setUpAll(() {
      for (final record in fixture) {
        normalizedById[record['id']! as String] =
            record['normalizedName']! as String;
      }
    });

    /// Asserts equal primary values keep name (then id) ascending in both
    /// directions.
    void expectStableTies(
      List<QuestSummary> quests,
      Object? Function(QuestSummary) primary,
    ) {
      for (var index = 1; index < quests.length; index++) {
        final previous = quests[index - 1];
        final current = quests[index];
        final value = primary(previous);
        if (value == null || value != primary(current)) {
          continue;
        }
        final previousName = normalizedById[previous.id]!;
        final currentName = normalizedById[current.id]!;
        final byName = previousName.compareTo(currentName);
        expect(
          byName,
          lessThanOrEqualTo(0),
          reason: 'ties must stay name-ascending: $previousName / $currentName',
        );
        if (byName == 0) {
          expect(previous.id.compareTo(current.id), lessThanOrEqualTo(0));
        }
      }
    }

    test('name both directions', () async {
      final ascending = await query(
        const QuestFilters(),
        sort: const QuestSort(QuestSortField.name),
      );
      final descending = await query(
        const QuestFilters(),
        sort: const QuestSort(QuestSortField.name, descending: true),
      );

      final expectedNames = [
        for (final record
            in [...fixture]..sort(
              (left, right) => (left['normalizedName']! as String).compareTo(
                right['normalizedName']! as String,
              ),
            ))
          record['name']! as String,
      ];

      expect([for (final quest in ascending.quests) quest.name], expectedNames);
      expect([
        for (final quest in descending.quests) quest.name,
      ], expectedNames.reversed.toList());
    });

    test('minimum player level: both directions, ties and nulls', () async {
      final ascending = await query(
        const QuestFilters(),
        sort: const QuestSort(QuestSortField.minPlayerLevel),
      );
      final descending = await query(
        const QuestFilters(),
        sort: const QuestSort(QuestSortField.minPlayerLevel, descending: true),
      );

      _expectSorted([
        for (final quest in ascending.quests) quest.minPlayerLevel,
      ], descending: false);
      _expectSorted([
        for (final quest in descending.quests) quest.minPlayerLevel,
      ], descending: true);
      expectStableTies(ascending.quests, (quest) => quest.minPlayerLevel);
      expectStableTies(descending.quests, (quest) => quest.minPlayerLevel);

      final ascendingPresent = [
        for (final quest in ascending.quests) ?quest.minPlayerLevel,
      ];
      expect([
        for (final quest in descending.quests) ?quest.minPlayerLevel,
      ], ascendingPresent.reversed.toList());
    });

    test('trader id: both directions, ties and nulls', () async {
      final ascending = await query(
        const QuestFilters(),
        sort: const QuestSort(QuestSortField.traderId),
      );
      final descending = await query(
        const QuestFilters(),
        sort: const QuestSort(QuestSortField.traderId, descending: true),
      );

      _expectSorted([
        for (final quest in ascending.quests) quest.traderId,
      ], descending: false);
      _expectSorted([
        for (final quest in descending.quests) quest.traderId,
      ], descending: true);
      expectStableTies(ascending.quests, (quest) => quest.traderId);
      expectStableTies(descending.quests, (quest) => quest.traderId);
    });

    test('map id: both directions with nulls last', () async {
      final ascending = await query(
        const QuestFilters(),
        sort: const QuestSort(QuestSortField.mapId),
      );
      final descending = await query(
        const QuestFilters(),
        sort: const QuestSort(QuestSortField.mapId, descending: true),
      );

      _expectSorted([
        for (final quest in ascending.quests) quest.mapId,
      ], descending: false);
      _expectSorted([
        for (final quest in descending.quests) quest.mapId,
      ], descending: true);
      expectStableTies(ascending.quests, (quest) => quest.mapId);
      expectStableTies(descending.quests, (quest) => quest.mapId);

      final withMap = expected((record) => record['mapId'] != null).length;
      expect(ascending.quests.last.mapId, isNull);
      expect(descending.quests.last.mapId, isNull);
      expect(
        ascending.quests.take(withMap).where((quest) => quest.mapId == null),
        isEmpty,
        reason: 'the $withMap quests with a map sort before the nulls',
      );
      expect(
        descending.quests.take(withMap).where((quest) => quest.mapId == null),
        isEmpty,
        reason: 'nulls stay last in descending order too',
      );
    });

    test('an explicit sort wins over the default', () async {
      final page = await query(
        const QuestFilters(text: 'the'),
        sort: const QuestSort(QuestSortField.minPlayerLevel, descending: true),
      );
      expect(page.quests, isNotEmpty);
      _expectSorted([
        for (final quest in page.quests) quest.minPlayerLevel,
      ], descending: true);
    });

    test('QuestSort.reversed flips only the direction', () {
      const sort = QuestSort(QuestSortField.mapId);
      expect(
        sort.reversed(),
        const QuestSort(QuestSortField.mapId, descending: true),
      );
      expect(sort.reversed().reversed(), sort);
    });
  });

  group('pagination', () {
    test('pages cover every row without duplicates', () async {
      final seen = <String>[];
      var offset = 0;
      var total = -1;

      while (true) {
        final page = await repository.query(
          QuestQuery(
            sort: const QuestSort(QuestSortField.minPlayerLevel),
            limit: 17,
            offset: offset,
          ),
        );
        total = page.total;
        seen.addAll(_ids(page.quests));
        if (!page.hasMore) {
          break;
        }
        expect(page.quests, hasLength(17));
        offset = page.nextOffset;
      }

      expect(total, 80);
      expect(seen, hasLength(80));
      expect(seen.toSet(), hasLength(80));
    });

    test('limit and offset boundaries', () async {
      final first = await repository.query(const QuestQuery(limit: 10));
      expect(first.quests, hasLength(10));
      expect(first.total, 80);
      expect(first.hasMore, isTrue);

      final last = await repository.query(
        const QuestQuery(limit: 10, offset: 75),
      );
      expect(last.quests, hasLength(5));
      expect(last.hasMore, isFalse);
      expect(last.nextOffset, 80);

      final pastEnd = await repository.query(
        const QuestQuery(limit: 10, offset: 80),
      );
      expect(pastEnd.total, 80);
      expect(pastEnd.quests, isEmpty);
      expect(pastEnd.isPageEmpty, isTrue);
      expect(pastEnd.isEmpty, isFalse, reason: 'the filters still match 80');
      expect(pastEnd.hasMore, isFalse);

      final defaultPage = await repository.query(const QuestQuery());
      expect(defaultPage.quests, hasLength(QuestQuery.defaultLimit));
      expect(defaultPage.limit, QuestQuery.defaultLimit);
    });

    test('invalid pagination is clamped deterministically', () async {
      final zero = await repository.query(
        const QuestQuery(limit: 0, offset: -7),
      );
      expect(zero.limit, 1);
      expect(zero.offset, 0);
      expect(zero.quests, hasLength(1));

      final negative = await repository.query(
        const QuestQuery(limit: -3, offset: -1),
      );
      expect(negative.limit, 1);
      expect(negative.offset, 0);
      expect(negative.quests, hasLength(1));

      final huge = await repository.query(
        const QuestQuery(limit: 100000, offset: 0),
      );
      expect(huge.limit, QuestQuery.maxLimit);
      expect(huge.quests, hasLength(80));
    });

    test('no match returns an explicit empty page', () async {
      final byText = await repository.query(
        const QuestQuery(filters: QuestFilters(text: 'zzzz')),
      );
      expect(byText.total, 0);
      expect(byText.isEmpty, isTrue);
      expect(byText.quests, isEmpty);

      final byTrader = await repository.query(
        const QuestQuery(filters: QuestFilters(traderId: 'no-such-id')),
      );
      expect(byTrader.isEmpty, isTrue);

      final punctuation = await repository.query(
        const QuestQuery(filters: QuestFilters(text: '---')),
      );
      expect(punctuation.isEmpty, isTrue);
      expect(punctuation.quests, isEmpty);
    });

    test('count matches the page total and ignores the page window', () async {
      const query = QuestQuery(
        filters: QuestFilters(traderId: _prapor),
        limit: 3,
        offset: 12,
      );
      final page = await repository.query(query);
      expect(page.total, 15);
      expect(page.quests, hasLength(3));
      expect(await repository.count(query), 15);
    });
  });

  group('profile-scoped progress state', () {
    final now = DateTime.utc(2026, 11, 26, 12);

    Future<void> setState(
      String profileId,
      String questId,
      String state,
    ) async {
      await db
          .into(db.questProgress)
          .insert(
            QuestProgressCompanion.insert(
              profileId: profileId,
              questId: questId,
              state: state,
              updatedAt: now,
            ),
          );
    }

    setUp(() async {
      await db.delete(db.questProgress).go();
      await db.delete(db.profiles).go();

      await insertProfile(db, id: 'profile-a', gameMode: 'regular', now: now);
      await insertProfile(db, id: 'profile-b', gameMode: 'pve', now: now);

      // The same quests have intentionally different states per profile.
      await setState('profile-a', _debut, 'completed');
      await setState('profile-a', _backgroundCheck, 'in-progress');
      await setState('profile-a', _shootoutPicnic, 'failed');
      await setState('profile-b', _debut, 'failed');
      await setState('profile-b', _backgroundCheck, 'completed');

      // An unexpected stored value must read as "no progress".
      await setState('profile-a', _postmanPart1, 'paused');
    });

    test(
      'summaries report the requested profile state; no row is notStarted',
      () async {
        final profileA = await query(
          const QuestFilters(),
          profileId: 'profile-a',
        );
        final profileB = await query(
          const QuestFilters(),
          profileId: 'profile-b',
        );

        QuestSummary find(QuestPage page, String id) =>
            page.quests.singleWhere((quest) => quest.id == id);

        expect(
          find(profileA, _debut).progressState,
          QuestProgressState.completed,
        );
        expect(
          find(profileA, _backgroundCheck).progressState,
          QuestProgressState.inProgress,
        );
        expect(
          find(profileA, _shootoutPicnic).progressState,
          QuestProgressState.failed,
        );
        expect(
          find(profileA, _postmanPart1).progressState,
          QuestProgressState.notStarted,
          reason: 'an unrecognized stored state must not claim progress',
        );
        expect(
          find(profileA, _antiqueEnthusiast).progressState,
          QuestProgressState.notStarted,
          reason: 'a quest with no progress row is not started',
        );

        expect(find(profileB, _debut).progressState, QuestProgressState.failed);
        expect(
          find(profileB, _backgroundCheck).progressState,
          QuestProgressState.completed,
        );
        expect(
          find(profileB, _shootoutPicnic).progressState,
          QuestProgressState.notStarted,
        );
      },
    );

    test('state filters are scoped to one profile', () async {
      final completedA = await query(
        const QuestFilters(state: QuestProgressState.completed),
        profileId: 'profile-a',
      );
      expect(_ids(completedA.quests), {_debut});

      final inProgressA = await query(
        const QuestFilters(state: QuestProgressState.inProgress),
        profileId: 'profile-a',
      );
      expect(_ids(inProgressA.quests), {_backgroundCheck});

      final failedA = await query(
        const QuestFilters(state: QuestProgressState.failed),
        profileId: 'profile-a',
      );
      expect(_ids(failedA.quests), {_shootoutPicnic});

      final completedB = await query(
        const QuestFilters(state: QuestProgressState.completed),
        profileId: 'profile-b',
      );
      expect(_ids(completedB.quests), {_backgroundCheck});

      final failedB = await query(
        const QuestFilters(state: QuestProgressState.failed),
        profileId: 'profile-b',
      );
      expect(_ids(failedB.quests), {_debut});

      final inProgressB = await query(
        const QuestFilters(state: QuestProgressState.inProgress),
        profileId: 'profile-b',
      );
      expect(inProgressB.total, 0);
    });

    test('notStarted means no row for that profile', () async {
      final notStartedA = await query(
        const QuestFilters(state: QuestProgressState.notStarted),
        profileId: 'profile-a',
      );
      expect(notStartedA.total, 77);
      expect(_ids(notStartedA.quests), isNot(contains(_debut)));
      expect(_ids(notStartedA.quests), isNot(contains(_backgroundCheck)));
      expect(_ids(notStartedA.quests), isNot(contains(_shootoutPicnic)));
      expect(
        _ids(notStartedA.quests),
        contains(_postmanPart1),
        reason: 'the unrecognized state counts as not started',
      );

      final notStartedB = await query(
        const QuestFilters(state: QuestProgressState.notStarted),
        profileId: 'profile-b',
      );
      expect(notStartedB.total, 78);
      expect(_ids(notStartedB.quests), isNot(contains(_debut)));
      expect(_ids(notStartedB.quests), isNot(contains(_backgroundCheck)));
      expect(_ids(notStartedB.quests), contains(_shootoutPicnic));
    });

    test('without a profile only notStarted can match', () async {
      final all = await query(const QuestFilters());
      expect(
        all.quests.every(
          (quest) => quest.progressState == QuestProgressState.notStarted,
        ),
        isTrue,
      );

      final completed = await query(
        const QuestFilters(state: QuestProgressState.completed),
      );
      expect(completed.total, 0);

      final failed = await query(
        const QuestFilters(state: QuestProgressState.failed),
      );
      expect(failed.total, 0);

      final notStarted = await query(
        const QuestFilters(state: QuestProgressState.notStarted),
      );
      expect(notStarted.total, 80);
    });

    test('state intersects with the other filters', () async {
      final byTrader = await query(
        const QuestFilters(
          state: QuestProgressState.completed,
          traderId: _prapor,
        ),
        profileId: 'profile-a',
      );
      expect(_ids(byTrader.quests), {_debut});

      final byText = await query(
        const QuestFilters(text: 'debut', state: QuestProgressState.completed),
        profileId: 'profile-a',
      );
      expect(_ids(byText.quests), {_debut});

      final byMap = await query(
        const QuestFilters(
          state: QuestProgressState.inProgress,
          mapId: _customs,
        ),
        profileId: 'profile-a',
      );
      expect(_ids(byMap.quests), {_backgroundCheck});

      final impossible = await query(
        const QuestFilters(
          state: QuestProgressState.completed,
          mapId: 'no-such-map',
        ),
        profileId: 'profile-a',
      );
      expect(impossible.total, 0);
    });

    test('clearing the state filter keeps the profile scope', () async {
      const filters = QuestFilters(
        state: QuestProgressState.completed,
        traderId: _prapor,
      );
      final narrowed = await query(filters, profileId: 'profile-a');
      expect(narrowed.total, 1);

      final cleared = await query(
        filters.withState(null),
        profileId: 'profile-a',
      );
      expect(cleared.total, 15);
      expect(
        cleared.quests.singleWhere((quest) => quest.id == _debut).progressState,
        QuestProgressState.completed,
      );
    });
  });

  group('search folding, nulls and ties on synthetic data', () {
    late AppDatabase syntheticDb;
    late QuestRepository syntheticRepository;
    late Directory syntheticDirectory;

    setUp(() async {
      syntheticDb = await openMemoryDatabase();
      syntheticDirectory = createTemporaryDirectory(addTearDown);
      syntheticRepository = QuestRepository(syntheticDb);
    });

    tearDown(() => syntheticDb.close());

    Future<void> ingest(List<Map<String, Object?>> tasks) async {
      final dataset = writeSyntheticDataset(
        syntheticDirectory,
        DatasetKind.tasks,
        [for (final task in tasks) jsonEncode(task)],
      );
      await DatasetIngestor(syntheticDb).ingest(
        mode: GameMode.regular,
        dataset: dataset.dataset,
        compressedFile: dataset.file,
      );
    }

    test(
      'case and diacritics fold through the query and the name sort',
      () async {
        await ingest([
          {
            'id': 'quest-cafe',
            'kind': 'task',
            'name': 'Café Crème',
            'normalizedName': 'cafe-creme',
            'traderId': 'trader-1',
            'mapId': null,
            'minPlayerLevel': 3,
            'experience': 100,
            'kappaRequired': false,
          },
          {
            'id': 'quest-eclair',
            'kind': 'task',
            'name': 'Éclair',
            'normalizedName': 'eclair',
            'traderId': 'trader-1',
            'mapId': null,
            'minPlayerLevel': 4,
            'experience': 200,
            'kappaRequired': false,
          },
          {
            'id': 'quest-zulu',
            'kind': 'task',
            'name': 'Zulu',
            'normalizedName': 'zulu',
            'traderId': 'trader-2',
            'mapId': null,
            'minPlayerLevel': 5,
            'experience': 300,
            'kappaRequired': false,
          },
          // A hand-written record without the bundle's search key falls back to
          // an ASCII case-insensitive match on the name.
          {
            'id': 'quest-legacy',
            'kind': 'task',
            'name': 'Legacy Quest',
            'traderId': 'trader-2',
          },
        ]);

        Future<Set<String>> search(String text) async => _ids(
          (await syntheticRepository.query(
            QuestQuery(filters: QuestFilters(text: text)),
          )).quests,
        );

        expect(await search('cafe'), {'quest-cafe'});
        expect(await search('CAFÉ'), {'quest-cafe'});
        expect(await search('creme'), {'quest-cafe'});
        expect(await search('café creme'), {'quest-cafe'});
        expect(await search('ÉCLAIR'), {'quest-eclair'});
        expect(await search('LEGACY'), {'quest-legacy'});

        final ascending = await syntheticRepository.query(
          const QuestQuery(sort: QuestSort(QuestSortField.name)),
        );
        expect(
          [for (final quest in ascending.quests) quest.id],
          ['quest-cafe', 'quest-eclair', 'quest-legacy', 'quest-zulu'],
        );

        final descending = await syntheticRepository.query(
          const QuestQuery(
            sort: QuestSort(QuestSortField.name, descending: true),
          ),
        );
        expect(
          [for (final quest in descending.quests) quest.id],
          ['quest-zulu', 'quest-legacy', 'quest-eclair', 'quest-cafe'],
        );
      },
    );

    test('nulls stay last and ties stay stable for every sort field', () async {
      await ingest([
        {
          'id': 'quest-null',
          'kind': 'task',
          'name': 'Zulu Null',
          'normalizedName': 'zulu-null',
          'traderId': null,
          'mapId': null,
          'minPlayerLevel': null,
          'experience': null,
          'kappaRequired': false,
        },
        {
          'id': 'quest-alpha',
          'kind': 'task',
          'name': 'Alpha',
          'normalizedName': 'alpha',
          'traderId': 'trader-b',
          'mapId': 'map-b',
          'minPlayerLevel': 10,
          'experience': 100,
          'kappaRequired': false,
        },
        {
          'id': 'quest-bravo',
          'kind': 'task',
          'name': 'Bravo',
          'normalizedName': 'bravo',
          'traderId': 'trader-a',
          'mapId': null,
          'minPlayerLevel': 10,
          'experience': 200,
          'kappaRequired': true,
        },
        {
          'id': 'quest-charlie',
          'kind': 'task',
          'name': 'Charlie',
          'normalizedName': 'charlie',
          'traderId': null,
          'mapId': 'map-a',
          'minPlayerLevel': 5,
          'experience': 300,
          'kappaRequired': false,
        },
      ]);

      Future<List<QuestSummary>> sorted(
        QuestSortField field, {
        required bool descending,
      }) async => (await syntheticRepository.query(
        QuestQuery(sort: QuestSort(field, descending: descending)),
      )).quests;

      for (final field in QuestSortField.values) {
        final ascending = await sorted(field, descending: false);
        final descending = await sorted(field, descending: true);

        List<Object?> valuesOf(List<QuestSummary> quests) => switch (field) {
          QuestSortField.name => [for (final quest in quests) quest.name],
          QuestSortField.minPlayerLevel => [
            for (final quest in quests) quest.minPlayerLevel,
          ],
          QuestSortField.traderId => [
            for (final quest in quests) quest.traderId,
          ],
          QuestSortField.mapId => [for (final quest in quests) quest.mapId],
        };

        final ascendingValues = valuesOf(ascending);
        final descendingValues = valuesOf(descending);

        if (field == QuestSortField.name) {
          _expectSorted<String>(
            ascendingValues.cast<String>(),
            descending: false,
          );
          _expectSorted<String>(
            descendingValues.cast<String>(),
            descending: true,
          );
        } else if (field == QuestSortField.minPlayerLevel) {
          _expectSorted<int>(ascendingValues.cast<int?>(), descending: false);
          _expectSorted<int>(descendingValues.cast<int?>(), descending: true);
        } else {
          _expectSorted<String>(
            ascendingValues.cast<String?>(),
            descending: false,
          );
          _expectSorted<String>(
            descendingValues.cast<String?>(),
            descending: true,
          );
        }
      }

      // Stable ties: 10 is shared by Alpha and Bravo; nulls are last for the
      // min-level sort in both directions.
      final byLevelAscending = await sorted(
        QuestSortField.minPlayerLevel,
        descending: false,
      );
      expect(
        [for (final quest in byLevelAscending) quest.id],
        ['quest-charlie', 'quest-alpha', 'quest-bravo', 'quest-null'],
      );
      expect(byLevelAscending.last.minPlayerLevel, isNull);

      final byLevelDescending = await sorted(
        QuestSortField.minPlayerLevel,
        descending: true,
      );
      expect(
        [for (final quest in byLevelDescending) quest.id],
        ['quest-alpha', 'quest-bravo', 'quest-charlie', 'quest-null'],
      );
      expect(byLevelDescending.last.minPlayerLevel, isNull);

      // Nulls remain last for map ids in both directions.
      final byMapAscending = await sorted(
        QuestSortField.mapId,
        descending: false,
      );
      expect(byMapAscending.last.mapId, isNull);
      final byMapDescending = await sorted(
        QuestSortField.mapId,
        descending: true,
      );
      expect(byMapDescending.last.mapId, isNull);

      // A quest with an unknown required level cannot prove either an exact or
      // an at-or-below bound, so it matches neither level filter.
      final exactTen = await syntheticRepository.query(
        const QuestQuery(filters: QuestFilters(minPlayerLevel: 10)),
      );
      expect(_ids(exactTen.quests), {'quest-alpha', 'quest-bravo'});

      final atMostTen = await syntheticRepository.query(
        const QuestQuery(filters: QuestFilters(maxPlayerLevel: 10)),
      );
      expect(_ids(atMostTen.quests), {
        'quest-alpha',
        'quest-bravo',
        'quest-charlie',
      });
      expect(_ids(atMostTen.quests), isNot(contains('quest-null')));
    });

    test('a filter set through with… calls keeps every other field', () async {
      const filters = QuestFilters(
        text: 'cafe',
        traderId: 'trader-1',
        mapId: 'map-1',
        minPlayerLevel: 3,
        maxPlayerLevel: 10,
        state: QuestProgressState.notStarted,
      );

      final updated = filters
          .withText('creme')
          .withTrader('trader-2')
          .withMap('map-2')
          .withMinPlayerLevel(4)
          .withMaxPlayerLevel(11)
          .withState(QuestProgressState.completed);

      expect(updated.text, 'creme');
      expect(updated.traderId, 'trader-2');
      expect(updated.mapId, 'map-2');
      expect(updated.minPlayerLevel, 4);
      expect(updated.maxPlayerLevel, 11);
      expect(updated.state, QuestProgressState.completed);

      final query = const QuestQuery()
          .withFilters(updated)
          .withSort(const QuestSort(QuestSortField.mapId, descending: true))
          .withPagination(limit: 7, offset: 3)
          .withProfile('profile-a');
      expect(query.filters, updated);
      expect(
        query.sort,
        const QuestSort(QuestSortField.mapId, descending: true),
      );
      expect(query.limit, 7);
      expect(query.offset, 3);
      expect(query.profileId, 'profile-a');
    });
  });

  test('progress state values map to the documented stored values', () {
    expect(QuestProgressState.notStarted.storedValue, isNull);
    expect(QuestProgressState.inProgress.storedValue, 'in-progress');
    expect(QuestProgressState.completed.storedValue, 'completed');
    expect(QuestProgressState.failed.storedValue, 'failed');

    expect(
      QuestProgressState.fromStoredValue('in-progress'),
      QuestProgressState.inProgress,
    );
    expect(
      QuestProgressState.fromStoredValue('completed'),
      QuestProgressState.completed,
    );
    expect(
      QuestProgressState.fromStoredValue('failed'),
      QuestProgressState.failed,
    );
    expect(
      QuestProgressState.fromStoredValue(null),
      QuestProgressState.notStarted,
    );
    expect(
      QuestProgressState.fromStoredValue('paused'),
      QuestProgressState.notStarted,
    );
  });

  test('QuestProgressState round-trips through its stored value', () {
    for (final state in QuestProgressState.values) {
      expect(
        QuestProgressState.fromStoredValue(state.storedValue),
        state,
        reason: state.name,
      );
    }
  });
}
