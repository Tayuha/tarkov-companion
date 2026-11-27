import 'dart:convert';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

/// One hand-written quest used by the quest list screen tests.
///
/// The screen tests need stable names, levels, maps and progress rows, not the
/// full pipeline corpus. They still run through the real [QuestRepository], so
/// every filter is exercised by the production SQL.
final class QuestFixtureQuest {
  const QuestFixtureQuest({
    required this.id,
    required this.name,
    required this.normalizedName,
    this.traderId,
    this.mapId,
    this.minPlayerLevel,
    this.experience,
  });

  final String id;
  final String name;
  final String normalizedName;
  final String? traderId;
  final String? mapId;
  final int? minPlayerLevel;
  final int? experience;
}

const fixtureProfileRegular = 'profile-regular';
const fixtureProfilePve = 'profile-pve';

const fixturePrapor = 'trader-prapor';
const fixtureTherapist = 'trader-therapist';
const fixtureSkier = 'trader-skier';

const fixtureCustoms = 'map-customs';
const fixtureWoods = 'map-woods';
const fixtureInterchange = 'map-interchange';

const fixtureTraderOptions = <QuestFilterOption>[
  QuestFilterOption(id: fixturePrapor, label: 'Prapor'),
  QuestFilterOption(id: fixtureTherapist, label: 'Therapist'),
  QuestFilterOption(id: fixtureSkier, label: 'Skier'),
];

const fixtureMapOptions = <QuestFilterOption>[
  QuestFilterOption(id: fixtureCustoms, label: 'Customs'),
  QuestFilterOption(id: fixtureWoods, label: 'Woods'),
  QuestFilterOption(id: fixtureInterchange, label: 'Interchange'),
];

/// Fourteen quests: enough for three pages of five, with traders, maps and
/// levels that make each filter's result set unambiguous.
const fixtureQuests = <QuestFixtureQuest>[
  QuestFixtureQuest(
    id: 'quest-cafe',
    name: 'Café Crème',
    normalizedName: 'cafe-creme',
    traderId: fixtureTherapist,
    mapId: fixtureInterchange,
    minPlayerLevel: 10,
    experience: 3000,
  ),
  QuestFixtureQuest(
    id: 'quest-car-repair',
    name: 'Car Repair',
    normalizedName: 'car-repair',
    traderId: fixtureSkier,
    mapId: fixtureInterchange,
    minPlayerLevel: 15,
    experience: 5000,
  ),
  QuestFixtureQuest(
    id: 'quest-checking',
    name: 'Checking',
    normalizedName: 'checking',
    traderId: fixturePrapor,
    mapId: fixtureCustoms,
    minPlayerLevel: 5,
    experience: 1800,
  ),
  QuestFixtureQuest(
    id: 'quest-collector',
    name: 'Collector',
    normalizedName: 'collector',
    traderId: fixturePrapor,
    minPlayerLevel: 40,
    experience: 100000,
  ),
  QuestFixtureQuest(
    id: 'quest-debut',
    name: 'Debut',
    normalizedName: 'debut',
    traderId: fixturePrapor,
    mapId: fixtureCustoms,
    minPlayerLevel: 1,
    experience: 1000,
  ),
  QuestFixtureQuest(
    id: 'quest-fishing-gear',
    name: 'Fishing Gear',
    normalizedName: 'fishing-gear',
    traderId: fixturePrapor,
    mapId: fixtureWoods,
    minPlayerLevel: 30,
    experience: 12000,
  ),
  QuestFixtureQuest(
    id: 'quest-friend-west',
    name: 'Friend from the West - Part 1',
    normalizedName: 'friend-from-the-west-part-1',
    traderId: fixtureSkier,
    mapId: fixtureCustoms,
    minPlayerLevel: 25,
    experience: 9000,
  ),
  QuestFixtureQuest(
    id: 'quest-gunsmith',
    name: 'Gunsmith - Part 1',
    normalizedName: 'gunsmith-part-1',
    traderId: fixtureSkier,
    minPlayerLevel: 30,
    experience: 11000,
  ),
  QuestFixtureQuest(
    id: 'quest-sanitary',
    name: 'Sanitary Standards - Part 1',
    normalizedName: 'sanitary-standards-part-1',
    traderId: fixtureTherapist,
    mapId: fixtureCustoms,
    minPlayerLevel: 5,
    experience: 2500,
  ),
  QuestFixtureQuest(
    id: 'quest-shootout',
    name: 'Shootout Picnic',
    normalizedName: 'shootout-picnic',
    traderId: fixturePrapor,
    mapId: fixtureWoods,
    minPlayerLevel: 10,
    experience: 4000,
  ),
  QuestFixtureQuest(
    id: 'quest-shortage',
    name: 'Shortage',
    normalizedName: 'shortage',
    traderId: fixtureTherapist,
    mapId: fixtureInterchange,
    minPlayerLevel: 10,
    experience: 3500,
  ),
  QuestFixtureQuest(
    id: 'quest-supply-plans',
    name: 'Supply Plans',
    normalizedName: 'supply-plans',
    traderId: fixtureTherapist,
    mapId: fixtureWoods,
    minPlayerLevel: 20,
    experience: 6000,
  ),
  QuestFixtureQuest(
    id: 'quest-punisher-1',
    name: 'The Punisher - Part 1',
    normalizedName: 'the-punisher-part-1',
    traderId: fixturePrapor,
    mapId: fixtureCustoms,
    minPlayerLevel: 15,
    experience: 7000,
  ),
  QuestFixtureQuest(
    id: 'quest-punisher-2',
    name: 'The Punisher - Part 2',
    normalizedName: 'the-punisher-part-2',
    traderId: fixturePrapor,
    mapId: fixtureCustoms,
    minPlayerLevel: 20,
    experience: 8000,
  ),
];

/// Recorded progress per profile. Every quest absent here is not started.
const fixtureProgress = <String, Map<String, String>>{
  fixtureProfileRegular: {
    'quest-debut': 'completed',
    'quest-checking': 'in-progress',
    'quest-shootout': 'failed',
    'quest-punisher-1': 'completed',
    'quest-sanitary': 'in-progress',
  },
  fixtureProfilePve: {
    'quest-debut': 'in-progress',
    'quest-checking': 'completed',
    'quest-punisher-1': 'failed',
  },
};

/// Opens an in-memory database with two profiles, the quest fixture and their
/// recorded progress.
Future<AppDatabase> openQuestFixtureDatabase() async {
  final database = AppDatabase.memory();
  await database.customSelect('SELECT 1').get(); // Force `beforeOpen`.
  await seedQuestFixture(database);
  return database;
}

/// Inserts the fixture through raw SQL so the test does not depend on drift.
Future<void> seedQuestFixture(AppDatabase database) async {
  final now = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;

  for (final (id, mode) in [
    (fixtureProfileRegular, 'regular'),
    (fixtureProfilePve, 'pve'),
  ]) {
    await database.customStatement(
      'INSERT INTO profiles (id, gameMode, playerLevel, createdAt, updatedAt) '
      'VALUES (?, ?, ?, ?, ?)',
      [id, mode, 25, now, now],
    );
  }

  for (final (id, name) in [
    (fixturePrapor, 'Prapor'),
    (fixtureTherapist, 'Therapist'),
    (fixtureSkier, 'Skier'),
  ]) {
    await database.customStatement(
      'INSERT INTO traders (id, name, normalizedName, payload) VALUES (?, ?, ?, ?)',
      [id, name, name.toLowerCase(), '{}'],
    );
  }

  for (final (id, name) in [
    (fixtureCustoms, 'Customs'),
    (fixtureWoods, 'Woods'),
    (fixtureInterchange, 'Interchange'),
  ]) {
    await database.customStatement(
      'INSERT INTO maps (id, name, normalizedName, payload) VALUES (?, ?, ?, ?)',
      [id, name, name.toLowerCase(), '{}'],
    );
  }

  for (final quest in fixtureQuests) {
    await database.customStatement(
      'INSERT INTO tasks ('
      'id, name, traderId, mapId, minPlayerLevel, experience, kappaRequired, '
      'payload'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        quest.id,
        quest.name,
        quest.traderId,
        quest.mapId,
        quest.minPlayerLevel,
        quest.experience,
        0,
        jsonEncode({'normalizedName': quest.normalizedName}),
      ],
    );
  }

  for (final entry in fixtureProgress.entries) {
    for (final progress in entry.value.entries) {
      await database.customStatement(
        'INSERT INTO questProgress (profileId, questId, state, updatedAt) '
        'VALUES (?, ?, ?, ?)',
        [entry.key, progress.key, progress.value, now],
      );
    }
  }
}
