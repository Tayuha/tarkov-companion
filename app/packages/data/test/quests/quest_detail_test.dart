import 'dart:convert';
import 'dart:io';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/bundle_fixture.dart';
import '../support/database_helpers.dart';
import '../support/quest_fixture.dart';

const _debut = '5936d90786f7742b1420ba5b';
const _sanitary1 = '59689ee586f7740d1570bbd5';
const _sanitary2 = '596a204686f774576d4c95de';
const _backgroundCheck = '5936da9e86f7742d65037edf';
const _bullshit = '5c0bbaa886f7746941031d82';
const _chemical2 = '597a0b2986f77426d66c0633';
const _iceCreamCones = '59675d6c86f7740a842fc482';
const _prapor = '54cb50c76803fa8b248b4571';
const _customs = '56f40101d2720b2a4d8b45d6';

void main() {
  late AppDatabase db;
  late Directory temporary;
  late QuestRepository repository;

  setUpAll(() async {
    db = await openMemoryDatabase();
    temporary = Directory.systemTemp.createTempSync('tarkov_quest_detail_');
    await ingestNormalizedTasksFixture(db, temporary);
    repository = QuestRepository(db);

    // Display names are joined from the local datasets, so give the detail a
    // realistic trader/map to resolve.
    final trader = writeSyntheticDataset(temporary, DatasetKind.traders, [
      jsonEncode({
        'id': _prapor,
        'kind': 'trader',
        'name': 'Prapor',
        'normalizedName': 'prapor',
      }),
    ]);
    await DatasetIngestor(db).ingest(
      mode: GameMode.regular,
      dataset: trader.dataset,
      compressedFile: trader.file,
    );

    final map = writeSyntheticDataset(temporary, DatasetKind.maps, [
      jsonEncode({
        'id': _customs,
        'kind': 'map',
        'name': 'Customs',
        'normalizedName': 'customs',
      }),
    ]);
    await DatasetIngestor(db).ingest(
      mode: GameMode.regular,
      dataset: map.dataset,
      compressedFile: map.file,
    );
  });

  tearDownAll(() async {
    await db.close();
    if (temporary.existsSync()) {
      temporary.deleteSync(recursive: true);
    }
  });

  test('detail exposes the catalog fields, objectives and rewards', () async {
    final detail = await repository.detail(_debut);
    expect(detail, isNotNull);
    detail!;

    expect(detail.id, _debut);
    expect(detail.name, 'Debut');
    expect(detail.normalizedName, 'debut');
    expect(detail.traderId, _prapor);
    expect(detail.traderName, 'Prapor');
    expect(detail.mapId, isNull);
    expect(detail.mapName, isNull);
    expect(detail.minPlayerLevel, 0);
    expect(detail.experience, 3000);
    expect(detail.kappaRequired, isFalse);
    expect(detail.wikiLink, contains('Debut'));
    expect(detail.prerequisites, isEmpty);

    expect(detail.objectives, hasLength(1));
    final objective = detail.objectives.single;
    expect(objective.type, 'shoot');
    expect(objective.description, isNotEmpty);
    expect(objective.requiredCount, 5);
    expect(objective.countable, isTrue);
    expect(objective.optional, isFalse);
    expect(objective.mapIds, hasLength(5));
    expect(objective.targetNames, contains('Scav'));

    expect(detail.rewards.items, hasLength(1));
    expect(detail.rewards.items.single.itemId, '5449016a4bdc2d6f028b456f');
    expect(detail.rewards.items.single.count, 80000);
    expect(detail.rewards.traderStanding, hasLength(1));
    expect(detail.rewards.traderStanding.single.traderId, _prapor);
    expect(detail.rewards.traderStanding.single.standing, 0.1);
    expect(detail.rewards.isEmpty, isFalse);
    expect(detail.unlocks, isEmpty);
  });

  test('prerequisites and single-quest unlocks are symmetric', () async {
    final part2 = await repository.detail(_sanitary2);
    expect(part2, isNotNull);
    expect(part2!.prerequisites, hasLength(1));
    expect(part2.prerequisites.single.taskId, _sanitary1);
    expect(part2.prerequisites.single.requiredStatuses, ['complete']);

    final part1 = await repository.detail(_sanitary1);
    expect(part1, isNotNull);
    expect(part1!.unlocks, hasLength(1));
    expect(part1.unlocks.single.questId, _sanitary2);
    expect(part1.unlocks.single.name, 'Sanitary Standards - Part 2');
    expect(part1.unlocks.single.requiredStatuses, ['complete']);
  });

  test('objectives keep their types and optional/binary semantics', () async {
    final detail = await repository.detail(_backgroundCheck);
    expect(detail, isNotNull);
    expect(detail!.mapId, _customs);
    expect(detail.mapName, 'Customs');
    expect(detail.objectives, hasLength(3));
    expect(
      detail.objectives.map((objective) => objective.type),
      containsAll(<String>['findQuestItem', 'findItem', 'giveQuestItem']),
    );
    expect(
      detail.objectives.every((objective) => objective.requiredCount >= 1),
      isTrue,
    );
    expect(
      detail.objectives.where((objective) => objective.optional),
      hasLength(1),
    );

    final part1 = await repository.detail(_sanitary1);
    final visit = part1!.objectives.singleWhere(
      (objective) => objective.type == 'visit',
    );
    expect(visit.optional, isTrue);
    expect(visit.countable, isFalse);
    expect(visit.requiredCount, 1);
  });

  test('reward categories beyond items and standing are parsed', () async {
    final detail = await repository.detail(_bullshit);
    expect(detail, isNotNull);
    expect(detail!.rewards.skills, isNotEmpty);
    expect(detail.rewards.skills.first.skill, isNotEmpty);
    expect(detail.rewards.skills.first.level, greaterThan(0));
    expect(detail.rewards.offerUnlocks, isNotEmpty);
    expect(detail.rewards.offerUnlocks.first.id, isNotEmpty);
    expect(detail.rewards.traderStanding.single.standing, 1.5);
  });

  test('craft unlocks are part of the reward model', () async {
    final detail = await repository.detail(_chemical2);
    expect(detail, isNotNull);
    expect(detail!.rewards.craftUnlocks, isNotEmpty);
    expect(detail.rewards.craftUnlocks.first.stationId, isNotEmpty);
  });

  test(
    'trader loyalty requirements are reported as typed advisories',
    () async {
      final detail = await repository.detail(_iceCreamCones);
      expect(detail, isNotNull);
      expect(detail!.traderRequirements, hasLength(1));
      final requirement = detail.traderRequirements.single;
      expect(requirement.isLoyaltyLevel, isTrue);
      expect(requirement.traderId, _prapor);
      expect(requirement.value, 2);
    },
  );

  test(
    'objectivesFor is the same ordered list and unknown ids are empty',
    () async {
      final objectives = await repository.objectivesFor(_sanitary1);
      expect(objectives, hasLength(3));
      final ids = [for (final objective in objectives) objective.id];
      expect(ids, List<String>.from(ids)..sort());

      expect(await repository.objectivesFor('missing'), isEmpty);
    },
  );

  test('a missing quest id returns null', () async {
    expect(await repository.detail('missing'), isNull);
  });
}
