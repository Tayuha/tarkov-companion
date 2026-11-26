import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'quest_query.dart';

/// Read-side execution of [QuestQuery] over the local quest catalog.
///
/// The repository is pure data access: it never touches widgets and works with
/// a plain in-memory database in tests.
///
/// ## Name search and sort key
///
/// The quest bundle already publishes `normalizedName` (lower-case and
/// diacritic-free) on every `task` record, but the shipped schema has no
/// `tasks.normalizedName` column and this layer deliberately does not add one.
/// The stored `tasks.payload` is the canonical JSONL record, so the query reads
/// the existing key with `json_extract` and falls back to `lower(name)` for a
/// hand-written record without it. Text search and the name sort therefore use
/// the same key, which keeps them consistent. Promoting the field to an indexed
/// column is a schema migration for a later task if quest volume ever makes the
/// JSON extraction hot; at a few hundred quests the difference is not
/// measurable.
///
/// Count and page queries run in one read transaction so a concurrent bundle
/// ingestion (which commits in a single transaction) cannot produce a page
/// whose `total` and rows disagree.
///
/// Progress is read with a `LEFT JOIN` on `questProgress` scoped to
/// `QuestQuery.profileId`. No row means [QuestProgressState.notStarted], and
/// rows for other profiles are never considered.
final class QuestRepository {
  const QuestRepository(this._database);

  final AppDatabase _database;

  /// The folded name key shared by text search and name sorting.
  ///
  /// `json_valid` guards a malformed payload: the ingestor writes canonical
  /// JSON, so this is defensive rather than expected. `lower(name)` keeps a
  /// record without `normalizedName` readable (ASCII case-insensitive only).
  static const String _normalizedNameSql =
      r"COALESCE(CASE WHEN json_valid(tasks.payload) "
      r"THEN json_extract(tasks.payload, '$.normalizedName') END, "
      r'lower(tasks.name))';

  /// Runs [query] and returns one typed page.
  ///
  /// Pagination is clamped through [QuestQuery.effectiveLimit] and
  /// [QuestQuery.effectiveOffset]; [QuestPage.limit] and [QuestPage.offset]
  /// report the values actually used.
  ///
  /// A text filter that contains no letter/digit token returns an empty page
  /// without issuing a query, because no token can match. An empty `text` (or
  /// whitespace) is not a filter at all.
  Future<QuestPage> query(QuestQuery query) async {
    final limit = query.effectiveLimit;
    final offset = query.effectiveOffset;
    final tokens = questSearchTokens(query.filters.text);

    if (query.hasText && tokens.isEmpty) {
      return QuestPage(
        quests: const [],
        total: 0,
        limit: limit,
        offset: offset,
      );
    }

    final parts = _buildParts(query, tokens);

    return _database.transaction(() async {
      final totalRow = await _database
          .customSelect(
            'SELECT count(*) AS n ${parts.fromSql} ${parts.whereSql}',
            variables: parts.variables,
          )
          .getSingle();
      final total = totalRow.read<int>('n');

      if (total == 0) {
        return QuestPage(
          quests: const [],
          total: 0,
          limit: limit,
          offset: offset,
        );
      }

      final rows = await _database
          .customSelect(
            'SELECT tasks.id, tasks.name, tasks.traderId, tasks.mapId, '
            'tasks.minPlayerLevel, tasks.experience, tasks.kappaRequired, '
            '${parts.progressColumn} '
            '${parts.fromSql} ${parts.whereSql} '
            'ORDER BY ${_orderBy(query.sort)} LIMIT ? OFFSET ?',
            variables: [
              ...parts.variables,
              Variable<int>(limit),
              Variable<int>(offset),
            ],
          )
          .get();

      return QuestPage(
        quests: [for (final row in rows) _readSummary(row)],
        total: total,
        limit: limit,
        offset: offset,
      );
    });
  }

  /// The number of quests matching [query], ignoring pagination.
  ///
  /// Equivalent to `(await query(q)).total` but without reading a page.
  Future<int> count(QuestQuery query) async {
    final tokens = questSearchTokens(query.filters.text);
    if (query.hasText && tokens.isEmpty) {
      return 0;
    }

    final parts = _buildParts(query, tokens);
    final row = await _database
        .customSelect(
          'SELECT count(*) AS n ${parts.fromSql} ${parts.whereSql}',
          variables: parts.variables,
        )
        .getSingle();
    return row.read<int>('n');
  }

  _QueryParts _buildParts(QuestQuery query, List<String> tokens) {
    final filters = query.filters;
    final profileId = _nonBlank(query.profileId);
    final where = _WhereBuilder();

    for (final token in tokens) {
      where.add('$_normalizedNameSql LIKE ?', Variable<String>('%$token%'));
    }

    final traderId = _nonBlank(filters.traderId);
    if (traderId != null) {
      where.add('tasks.traderId = ?', Variable<String>(traderId));
    }

    final mapId = _nonBlank(filters.mapId);
    if (mapId != null) {
      where.add('tasks.mapId = ?', Variable<String>(mapId));
    }

    if (filters.minPlayerLevel != null) {
      where.add(
        'tasks.minPlayerLevel = ?',
        Variable<int>(filters.minPlayerLevel!),
      );
    }

    if (filters.maxPlayerLevel != null) {
      where.add(
        'tasks.minPlayerLevel IS NOT NULL AND tasks.minPlayerLevel <= ?',
        Variable<int>(filters.maxPlayerLevel!),
      );
    }

    final state = filters.state;
    if (state != null) {
      if (profileId == null) {
        // No profile means no progress row can exist, so only `notStarted`
        // matches. Other states deliberately match nothing.
        if (state != QuestProgressState.notStarted) {
          where.addRaw('1 = 0');
        }
      } else {
        switch (state) {
          case QuestProgressState.notStarted:
            where.addRaw(
              '(qp.state IS NULL OR qp.state NOT IN '
              "('in-progress', 'completed', 'failed'))",
            );
          case QuestProgressState.inProgress:
            where.addRaw("qp.state = 'in-progress'");
          case QuestProgressState.completed:
            where.addRaw("qp.state = 'completed'");
          case QuestProgressState.failed:
            where.addRaw("qp.state = 'failed'");
        }
      }
    }

    return _QueryParts(
      fromSql: profileId == null
          ? 'FROM tasks'
          : 'FROM tasks LEFT JOIN questProgress AS qp '
                'ON qp.questId = tasks.id AND qp.profileId = ?',
      whereSql: where.isEmpty ? '' : 'WHERE ${where.sql}',
      progressColumn: profileId == null
          ? 'NULL AS progressState'
          : 'qp.state AS progressState',
      variables: [
        if (profileId != null) Variable<String>(profileId),
        ...where.variables,
      ],
    );
  }

  QuestSummary _readSummary(QueryRow row) {
    return QuestSummary(
      id: row.read<String>('id'),
      name: row.read<String>('name'),
      traderId: row.readNullable<String>('traderId'),
      mapId: row.readNullable<String>('mapId'),
      minPlayerLevel: row.readNullable<int>('minPlayerLevel'),
      experience: row.readNullable<int>('experience'),
      kappaRequired: row.read<bool>('kappaRequired'),
      progressState: QuestProgressState.fromStoredValue(
        row.readNullable<String>('progressState'),
      ),
    );
  }

  String _orderBy(QuestSort? sort) {
    final effective = sort ?? const QuestSort(QuestSortField.name);
    final direction = effective.descending ? 'DESC' : 'ASC';
    const name = _normalizedNameSql;

    // `(column IS NULL) ASC` keeps missing values last in both directions.
    // Name and id always ascend as tie-breakers, so equal primary values render
    // in the same order on every page and in both directions.
    return switch (effective.field) {
      QuestSortField.name => '$name $direction, tasks.id ASC',
      QuestSortField.minPlayerLevel =>
        '(tasks.minPlayerLevel IS NULL) ASC, '
            'tasks.minPlayerLevel $direction, $name ASC, tasks.id ASC',
      QuestSortField.traderId =>
        '(tasks.traderId IS NULL) ASC, '
            'tasks.traderId $direction, $name ASC, tasks.id ASC',
      QuestSortField.mapId =>
        '(tasks.mapId IS NULL) ASC, '
            'tasks.mapId $direction, $name ASC, tasks.id ASC',
    };
  }
}

/// The `FROM … WHERE …` fragment shared by the count and page queries.
final class _QueryParts {
  const _QueryParts({
    required this.fromSql,
    required this.whereSql,
    required this.progressColumn,
    required this.variables,
  });

  final String fromSql;
  final String whereSql;

  /// The selected `progressState` expression, or `NULL` without a profile.
  final String progressColumn;

  final List<Variable<Object>> variables;
}

/// Builds the `WHERE` fragment and its positional variables in one pass, so
/// the SQL text and the variable order cannot drift apart.
final class _WhereBuilder {
  final List<String> _clauses = <String>[];
  final List<Variable<Object>> variables = <Variable<Object>>[];

  bool get isEmpty => _clauses.isEmpty;

  String get sql => _clauses.join(' AND ');

  void add(String clause, Variable<Object> value) {
    _clauses.add(clause);
    variables.add(value);
  }

  void addRaw(String clause) => _clauses.add(clause);
}

String? _nonBlank(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}
