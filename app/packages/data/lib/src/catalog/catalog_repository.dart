import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'catalog_query.dart';
import 'item_detail.dart';

/// Read-side execution of [CatalogQuery] over the local item catalog.
///
/// The repository is pure data access: it never touches widgets or images and
/// works with a plain in-memory database in tests. Text search uses the
/// `items_fts` index created in `fts.dart`; category and type filters use the
/// `itemCategories` and `itemTypes` join tables; price and weight filters use
/// the columns on `items`.
///
/// Count, page and tag lookups run in one read transaction so a concurrent
/// bundle ingestion (which commits in a single transaction) cannot produce a
/// page whose `total` and rows disagree.
final class CatalogRepository {
  const CatalogRepository(this._database);

  final AppDatabase _database;

  /// Runs [query] and returns one typed page.
  ///
  /// Pagination is clamped through [CatalogQuery.effectiveLimit] and
  /// [CatalogQuery.effectiveOffset]; [CatalogPage.limit] and
  /// [CatalogPage.offset] report the values actually used.
  ///
  /// A text filter that contains no letter/digit token returns an empty page
  /// without issuing a query, because FTS5 has no term to match. An empty
  /// `text` (or whitespace) is not a filter at all.
  Future<CatalogPage> query(CatalogQuery query) async {
    final filters = query.filters;
    final limit = query.effectiveLimit;
    final offset = query.effectiveOffset;

    final match = _matchExpression(filters.text);
    if (query.hasText && match == null) {
      return CatalogPage(
        items: const [],
        total: 0,
        limit: limit,
        offset: offset,
      );
    }

    final where = _buildWhere(filters, match);
    final orderSql = _orderBy(query, hasMatch: match != null);

    return _database.transaction(() async {
      final totalRow = await _database
          .customSelect(
            'SELECT count(*) AS n ${where.join} ${where.whereSql}',
            variables: where.variables,
          )
          .getSingle();
      final total = totalRow.read<int>('n');

      if (total == 0) {
        return CatalogPage(
          items: const [],
          total: 0,
          limit: limit,
          offset: offset,
        );
      }

      final rows = await _database
          .customSelect(
            'SELECT items.* ${where.join} ${where.whereSql} '
            'ORDER BY $orderSql LIMIT ? OFFSET ?',
            variables: [
              ...where.variables,
              Variable<int>(limit),
              Variable<int>(offset),
            ],
          )
          .get();

      final ids = [for (final row in rows) row.read<String>('id')];
      final tags = await _loadTags(ids);

      return CatalogPage(
        items: [for (final row in rows) _readSummary(row, tags)],
        total: total,
        limit: limit,
        offset: offset,
      );
    });
  }

  /// The number of items matching [filters], ignoring pagination.
  ///
  /// Equivalent to `(await query(q)).total` but without reading a page.
  Future<int> count(CatalogQuery query) async {
    final match = _matchExpression(query.filters.text);
    if (query.hasText && match == null) {
      return 0;
    }

    final where = _buildWhere(query.filters, match);
    final row = await _database
        .customSelect(
          'SELECT count(*) AS n ${where.join} ${where.whereSql}',
          variables: where.variables,
        )
        .getSingle();
    return row.read<int>('n');
  }

  /// The full detail record for [itemId], or `null` when the current dataset
  /// has no such item.
  ///
  /// Reads the indexed `items` columns plus the canonical `payload`, and the
  /// type/category tag rows. Category display names are resolved from the
  /// bundle's `itemCategory`/`handbookCategory` records when present; a
  /// category without a matching record keeps its id so an incomplete dataset
  /// is still usable. Corrupt payload JSON throws instead of returning a
  /// half-filled detail, so the screen never renders invented values.
  Future<ItemDetail?> itemDetail(String itemId) async {
    final id = itemId.trim();
    if (id.isEmpty) {
      return null;
    }

    final row = await (_database.select(
      _database.items,
    )..where((item) => item.id.equals(id))).getSingleOrNull();
    if (row == null) {
      return null;
    }

    final tags = await _loadTags([id]);
    final categoryIds = [
      ...?tags.categories[id],
      ...?tags.handbookCategories[id],
    ];

    return ItemDetail.fromPayload(
      id: row.id,
      name: row.name,
      shortName: row.shortName,
      weight: row.weight,
      width: row.width,
      height: row.height,
      payload: row.payload,
      types: tags.types[id] ?? const [],
      categoryIds: tags.categories[id] ?? const [],
      handbookCategoryIds: tags.handbookCategories[id] ?? const [],
      categoryNames: await _loadCategoryNames(categoryIds),
    );
  }

  /// Display names for [categoryIds] from the auxiliary bundle records.
  Future<Map<String, String>> _loadCategoryNames(
    List<String> categoryIds,
  ) async {
    if (categoryIds.isEmpty) {
      return const {};
    }
    final placeholders = List.filled(categoryIds.length, '?').join(', ');
    final rows = await _database
        .customSelect(
          'SELECT id, payload FROM gameRecords '
          "WHERE kind IN ('itemCategory', 'handbookCategory') "
          'AND id IN ($placeholders)',
          variables: _idVariables(categoryIds),
        )
        .get();

    final names = <String, String>{};
    for (final row in rows) {
      try {
        final payload = jsonDecode(row.read<String>('payload'));
        if (payload is Map<String, Object?>) {
          final name = payload['name'];
          if (name is String && name.trim().isNotEmpty) {
            names[row.read<String>('id')] = name;
          }
        }
      } on FormatException {
        // A category record without decodable JSON must not hide the category:
        // the caller falls back to the id.
      }
    }
    return names;
  }

  _QueryParts _buildWhere(CatalogFilters filters, String? match) {
    final where = _WhereBuilder();
    if (match != null) {
      where.add('items_fts MATCH ?', Variable<String>(match));
    }
    final categoryId = _nonBlank(filters.categoryId);
    if (categoryId != null) {
      where.add(
        'EXISTS (SELECT 1 FROM itemCategories c '
        'WHERE c.itemId = items.id AND c.categoryId = ? '
        'AND c.categoryKind = ?)',
        Variable<String>(categoryId),
        Variable<String>(filters.categoryKind.name),
      );
    }
    final type = _nonBlank(filters.type);
    if (type != null) {
      where.add(
        'EXISTS (SELECT 1 FROM itemTypes t '
        'WHERE t.itemId = items.id AND t.type = ?)',
        Variable<String>(type),
      );
    }
    if (filters.fleaEligible != null) {
      where.add(
        'items.fleaEligible = ?',
        Variable<bool>(filters.fleaEligible!),
      );
    }
    if (filters.minPrice != null) {
      where.add(
        'items.lastLowPrice IS NOT NULL AND items.lastLowPrice >= ?',
        Variable<int>(filters.minPrice!),
      );
    }
    if (filters.maxPrice != null) {
      where.add(
        'items.lastLowPrice IS NOT NULL AND items.lastLowPrice <= ?',
        Variable<int>(filters.maxPrice!),
      );
    }

    return _QueryParts(
      join: match == null
          ? 'FROM items'
          : 'FROM items JOIN items_fts ON items_fts.rowid = items.rowid',
      whereSql: where.isEmpty ? '' : 'WHERE ${where.sql}',
      variables: where.variables,
    );
  }

  ItemSummary _readSummary(QueryRow row, _ItemTags tags) {
    final id = row.read<String>('id');
    return ItemSummary(
      id: id,
      name: row.read<String>('name'),
      shortName: row.read<String>('shortName'),
      weight: row.readNullable<double>('weight'),
      width: row.readNullable<int>('width'),
      height: row.readNullable<int>('height'),
      basePrice: row.readNullable<int>('basePrice'),
      avg24hPrice: row.readNullable<int>('avg24hPrice'),
      fleaPrice: row.readNullable<int>('lastLowPrice'),
      change48hPercent: row.readNullable<double>('changeLast48hPercent'),
      priceObservedAt: row.readNullable<DateTime>('priceObservedAt'),
      minLevelForFlea: row.readNullable<int>('minLevelForFlea'),
      fleaEligible: row.readNullable<bool>('fleaEligible'),
      iconLink: row.readNullable<String>('iconLink'),
      types: tags.types[id] ?? const [],
      categoryIds: tags.categories[id] ?? const [],
      handbookCategoryIds: tags.handbookCategories[id] ?? const [],
    );
  }

  String _orderBy(CatalogQuery query, {required bool hasMatch}) {
    final sort = query.sort;
    if (sort == null) {
      return hasMatch
          ? 'items_fts.rank, items.name COLLATE NOCASE ASC, items.id ASC'
          : 'items.name COLLATE NOCASE ASC, items.id ASC';
    }

    final direction = sort.descending ? 'DESC' : 'ASC';
    return switch (sort.field) {
      CatalogSortField.name =>
        'items.name COLLATE NOCASE $direction, items.id $direction',
      CatalogSortField.basePrice =>
        '(items.basePrice IS NULL) ASC, items.basePrice $direction, '
            'items.name COLLATE NOCASE ASC, items.id ASC',
      CatalogSortField.fleaPrice =>
        '(items.lastLowPrice IS NULL) ASC, items.lastLowPrice $direction, '
            'items.name COLLATE NOCASE ASC, items.id ASC',
      CatalogSortField.weight =>
        '(items.weight IS NULL) ASC, items.weight $direction, '
            'items.name COLLATE NOCASE ASC, items.id ASC',
    };
  }

  Future<_ItemTags> _loadTags(List<String> ids) async {
    if (ids.isEmpty) {
      return const _ItemTags.empty();
    }
    final placeholders = List.filled(ids.length, '?').join(', ');

    final typeRows = await _database
        .customSelect(
          'SELECT itemId, type FROM itemTypes '
          'WHERE itemId IN ($placeholders)',
          variables: _idVariables(ids),
        )
        .get();
    final types = <String, List<String>>{};
    for (final row in typeRows) {
      types
          .putIfAbsent(row.read<String>('itemId'), () => <String>[])
          .add(row.read<String>('type'));
    }

    final categoryRows = await _database
        .customSelect(
          'SELECT itemId, categoryId, categoryKind FROM itemCategories '
          'WHERE itemId IN ($placeholders)',
          variables: _idVariables(ids),
        )
        .get();
    final categories = <String, List<String>>{};
    final handbookCategories = <String, List<String>>{};
    for (final row in categoryRows) {
      final bucket = row.read<String>('categoryKind') == 'handbook'
          ? handbookCategories
          : categories;
      bucket
          .putIfAbsent(row.read<String>('itemId'), () => <String>[])
          .add(row.read<String>('categoryId'));
    }

    for (final list in [
      ...types.values,
      ...categories.values,
      ...handbookCategories.values,
    ]) {
      list.sort();
    }

    return _ItemTags(
      types: types,
      categories: categories,
      handbookCategories: handbookCategories,
    );
  }

  static List<Variable<String>> _idVariables(List<String> ids) => [
    for (final id in ids) Variable<String>(id),
  ];
}

/// The `FROM … JOIN … WHERE …` fragment shared by the count and page queries.
final class _QueryParts {
  const _QueryParts({
    required this.join,
    required this.whereSql,
    required this.variables,
  });

  final String join;
  final String whereSql;
  final List<Variable<Object>> variables;
}

/// Builds the `WHERE` fragment and its positional variables in one pass, so
/// the SQL text and the variable order cannot drift apart.
final class _WhereBuilder {
  final List<String> _clauses = <String>[];
  final List<Variable<Object>> variables = <Variable<Object>>[];

  bool get isEmpty => _clauses.isEmpty;

  String get sql => _clauses.join(' AND ');

  void add(String clause, Variable<Object> first, [Variable<Object>? second]) {
    _clauses.add(clause);
    variables.add(first);
    if (second != null) {
      variables.add(second);
    }
  }
}

final class _ItemTags {
  const _ItemTags({
    required this.types,
    required this.categories,
    required this.handbookCategories,
  });

  const _ItemTags.empty()
    : types = const {},
      categories = const {},
      handbookCategories = const {};

  final Map<String, List<String>> types;
  final Map<String, List<String>> categories;
  final Map<String, List<String>> handbookCategories;
}

/// Turns free text into an FTS5 expression of prefix terms.
///
/// Only Unicode letters and digits become terms, so characters that are FTS5
/// syntax (`"`, `*`, `:`, `-`, parentheses) in the user's input can never
/// produce a syntax error. Terms are ANDed, matching the "narrow as the user
/// types" behavior of the catalog. Returns `null` when the text has no term.
String? _matchExpression(String? text) {
  if (text == null) {
    return null;
  }
  final tokens = RegExp(
    r'[\p{L}\p{N}]+',
    unicode: true,
  ).allMatches(text).map((match) => match[0]!).toList();
  if (tokens.isEmpty) {
    return null;
  }
  return tokens.map((token) => '"$token"*').join(' ');
}

String? _nonBlank(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}
