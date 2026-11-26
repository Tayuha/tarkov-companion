/// Immutable values that describe a catalog query and its typed results.
///
/// The data layer owns filtering, sorting and pagination semantics so the
/// catalog screen (task 5.2) only renders rows and forwards the user's choices.
/// Filters are deliberately independent: each one can be set, combined with
/// the others, or cleared on its own with a `with…(null)` call.
library;

/// The category tree a [CatalogFilters.categoryId] belongs to.
///
/// An item carries two independent category lists in the bundle:
/// `categoryIds` (the in-game hierarchy) and `handbookCategoryIds` (the
/// handbook tree). A filter must say which one it means because ids are only
/// meaningful inside their tree.
enum CatalogCategoryKind {
  /// `items.categoryIds`.
  item,

  /// `items.handbookCategoryIds`.
  handbook,
}

/// A sortable item field.
enum CatalogSortField {
  /// Display name, case-insensitive.
  name,

  /// Trader-independent base price.
  basePrice,

  /// Latest flea-market low (`price.lastLow`).
  fleaPrice,

  /// Weight in kilograms.
  weight,
}

/// One sort instruction: a field and a direction.
///
/// Ties are always broken by name (case-insensitive) and then by item id, so a
/// page is stable across calls. Items with a null value for the sorted field
/// are placed last in **both** directions: "no data" is not "the smallest
/// price".
final class CatalogSort {
  const CatalogSort(this.field, {this.descending = false});

  final CatalogSortField field;
  final bool descending;

  CatalogSort reversed() => CatalogSort(field, descending: !descending);

  @override
  bool operator ==(Object other) =>
      other is CatalogSort &&
      other.field == field &&
      other.descending == descending;

  @override
  int get hashCode => Object.hash(field, descending);

  @override
  String toString() => 'CatalogSort(${field.name}, descending: $descending)';
}

/// The structured filters of a catalog query.
///
/// Every field is optional and they combine with AND. A `null` field means
/// "no constraint", so clearing one filter never disturbs the others.
///
/// * [text] is full-text search over `name`, `shortName` and `normalizedName`
///   (the `items_fts` index). It is tokenized to Unicode letter/digit runs and
///   every token becomes a prefix term, so `m4a` matches `M4A1` while the user
///   types. A text with no token (for example `"--"`) matches nothing.
/// * [categoryId] with [categoryKind] matches an exact category membership.
///   Ancestor categories are already present in the bundle arrays, so no
///   hierarchy walk is needed.
/// * [type] matches one bundle `types[]` value exactly (`ammo`, `mods`,
///   `noFlea`, ...).
/// * [fleaEligible] matches the derived `noFlea` flag. An item migrated from
///   schema v4 before its next bundle has an unknown flag and therefore
///   matches neither `true` nor `false`.
/// * [minPrice] and [maxPrice] are inclusive bounds on the latest flea low
///   (`items.lastLowPrice`). Setting either bound excludes items that have no
///   observed flea price, because "no price" cannot be inside a range.
final class CatalogFilters {
  const CatalogFilters({
    this.text,
    this.categoryId,
    this.categoryKind = CatalogCategoryKind.item,
    this.type,
    this.fleaEligible,
    this.minPrice,
    this.maxPrice,
  });

  final String? text;
  final String? categoryId;
  final CatalogCategoryKind categoryKind;
  final String? type;
  final bool? fleaEligible;
  final int? minPrice;
  final int? maxPrice;

  /// Whether no filter is active.
  bool get isEmpty =>
      _isBlank(text) &&
      _isBlank(categoryId) &&
      _isBlank(type) &&
      fleaEligible == null &&
      minPrice == null &&
      maxPrice == null;

  /// Whether at least one filter is active.
  bool get isNotEmpty => !isEmpty;

  /// Replaces the search text; `null` (or blank) clears it.
  CatalogFilters withText(String? value) => CatalogFilters(
    text: value,
    categoryId: categoryId,
    categoryKind: categoryKind,
    type: type,
    fleaEligible: fleaEligible,
    minPrice: minPrice,
    maxPrice: maxPrice,
  );

  /// Replaces the category filter; `null` (or blank) clears it.
  ///
  /// [kind] may be changed independently even when [id] is null.
  CatalogFilters withCategory(String? id, {CatalogCategoryKind? kind}) =>
      CatalogFilters(
        text: text,
        categoryId: id,
        categoryKind: kind ?? categoryKind,
        type: type,
        fleaEligible: fleaEligible,
        minPrice: minPrice,
        maxPrice: maxPrice,
      );

  /// Replaces the type filter; `null` (or blank) clears it.
  CatalogFilters withType(String? value) => CatalogFilters(
    text: text,
    categoryId: categoryId,
    categoryKind: categoryKind,
    type: value,
    fleaEligible: fleaEligible,
    minPrice: minPrice,
    maxPrice: maxPrice,
  );

  /// Replaces the flea-eligibility filter; `null` clears it.
  CatalogFilters withFleaEligible(bool? value) => CatalogFilters(
    text: text,
    categoryId: categoryId,
    categoryKind: categoryKind,
    type: type,
    fleaEligible: value,
    minPrice: minPrice,
    maxPrice: maxPrice,
  );

  /// Replaces the inclusive flea-price range; either bound may be `null`.
  CatalogFilters withPriceRange({int? min, int? max}) => CatalogFilters(
    text: text,
    categoryId: categoryId,
    categoryKind: categoryKind,
    type: type,
    fleaEligible: fleaEligible,
    minPrice: min,
    maxPrice: max,
  );

  /// Clears every filter.
  CatalogFilters clear() => const CatalogFilters();

  @override
  String toString() =>
      'CatalogFilters(text: $text, categoryId: $categoryId, '
      'categoryKind: $categoryKind.name, type: $type, '
      'fleaEligible: $fleaEligible, minPrice: $minPrice, maxPrice: $maxPrice)';
}

/// A complete catalog query: filters, an optional sort and a page window.
///
/// [limit] and [offset] are clamped deterministically when [effectiveLimit] and
/// [effectiveOffset] are read, rather than rejected:
///
/// * `limit < 1` becomes `1`, `limit > maxLimit` becomes [maxLimit];
/// * `offset < 0` becomes `0`.
///
/// This keeps a bad UI state (a stale page number, a huge page size) from
/// throwing in the middle of a frame while still bounding the work a caller can
/// request.
final class CatalogQuery {
  const CatalogQuery({
    this.filters = const CatalogFilters(),
    this.sort,
    this.limit = defaultLimit,
    this.offset = 0,
  });

  /// Page size used when the caller does not choose one.
  static const int defaultLimit = 50;

  /// Largest page a single query may return.
  static const int maxLimit = 200;

  final CatalogFilters filters;

  /// The requested order, or `null` for the default.
  ///
  /// The default is relevance when [CatalogFilters.text] is active and
  /// ascending name otherwise. An explicit sort always wins, including over
  /// relevance.
  final CatalogSort? sort;

  final int limit;
  final int offset;

  /// [limit] clamped to `1..maxLimit`.
  int get effectiveLimit {
    if (limit < 1) {
      return 1;
    }
    if (limit > maxLimit) {
      return maxLimit;
    }
    return limit;
  }

  /// [offset] clamped to `>= 0`.
  int get effectiveOffset => offset < 0 ? 0 : offset;

  /// Whether this query performs a full-text search.
  bool get hasText => filters.text != null && filters.text!.trim().isNotEmpty;

  CatalogQuery withFilters(CatalogFilters value) =>
      CatalogQuery(filters: value, sort: sort, limit: limit, offset: offset);

  CatalogQuery withSort(CatalogSort? value) =>
      CatalogQuery(filters: filters, sort: value, limit: limit, offset: offset);

  /// Replaces the page window; omitted arguments keep their current value.
  CatalogQuery withPagination({int? limit, int? offset}) => CatalogQuery(
    filters: filters,
    sort: sort,
    limit: limit ?? this.limit,
    offset: offset ?? this.offset,
  );

  @override
  String toString() =>
      'CatalogQuery(filters: $filters, sort: $sort, limit: $limit, '
      'offset: $offset)';
}

/// One catalog row, typed for the UI.
///
/// This is deliberately not a drift row: it contains the joined `types` and
/// category lists as well as the scalar columns, so a widget never has to know
/// table names or parse JSON.
final class ItemSummary {
  const ItemSummary({
    required this.id,
    required this.name,
    required this.shortName,
    required this.weight,
    required this.width,
    required this.height,
    required this.basePrice,
    required this.avg24hPrice,
    required this.fleaPrice,
    required this.change48hPercent,
    required this.priceObservedAt,
    required this.minLevelForFlea,
    required this.fleaEligible,
    required this.iconLink,
    required this.types,
    required this.categoryIds,
    required this.handbookCategoryIds,
  });

  final String id;
  final String name;
  final String shortName;

  /// Weight in kilograms, when the bundle provides one.
  final double? weight;

  /// Grid width in slots, when the item occupies a grid.
  final int? width;

  /// Grid height in slots, when the item occupies a grid.
  final int? height;

  /// Trader-independent base price in roubles.
  final int? basePrice;

  /// Flea-market 24 h average in roubles.
  final int? avg24hPrice;

  /// Latest flea-market low in roubles, the value [CatalogSortField.fleaPrice]
  /// and the price range filter use.
  final int? fleaPrice;

  /// 48 h flea price change as a percentage.
  final double? change48hPercent;

  /// When the newest price snapshot was observed, or `null` when unknown.
  final DateTime? priceObservedAt;

  /// Minimum player level required by the flea market, `0` for none.
  final int? minLevelForFlea;

  /// Whether the item may appear on the flea market; `null` for a row migrated
  /// from schema v4 that has not seen a new `items` bundle yet.
  final bool? fleaEligible;

  final String? iconLink;

  /// Bundle `types[]`, sorted.
  final List<String> types;

  /// Bundle `categoryIds`, sorted.
  final List<String> categoryIds;

  /// Bundle `handbookCategoryIds`, sorted.
  final List<String> handbookCategoryIds;

  @override
  String toString() => 'ItemSummary($id, $name)';
}

/// One page of catalog rows plus the total that matched the filters.
///
/// [total] ignores [offset] and [limit], so a UI can render "showing X of Y"
/// and decide whether to request another page.
final class CatalogPage {
  const CatalogPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<ItemSummary> items;
  final int total;

  /// The clamped limit the query actually used.
  final int limit;

  /// The clamped offset the query actually used.
  final int offset;

  /// Whether the filters matched nothing at all.
  bool get isEmpty => total == 0;

  /// Whether the page itself is empty (an offset past the end).
  bool get isPageEmpty => items.isEmpty;

  /// Whether rows exist after this page.
  bool get hasMore => offset + items.length < total;

  /// The offset a request for the next page should use.
  int get nextOffset => offset + items.length;

  @override
  String toString() =>
      'CatalogPage(${items.length}/$total, limit: $limit, '
      'offset: $offset)';
}

bool _isBlank(String? value) => value == null || value.trim().isEmpty;
