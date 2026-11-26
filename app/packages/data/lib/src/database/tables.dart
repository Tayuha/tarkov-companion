import 'package:drift/drift.dart';

/// The drift schema of the local Tarkov Companion database.
///
/// The schema is split in two halves (design D4):
///
/// * **Game data** — owned by the bundle pipeline and replaced wholesale on a
///   dataset refresh. Every table is keyed by an upstream identifier and keeps
///   the complete JSONL record in a `payload` column next to the columns the UI
///   queries. Game-data tables may reference each other with foreign keys.
/// * **Player data** — owned by the app and never touched by ingestion. Player
///   tables must not declare a foreign key onto a game-data table, so deleting
///   or replacing a dataset can never remove progress.
///
/// Column names are written in `camelCase` to match the bundle record fields
/// (`docs/data-bundles.md`), so ingestion maps a record field to a column
/// without a name translation. Timestamps are drift `DateTimeColumn`s, stored
/// as Unix epoch seconds.
///
/// Adding or changing a table requires `schemaVersion` to move forward in
/// `AppDatabase` and the generated code to be rebuilt; see `docs/schema.md`.

// ---------------------------------------------------------------------------
// Game data (replaceable, written by ingestion, never authoring player rows)
// ---------------------------------------------------------------------------

/// Bookkeeping for applied datasets: one row per `(mode, dataset)`.
///
/// The primary key makes applying a dataset idempotent — ingestion upserts the
/// row and a second apply of the same checksum is a no-op.
@DataClassName('DatasetState')
class DatasetStates extends Table {
  @override
  String get tableName => 'datasetState';

  /// Game mode: `regular`, `pve` or `pvp-season`.
  TextColumn get mode => text().named('mode')();

  /// Bundle dataset name: `items`, `tasks`, `traders`, ...
  TextColumn get dataset => text().named('dataset')();

  /// SHA-256 of the compressed dataset file that was applied.
  TextColumn get checksum => text().named('checksum')();

  /// `datasets[].schemaVersion` of the applied bundle entry.
  IntColumn get schemaVersion => integer().named('schemaVersion')();

  /// Number of JSONL records applied, for diagnostics.
  IntColumn get records => integer().named('records')();

  /// Upstream timestamp of the applied content, when the manifest provides it.
  DateTimeColumn get sourceUpdatedAt =>
      dateTime().named('sourceUpdatedAt').nullable()();

  /// When this client applied the dataset.
  DateTimeColumn get appliedAt => dateTime().named('appliedAt')();

  @override
  Set<Column<Object>> get primaryKey => {mode, dataset};
}

/// The last manifest seen for each game mode, used by the sync layer.
///
/// This is client-owned bookkeeping, like [DatasetStates], not ingested game
/// data. It keeps the raw manifest body exactly as received so a `304 Not
/// Modified` can return the cached document without a second request, plus the
/// validators needed for the next conditional request (`ETag` and
/// `Last-Modified`).
///
/// [contentHash] is the SHA-256 of the raw manifest bytes. It is what decides
/// whether the document actually changed: a `200` with the same body but a new
/// `ETag` updates the validators and [lastCheckedAt] without moving
/// [lastChangedAt].
@DataClassName('RemoteManifestRecord')
class RemoteManifests extends Table {
  @override
  String get tableName => 'remoteManifest';

  /// Game mode: `regular`, `pve` or `pvp-season`.
  TextColumn get mode => text().named('mode')();

  /// HTTP `ETag` from the last successful fetch, when the response had one.
  TextColumn get etag => text().named('etag').nullable()();

  /// HTTP `Last-Modified` from the last successful fetch, when present.
  TextColumn get lastModified => text().named('lastModified').nullable()();

  /// The raw manifest document exactly as received (a UTF-8 JSON object).
  TextColumn get manifestJson => text().named('manifestJson')();

  /// The manifest's `generatedAt`, verbatim, as a diagnostic.
  TextColumn get manifestGeneratedAt =>
      text().named('manifestGeneratedAt').nullable()();

  /// When this client last asked the server about this mode's manifest.
  DateTimeColumn get lastCheckedAt => dateTime().named('lastCheckedAt')();

  /// When the manifest body last changed, or `null` before the first change.
  DateTimeColumn get lastChangedAt =>
      dateTime().named('lastChangedAt').nullable()();

  /// Lowercase hex SHA-256 of the raw manifest bytes.
  TextColumn get contentHash => text().named('contentHash')();

  @override
  Set<Column<Object>> get primaryKey => {mode};
}

/// Catalog items, one row per `item` record.
///
/// The item table is the only game-data table that the catalog queries
/// directly; everything type-specific lives in [payload]. `items_fts` is an
/// FTS5 external-content index over the three text columns, created in
/// `AppDatabase.migration` and kept in sync by triggers.
@DataClassName('Item')
@TableIndex(name: 'itemsNormalizedName', columns: {#normalizedName})
@TableIndex(name: 'itemsLastLowPrice', columns: {#lastLowPrice})
@TableIndex(name: 'itemsAvg24hPrice', columns: {#avg24hPrice})
class Items extends Table {
  @override
  String get tableName => 'items';

  /// Upstream item id (`items[].id`).
  TextColumn get id => text().named('id')();

  /// Display name, localized by the pipeline.
  TextColumn get name => text().named('name')();

  /// Short display name (`M4A1`).
  TextColumn get shortName => text().named('shortName')();

  /// Diacritic-free, lower-case search key from the bundle.
  TextColumn get normalizedName => text().named('normalizedName')();

  /// Weight in kilograms.
  RealColumn get weight => real().named('weight').nullable()();

  /// Grid width in slots.
  IntColumn get width => integer().named('width').nullable()();

  /// Grid height in slots.
  IntColumn get height => integer().named('height').nullable()();

  /// Trader-independent base price in roubles.
  IntColumn get basePrice => integer().named('basePrice').nullable()();

  /// Flea-market 24 h average, `price.avg24h`.
  IntColumn get avg24hPrice => integer().named('avg24hPrice').nullable()();

  /// Latest flea-market low, `price.lastLow`.
  IntColumn get lastLowPrice => integer().named('lastLowPrice').nullable()();

  /// 48 h flea price change as a percentage, `price.change48hPercent`.
  RealColumn get changeLast48hPercent =>
      real().named('changeLast48hPercent').nullable()();

  /// Icon URL.
  TextColumn get iconLink => text().named('iconLink').nullable()();

  /// Grid image URL.
  TextColumn get gridImageLink => text().named('gridImageLink').nullable()();

  /// The complete bundle record as canonical JSON.
  TextColumn get payload => text().named('payload')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Quests, one row per `task` record. Objectives are split into
/// [TaskObjectives]; the rest of the record stays in [payload].
@DataClassName('Task')
@TableIndex(name: 'tasksTraderId', columns: {#traderId})
@TableIndex(name: 'tasksMapId', columns: {#mapId})
@TableIndex(name: 'tasksMinPlayerLevel', columns: {#minPlayerLevel})
class Tasks extends Table {
  @override
  String get tableName => 'tasks';

  /// Upstream task id.
  TextColumn get id => text().named('id')();

  /// Localized quest name.
  TextColumn get name => text().named('name')();

  /// Trader that gives the quest.
  TextColumn get traderId => text().named('traderId').nullable()();

  /// Primary map of the quest, when upstream provides one.
  TextColumn get mapId => text().named('mapId').nullable()();

  /// Minimum player level required to accept the quest.
  IntColumn get minPlayerLevel =>
      integer().named('minPlayerLevel').nullable()();

  /// Experience reward. Upstream may send `null`.
  IntColumn get experience => integer().named('experience').nullable()();

  /// Whether the quest counts towards the Kappa container.
  BoolColumn get kappaRequired =>
      boolean().named('kappaRequired').withDefault(const Constant(false))();

  /// The complete bundle record as canonical JSON.
  TextColumn get payload => text().named('payload')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Quest objectives, split out of the task record so the tracker can query and
/// index them. `payload` holds the complete objective object.
///
/// This is a game-data table: the foreign key to [Tasks] is allowed (and
/// cascades on delete) because both sides are replaced by ingestion. No player
/// table references this one with a foreign key.
@DataClassName('TaskObjective')
@TableIndex(name: 'taskObjectivesTaskId', columns: {#taskId})
class TaskObjectives extends Table {
  @override
  String get tableName => 'taskObjectives';

  /// Upstream objective id.
  TextColumn get id => text().named('id')();

  /// Owning task; cascades when the task row is replaced.
  TextColumn get taskId => text()
      .named('taskId')
      .references(Tasks, #id, onDelete: KeyAction.cascade)();

  /// Objective type (`shoot`, `findItem`, `visit`, ...).
  TextColumn get type => text().named('type')();

  /// Localized objective description.
  TextColumn get description =>
      text().named('description').withDefault(const Constant(''))();

  /// Required count for countable objectives; `null` for binary ones.
  IntColumn get count => integer().named('count').nullable()();

  /// The complete bundle record as canonical JSON.
  TextColumn get payload => text().named('payload')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Traders, one row per `trader` record.
@DataClassName('Trader')
@TableIndex(name: 'tradersNormalizedName', columns: {#normalizedName})
class Traders extends Table {
  @override
  String get tableName => 'traders';

  TextColumn get id => text().named('id')();
  TextColumn get name => text().named('name')();
  TextColumn get normalizedName => text().named('normalizedName')();
  TextColumn get payload => text().named('payload')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Hideout stations, one row per `hideoutStation` record.
@DataClassName('HideoutStation')
class HideoutStations extends Table {
  @override
  String get tableName => 'hideoutStations';

  TextColumn get id => text().named('id')();
  TextColumn get name => text().named('name')();
  TextColumn get payload => text().named('payload')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Hideout crafts, one row per `craft` record.
@DataClassName('Craft')
@TableIndex(name: 'craftsStationId', columns: {#stationId})
@TableIndex(name: 'craftsProductItemId', columns: {#productItemId})
class Crafts extends Table {
  @override
  String get tableName => 'crafts';

  TextColumn get id => text().named('id')();
  TextColumn get stationId => text().named('stationId')();
  TextColumn get productItemId => text().named('productItemId')();
  TextColumn get payload => text().named('payload')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Trader barters, one row per `barter` record.
@DataClassName('Barter')
class Barters extends Table {
  @override
  String get tableName => 'barters';

  TextColumn get id => text().named('id')();
  TextColumn get payload => text().named('payload')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Maps, one row per `map` record.
///
/// The row class is named `TarkovMap` so it does not shadow `dart:core`'s
/// `Map` in generated code.
@DataClassName('TarkovMap')
@TableIndex(name: 'mapsNormalizedName', columns: {#normalizedName})
class Maps extends Table {
  @override
  String get tableName => 'maps';

  TextColumn get id => text().named('id')();
  TextColumn get name => text().named('name')();
  TextColumn get normalizedName => text().named('normalizedName')();
  TextColumn get payload => text().named('payload')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Bundle records that have no dedicated table yet, keyed by record kind and id.
///
/// The bundle carries auxiliary collections (`itemCategory`, `armorMaterial`,
/// `achievement`, `mob`, ...) that the UI does not query yet. Storing them here
/// keeps a whole-dataset replacement lossless: a future feature can start
/// reading them without a client release that had to re-download the bundle.
/// [payload] is the complete record as canonical JSON, exactly like the
/// dedicated tables.
///
/// `kind` is part of the primary key because upstream ids are only unique
/// within a kind (for example a `questItem` and an `achievement` may share an
/// upstream id namespace but are different records).
@DataClassName('GameRecord')
@TableIndex(name: 'gameRecordsKind', columns: {#kind})
class GameRecords extends Table {
  @override
  String get tableName => 'gameRecords';

  /// Bundle record discriminator (`itemCategory`, `achievement`, ...).
  TextColumn get kind => text().named('kind')();

  /// Upstream identifier of the record.
  TextColumn get id => text().named('id')();

  /// The complete bundle record as canonical JSON.
  TextColumn get payload => text().named('payload')();

  @override
  Set<Column<Object>> get primaryKey => {kind, id};
}

/// Cached per-item price history. This is game data (a cache), refreshed on
/// demand rather than by dataset ingestion.
///
/// There is deliberately no foreign key to [Items]: deleting and re-inserting
/// the item dataset must neither fail nor wipe a cached history, and the
/// history is invalidated by its own TTL instead.
@DataClassName('PriceHistoryEntry')
@TableIndex(name: 'priceHistoryItemId', columns: {#itemId})
class PriceHistory extends Table {
  @override
  String get tableName => 'priceHistory';

  TextColumn get itemId => text().named('itemId')();
  DateTimeColumn get observedAt => dateTime().named('observedAt')();
  IntColumn get price => integer().named('price')();
  IntColumn get priceMin => integer().named('priceMin').nullable()();

  @override
  Set<Column<Object>> get primaryKey => {itemId, observedAt};
}

// ---------------------------------------------------------------------------
// Player data (durable, never cascaded from game data)
// ---------------------------------------------------------------------------

/// One profile per game mode. Progress is scoped to a profile.
///
/// Player data: this table has no foreign key onto any game-data table.
@DataClassName('Profile')
class Profiles extends Table {
  @override
  String get tableName => 'profiles';

  /// Profile id. Stable for the lifetime of the profile.
  TextColumn get id => text().named('id')();

  /// `regular`, `pve` or `pvp-season`; at most one profile per mode.
  TextColumn get gameMode => text().named('gameMode').unique()();

  /// Player level recorded by the user.
  IntColumn get playerLevel =>
      integer().named('playerLevel').withDefault(const Constant(1))();

  DateTimeColumn get createdAt => dateTime().named('createdAt')();
  DateTimeColumn get updatedAt => dateTime().named('updatedAt')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Recorded quest state for a profile.
///
/// `questId` intentionally has no foreign key: a quest that disappears from the
/// dataset keeps its recorded state (spec: "Quest removed upstream"), and a
/// dataset refresh can never delete progress. The foreign key to [Profiles]
/// cascades because both sides are player data.
@DataClassName('QuestProgressEntry')
@TableIndex(name: 'questProgressQuestId', columns: {#questId})
class QuestProgress extends Table {
  @override
  String get tableName => 'questProgress';

  TextColumn get profileId => text()
      .named('profileId')
      .references(Profiles, #id, onDelete: KeyAction.cascade)();

  /// Upstream quest id; may reference a quest absent from the current dataset.
  TextColumn get questId => text().named('questId')();

  /// `in-progress`, `completed` or `failed`. Availability (locked/available) is
  /// derived and never stored.
  TextColumn get state => text().named('state')();

  DateTimeColumn get updatedAt => dateTime().named('updatedAt')();

  @override
  Set<Column<Object>> get primaryKey => {profileId, questId};
}

/// Recorded counts for countable quest objectives.
///
/// Like [QuestProgress], `questId` and `objectiveId` have no foreign key onto
/// game data.
@DataClassName('ObjectiveProgressEntry')
@TableIndex(name: 'objectiveProgressQuestId', columns: {#questId})
class ObjectiveProgress extends Table {
  @override
  String get tableName => 'objectiveProgress';

  TextColumn get profileId => text()
      .named('profileId')
      .references(Profiles, #id, onDelete: KeyAction.cascade)();

  TextColumn get questId => text().named('questId')();
  TextColumn get objectiveId => text().named('objectiveId')();

  /// Recorded count, clamped to the objective's required count by the tracker.
  IntColumn get count =>
      integer().named('count').withDefault(const Constant(0))();

  DateTimeColumn get updatedAt => dateTime().named('updatedAt')();

  @override
  Set<Column<Object>> get primaryKey => {profileId, questId, objectiveId};
}

/// Key/value store for app preferences (active profile, auto-update, metered
/// behavior, freshness threshold). Values are strings so a preference keeps its
/// meaning across schema versions.
@DataClassName('AppSetting')
class AppSettings extends Table {
  @override
  String get tableName => 'appSettings';

  TextColumn get key => text().named('key')();
  TextColumn get value => text().named('value')();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
