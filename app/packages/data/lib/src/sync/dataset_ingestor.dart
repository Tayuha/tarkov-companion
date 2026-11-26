import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../bundle/bundle_contract.dart';
import '../bundle/canonical_json.dart';
import '../bundle/game_mode.dart';
import '../bundle/manifest.dart';
import '../database/app_database.dart';
import '../database/dataset_state_repository.dart';
import '../database/tables.dart';
import '../dataset_kind.dart';
import 'jsonl_reader.dart';

/// Why a dataset could not be ingested.
enum IngestFailure {
  /// The verified `.jsonl.zst` file is not on disk.
  missingFile,

  /// The compressed bytes are not a valid zstd frame, or decoding failed.
  decompression,

  /// The decoded payload is not valid UTF-8.
  invalidUtf8,

  /// A line is not a JSON object.
  malformedJson,

  /// A record is missing `kind`/`id`, has the wrong field type, or a dedicated
  /// kind lacks a required field (for example an `item` without `name`).
  invalidRecord,

  /// The same `kind`+`id` appears twice in one dataset.
  duplicateRecord,

  /// The dataset declared fewer or more lines than the manifest's `records`.
  recordCountMismatch,

  /// The dataset's record schema is newer than this client implements.
  unsupportedSchema,

  /// `datasetState` refused the dataset even though the schema check passed.
  datasetStateRejected,
}

/// A typed ingestion failure.
///
/// Every failure aborts the dataset's transaction: previously applied rows and
/// `datasetState` stay exactly as they were. [line] is 1-based and populated
/// once line parsing has started.
final class IngestError implements Exception {
  const IngestError(this.failure, this.message, {this.line, this.cause});

  final IngestFailure failure;
  final String message;
  final int? line;
  final Object? cause;

  @override
  String toString() {
    final at = line == null ? '' : ' (line $line)';
    return 'IngestError(${failure.name})$at: $message';
  }
}

/// Progress through one dataset.
final class IngestProgress {
  const IngestProgress({
    required this.recordsProcessed,
    required this.totalRecords,
  });

  final int recordsProcessed;
  final int totalRecords;

  /// `0.0` until the first record, `1.0` once every line was processed.
  double get fraction =>
      totalRecords == 0 ? 1 : recordsProcessed / totalRecords;
}

/// What an ingest committed.
final class IngestResult {
  const IngestResult({
    required this.mode,
    required this.dataset,
    required this.records,
    required this.appliedAt,
    required this.stateOutcome,
  });

  final GameMode mode;
  final DatasetKind dataset;

  /// Number of JSONL records ingested. Equal to the manifest's `records`.
  final int records;

  final DateTime appliedAt;

  /// Whether `datasetState` was inserted, updated or already current.
  final DatasetApplyOutcome stateOutcome;
}

/// Ingests one verified bundle dataset into the local database.
///
/// The whole dataset is replaced in **one** SQLite transaction:
///
/// 1. delete the rows this dataset owns (dedicated tables and its auxiliary
///    kinds in [GameRecords]);
/// 2. stream the zstd frame, parse one JSON record per line, and insert rows in
///    batches of [batchSize];
/// 3. verify the line count against the manifest and write `datasetState`;
/// 4. commit.
///
/// A throw at any point — bad JSON, a missing required field, decompression
/// failure or a count mismatch — rolls back the deletes, the inserts and the
/// state row together, so the previous dataset remains readable and applied.
/// Player data, price history and the FTS index are never written directly;
/// the `items` triggers maintain FTS for the replaced item rows.
final class DatasetIngestor {
  DatasetIngestor(
    this._database, {
    this.batchSize = 500,
    DateTime Function()? clock,
  }) : assert(batchSize > 0),
       _clock = clock ?? DateTime.now;

  final AppDatabase _database;

  /// Rows buffered before a batch insert. 500 keeps a batch well under SQLite's
  /// variable limit while amortising statement overhead.
  final int batchSize;

  final DateTime Function() _clock;

  /// Ingests [dataset] from [compressedFile] for [mode].
  ///
  /// [onProgress] is called once per processed record. It does not run on the
  /// UI isolate by itself; the scheduler owns isolate placement (task 4.6).
  Future<IngestResult> ingest({
    required GameMode mode,
    required ManifestDataset dataset,
    required File compressedFile,
    void Function(IngestProgress progress)? onProgress,
  }) async {
    if (!BundleContract.supportsDatasetSchema(dataset.schemaVersion)) {
      throw IngestError(
        IngestFailure.unsupportedSchema,
        'Dataset ${dataset.dataset.id} needs schema version '
        '${dataset.schemaVersion}; this client supports '
        '${BundleContract.appDataSchemaVersion}.',
      );
    }

    final reader = JsonlLineReader(compressedFile);
    try {
      return await _database.transaction(() async {
        await _clearDataset(dataset.dataset);

        final sinks = _IngestSinks(_database);
        final seen = <String>{};
        var records = 0;
        var lineNumber = 0;

        while (true) {
          final String? line;
          try {
            line = reader.nextLine();
          } on JsonlReadException catch (error) {
            throw _readError(error, lineNumber);
          } on FormatException catch (error) {
            throw IngestError(
              IngestFailure.invalidUtf8,
              'Line is not valid UTF-8: ${error.message}',
              line: lineNumber + 1,
              cause: error,
            );
          }
          if (line == null) {
            break;
          }
          lineNumber++;
          if (line.isEmpty) {
            throw IngestError(
              IngestFailure.malformedJson,
              'Empty line; every bundle line must be a JSON object.',
              line: lineNumber,
            );
          }

          final Map<String, Object?> record;
          try {
            final decoded = jsonDecode(line);
            if (decoded is! Map<String, Object?>) {
              throw const FormatException('not a JSON object');
            }
            record = decoded;
          } on FormatException catch (error) {
            throw IngestError(
              IngestFailure.malformedJson,
              'Line is not a JSON object: ${error.message}',
              line: lineNumber,
              cause: error,
            );
          }

          final kind = _requiredString(record, 'kind', lineNumber);
          final id = _requiredString(record, 'id', lineNumber);
          final key = '$kind\u0000$id';
          if (!seen.add(key)) {
            throw IngestError(
              IngestFailure.duplicateRecord,
              'Duplicate record "$kind/$id" in ${dataset.dataset.id}.',
              line: lineNumber,
            );
          }

          await sinks.add(record, kind: kind, id: id, line: lineNumber);
          records++;
          onProgress?.call(
            IngestProgress(
              recordsProcessed: records,
              totalRecords: dataset.records,
            ),
          );

          if (sinks.pending >= batchSize) {
            await sinks.flushAll();
          }
        }

        await sinks.flushAll();

        if (records != dataset.records) {
          throw IngestError(
            IngestFailure.recordCountMismatch,
            'Ingested $records record(s) but the manifest declares '
            '${dataset.records}.',
          );
        }

        final appliedAt = _clock();
        final state = await DatasetStateRepository(_database)
            .recordApplied(dataset, mode: mode, appliedAt: appliedAt);
        if (state is DatasetApplyRejected) {
          throw IngestError(
            IngestFailure.datasetStateRejected,
            'datasetState refused ${dataset.dataset.id} schema version '
            '${state.datasetSchemaVersion}.',
          );
        }

        return IngestResult(
          mode: mode,
          dataset: dataset.dataset,
          records: records,
          appliedAt: appliedAt,
          stateOutcome: (state as DatasetApplied).outcome,
        );
      });
    } finally {
      reader.close();
    }
  }

  IngestError _readError(JsonlReadException error, int lineNumber) {
    return IngestError(
      switch (error.failure) {
        JsonlReadFailure.missingFile => IngestFailure.missingFile,
        JsonlReadFailure.decompression => IngestFailure.decompression,
      },
      error.message,
      line: lineNumber == 0 ? null : lineNumber,
      cause: error.cause ?? error,
    );
  }

  /// Deletes the previous rows owned by [dataset], inside the transaction.
  Future<void> _clearDataset(DatasetKind dataset) async {
    switch (dataset) {
      case DatasetKind.items:
        // Explicit, rather than relying only on the foreign-key cascade, so a
        // stale join row can never survive a replacement if enforcement is
        // ever relaxed.
        await _database.delete(_database.itemCategories).go();
        await _database.delete(_database.itemTypes).go();
        await _database.delete(_database.items).go();
      case DatasetKind.tasks:
        // `taskObjectives.taskId` cascades from `tasks`, so this also removes
        // the previous objectives in the same statement.
        await _database.delete(_database.tasks).go();
      case DatasetKind.traders:
        await _database.delete(_database.traders).go();
      case DatasetKind.hideout:
        await _database.delete(_database.hideoutStations).go();
      case DatasetKind.crafts:
        await _database.delete(_database.crafts).go();
      case DatasetKind.barters:
        await _database.delete(_database.barters).go();
      case DatasetKind.maps:
        await _database.delete(_database.maps).go();
    }

    final auxiliary = _auxiliaryKinds[dataset]!;
    if (auxiliary.isNotEmpty) {
      await (_database.delete(
        _database.gameRecords,
      )..where((row) => row.kind.isIn(auxiliary))).go();
    }
  }
}

/// Record kinds stored in [GameRecords] for each dataset.
///
/// The dedicated kind of a dataset (`item`, `task`, `trader`, ...) is not in
/// this set; it is deleted from its own table. The set is exhaustive for the
/// kinds the pipeline can currently emit, so a refresh removes a collection
/// that disappeared upstream instead of leaving stale rows behind.
const _auxiliaryKinds = <DatasetKind, Set<String>>{
  DatasetKind.items: {
    'itemCategory',
    'handbookCategory',
    'fleaMarket',
    'armorMaterial',
    'playerLevel',
    'mastering',
    'skill',
    'specialItem',
    'setting',
  },
  DatasetKind.tasks: {'questItem', 'achievement', 'prestige'},
  DatasetKind.traders: {},
  DatasetKind.hideout: {},
  DatasetKind.crafts: {},
  DatasetKind.barters: {},
  DatasetKind.maps: {'mob', 'lootContainer', 'stationaryWeapon', 'goonReport'},
};

/// Typed row buffers, flushed in foreign-key-safe order.
final class _IngestSinks {
  _IngestSinks(this._database);

  final AppDatabase _database;

  late final _items = _BatchSink<Items, Item>(_database, _database.items);
  late final _itemTypes = _BatchSink<ItemTypes, ItemType>(
    _database,
    _database.itemTypes,
  );
  late final _itemCategories = _BatchSink<ItemCategories, ItemCategory>(
    _database,
    _database.itemCategories,
  );
  late final _tasks = _BatchSink<Tasks, Task>(_database, _database.tasks);
  late final _objectives = _BatchSink<TaskObjectives, TaskObjective>(
    _database,
    _database.taskObjectives,
  );
  late final _traders = _BatchSink<Traders, Trader>(
    _database,
    _database.traders,
  );
  late final _hideout = _BatchSink<HideoutStations, HideoutStation>(
    _database,
    _database.hideoutStations,
  );
  late final _crafts = _BatchSink<Crafts, Craft>(_database, _database.crafts);
  late final _barters = _BatchSink<Barters, Barter>(
    _database,
    _database.barters,
  );
  late final _maps = _BatchSink<Maps, TarkovMap>(_database, _database.maps);
  late final _gameRecords = _BatchSink<GameRecords, GameRecord>(
    _database,
    _database.gameRecords,
  );

  final Set<String> _clearedGameRecordKinds = <String>{};

  int get pending =>
      _items.length +
      _itemTypes.length +
      _itemCategories.length +
      _tasks.length +
      _objectives.length +
      _traders.length +
      _hideout.length +
      _crafts.length +
      _barters.length +
      _maps.length +
      _gameRecords.length;

  Future<void> add(
    Map<String, Object?> record, {
    required String kind,
    required String id,
    required int line,
  }) async {
    final payload = canonicalJsonEncode(record);
    switch (kind) {
      case 'item':
        _items.add(_itemRow(record, id: id, payload: payload, line: line));
        _addItemTags(record, itemId: id, line: line);
      case 'task':
        _tasks.add(_taskRow(record, id: id, payload: payload, line: line));
        _addObjectives(record, taskId: id, line: line);
      case 'trader':
        _traders.add(
          TradersCompanion.insert(
            id: id,
            name: _requiredString(record, 'name', line),
            normalizedName: _requiredString(record, 'normalizedName', line),
            payload: payload,
          ),
        );
      case 'hideoutStation':
        _hideout.add(
          HideoutStationsCompanion.insert(
            id: id,
            name: _requiredString(record, 'name', line),
            payload: payload,
          ),
        );
      case 'craft':
        _crafts.add(
          CraftsCompanion.insert(
            id: id,
            stationId: _requiredString(record, 'stationId', line),
            productItemId: _nestedRequiredString(
              record,
              'productItem',
              'itemId',
              line,
            ),
            payload: payload,
          ),
        );
      case 'barter':
        _barters.add(BartersCompanion.insert(id: id, payload: payload));
      case 'map':
        _maps.add(
          MapsCompanion.insert(
            id: id,
            name: _requiredString(record, 'name', line),
            normalizedName: _requiredString(record, 'normalizedName', line),
            payload: payload,
          ),
        );
      default:
        await _clearUnknownGameRecordKind(kind);
        _gameRecords.add(
          GameRecordsCompanion.insert(kind: kind, id: id, payload: payload),
        );
    }
  }

  /// Unknown kinds have no declared dataset owner, so the previous rows are
  /// removed the first time the kind appears in this ingest. That makes a
  /// re-ingest idempotent while keeping the delete inside the transaction.
  Future<void> _clearUnknownGameRecordKind(String kind) async {
    final first = _clearedGameRecordKinds.add(kind);
    if (!first) {
      return;
    }
    final ownedByAnotherDataset = _allAuxiliaryKinds.contains(kind);
    if (ownedByAnotherDataset) {
      // The dataset's own auxiliary kinds were already deleted up front. A
      // kind that belongs to another dataset is contract-invalid here; leaving
      // the existing rows alone is safer than deleting another dataset's data.
      return;
    }
    await (_database.delete(
      _database.gameRecords,
    )..where((row) => row.kind.equals(kind))).go();
  }

  Future<void> flushAll() async {
    // Tasks must exist before their objectives for the immediate foreign key.
    await _tasks.flush();
    await _objectives.flush();
    // Items must exist before their type/category rows for the same reason.
    await _items.flush();
    await _itemTypes.flush();
    await _itemCategories.flush();
    await _traders.flush();
    await _hideout.flush();
    await _crafts.flush();
    await _barters.flush();
    await _maps.flush();
    await _gameRecords.flush();
  }

  /// Buffers the multi-valued `types`, `categoryIds` and
  /// `handbookCategoryIds` arrays as indexed rows.
  ///
  /// The fields are optional only for hand-written test records; a published
  /// item record always carries them. A missing field yields no rows, and a
  /// present non-array or non-string entry is a contract violation.
  void _addItemTags(
    Map<String, Object?> record, {
    required String itemId,
    required int line,
  }) {
    for (final type
        in _optionalStringList(record, 'types', line) ?? const <String>[]) {
      _itemTypes.add(ItemTypesCompanion.insert(itemId: itemId, type: type));
    }
    for (final (field, kind) in const [
      ('categoryIds', 'item'),
      ('handbookCategoryIds', 'handbook'),
    ]) {
      final ids = _optionalStringList(record, field, line);
      if (ids == null) {
        continue;
      }
      for (final categoryId in ids) {
        _itemCategories.add(
          ItemCategoriesCompanion.insert(
            itemId: itemId,
            categoryId: categoryId,
            categoryKind: kind,
          ),
        );
      }
    }
  }

  void _addObjectives(
    Map<String, Object?> record, {
    required String taskId,
    required int line,
  }) {
    final raw = record['objectives'];
    if (raw == null) {
      return;
    }
    if (raw is! List<Object?>) {
      throw IngestError(
        IngestFailure.invalidRecord,
        'task.objectives must be an array.',
        line: line,
      );
    }
    for (final entry in raw) {
      if (entry is! Map<String, Object?>) {
        throw IngestError(
          IngestFailure.invalidRecord,
          'task.objectives entries must be objects.',
          line: line,
        );
      }
      final id = _requiredString(entry, 'id', line);
      final type = _requiredString(entry, 'type', line);
      _objectives.add(
        TaskObjectivesCompanion.insert(
          id: id,
          taskId: taskId,
          type: type,
          description: Value(_optionalString(entry, 'description', line) ?? ''),
          count: Value(_optionalInt(entry, 'count', line)),
          payload: canonicalJsonEncode(entry),
        ),
      );
    }
  }

  static final Set<String> _allAuxiliaryKinds = {
    for (final kinds in _auxiliaryKinds.values) ...kinds,
  };
}

final class _BatchSink<T extends Table, D extends DataClass> {
  _BatchSink(this._database, this._table);

  final AppDatabase _database;
  final TableInfo<T, D> _table;
  final List<Insertable<D>> _rows = <Insertable<D>>[];

  int get length => _rows.length;

  void add(Insertable<D> row) => _rows.add(row);

  Future<void> flush() async {
    if (_rows.isEmpty) {
      return;
    }
    final rows = List<Insertable<D>>.of(_rows);
    _rows.clear();
    await _database.batch((batch) => batch.insertAll(_table, rows));
  }
}

Insertable<Item> _itemRow(
  Map<String, Object?> record, {
  required String id,
  required String payload,
  required int line,
}) {
  final price = record['price'];
  final priceMap = price == null
      ? const <String, Object?>{}
      : price is Map<String, Object?>
      ? price
      : throw IngestError(
          IngestFailure.invalidRecord,
          'item.price must be an object or null.',
          line: line,
        );

  final types = _optionalStringList(record, 'types', line);

  return ItemsCompanion.insert(
    id: id,
    name: _requiredString(record, 'name', line),
    shortName: _requiredString(record, 'shortName', line, allowEmpty: true),
    normalizedName: _requiredString(record, 'normalizedName', line),
    weight: Value(_optionalDouble(record, 'weight', line)),
    width: Value(_optionalInt(record, 'width', line)),
    height: Value(_optionalInt(record, 'height', line)),
    basePrice: Value(_optionalInt(record, 'basePrice', line)),
    avg24hPrice: Value(_optionalInt(priceMap, 'avg24h', line)),
    lastLowPrice: Value(_optionalInt(priceMap, 'lastLow', line)),
    changeLast48hPercent: Value(
      _optionalDouble(priceMap, 'change48hPercent', line),
    ),
    priceObservedAt: Value(_optionalDateTime(priceMap, 'observedAt', line)),
    iconLink: Value(_optionalString(record, 'iconLink', line)),
    gridImageLink: Value(_optionalString(record, 'gridImageLink', line)),
    minLevelForFlea: Value(_optionalInt(record, 'minLevelForFlea', line)),
    // `noFlea` is the bundle's marker for an item that cannot be traded on the
    // flea market; `minLevelForFlea` is a level gate, not a ban. No `types`
    // field means the record is too old to know, so eligibility stays null.
    fleaEligible: Value(types == null ? null : !types.contains('noFlea')),
    payload: payload,
  );
}

Insertable<Task> _taskRow(
  Map<String, Object?> record, {
  required String id,
  required String payload,
  required int line,
}) {
  return TasksCompanion.insert(
    id: id,
    name: _requiredString(record, 'name', line),
    traderId: Value(_optionalString(record, 'traderId', line)),
    mapId: Value(_optionalString(record, 'mapId', line)),
    minPlayerLevel: Value(_optionalInt(record, 'minPlayerLevel', line)),
    experience: Value(_optionalInt(record, 'experience', line)),
    kappaRequired: Value(_optionalBool(record, 'kappaRequired', line) ?? false),
    payload: payload,
  );
}

String _nestedRequiredString(
  Map<String, Object?> record,
  String parent,
  String field,
  int line,
) {
  final container = record[parent];
  if (container is Map) {
    final value = container[field];
    if (value is String && value.isNotEmpty) return value;
  }
  throw IngestError(
    IngestFailure.invalidRecord,
    'Missing or invalid required string field "$parent.$field"',
    line: line,
  );
}

String _requiredString(
  Map<String, Object?> record,
  String field,
  int line, {
  bool allowEmpty = false,
}) {
  final value = record[field];
  if (value is String && (allowEmpty || value.isNotEmpty)) {
    return value;
  }
  throw IngestError(
    IngestFailure.invalidRecord,
    'Missing or invalid required string field "$field".',
    line: line,
  );
}

String? _optionalString(Map<String, Object?> record, String field, int line) {
  final value = record[field];
  if (value == null || value is String) {
    return value as String?;
  }
  throw IngestError(
    IngestFailure.invalidRecord,
    'Field "$field" must be a string or null.',
    line: line,
  );
}

int? _optionalInt(Map<String, Object?> record, String field, int line) {
  final value = record[field];
  if (value == null || value is int) {
    return value as int?;
  }
  throw IngestError(
    IngestFailure.invalidRecord,
    'Field "$field" must be an integer or null.',
    line: line,
  );
}

double? _optionalDouble(Map<String, Object?> record, String field, int line) {
  final value = record[field];
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw IngestError(
    IngestFailure.invalidRecord,
    'Field "$field" must be a number or null.',
    line: line,
  );
}

bool? _optionalBool(Map<String, Object?> record, String field, int line) {
  final value = record[field];
  if (value == null || value is bool) {
    return value as bool?;
  }
  throw IngestError(
    IngestFailure.invalidRecord,
    'Field "$field" must be a boolean or null.',
    line: line,
  );
}

/// Reads an optional array of strings. `null` means the field is absent.
///
/// An empty array is meaningful (the item has no tags) and returns an empty
/// list, distinct from the `null` an old record may have.
List<String>? _optionalStringList(
  Map<String, Object?> record,
  String field,
  int line,
) {
  final value = record[field];
  if (value == null) {
    return null;
  }
  if (value is! List<Object?>) {
    throw IngestError(
      IngestFailure.invalidRecord,
      'Field "$field" must be an array of strings or null.',
      line: line,
    );
  }
  final entries = <String>[];
  for (final entry in value) {
    if (entry is! String || entry.isEmpty) {
      throw IngestError(
        IngestFailure.invalidRecord,
        'Field "$field" must contain only non-empty strings.',
        line: line,
      );
    }
    entries.add(entry);
  }
  return entries;
}

/// Parses an ISO 8601 timestamp (the bundle's `observedAt` shape) into UTC.
///
/// A missing or `null` field is "unknown" and returns `null`. A present but
/// unparsable value is a contract violation: silently dropping it would turn a
/// malformed observation into an unqualified current price.
DateTime? _optionalDateTime(
  Map<String, Object?> record,
  String field,
  int line,
) {
  final value = record[field];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw IngestError(
      IngestFailure.invalidRecord,
      'Field "$field" must be an ISO 8601 string or null.',
      line: line,
    );
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw IngestError(
      IngestFailure.invalidRecord,
      'Field "$field" is not a valid ISO 8601 timestamp: "$value".',
      line: line,
    );
  }
  return parsed.toUtc();
}
