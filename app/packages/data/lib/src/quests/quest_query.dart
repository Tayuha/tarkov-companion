/// Immutable values that describe a quest query and its typed results.
///
/// The data layer owns filtering, sorting and pagination semantics so the quest
/// catalog screen (task 6.2) only renders rows and forwards the user's choices.
/// Filters are deliberately independent: each one can be set, combined with the
/// others, or cleared on its own with a `with…(null)` call.
///
/// This is a read/query layer only. It reports the recorded progress state; it
/// does not derive locked/available availability from prerequisites, level and
/// progress (that is the availability engine, task 6.3).
library;

/// A sortable quest field.
enum QuestSortField {
  /// Quest name, compared through the bundle's normalized search key so the
  /// order is case- and diacritic-insensitive and agrees with text search.
  name,

  /// Minimum player level required to accept the quest.
  minPlayerLevel,

  /// Trader id (upstream identifier, not the trader's display name).
  traderId,

  /// Primary map id (upstream identifier, not the map's display name).
  mapId,
}

/// One quest sort instruction: a field and a direction.
///
/// Ties are always broken by name (normalized, ascending) and then by quest id
/// (ascending), so a page is stable across calls and across the two directions.
/// Quests with a null value for the sorted field are placed last in **both**
/// directions: "no trader/map/level" is not "the smallest trader/map/level".
final class QuestSort {
  const QuestSort(this.field, {this.descending = false});

  final QuestSortField field;
  final bool descending;

  QuestSort reversed() => QuestSort(field, descending: !descending);

  @override
  bool operator ==(Object other) =>
      other is QuestSort &&
      other.field == field &&
      other.descending == descending;

  @override
  int get hashCode => Object.hash(field, descending);

  @override
  String toString() => 'QuestSort(${field.name}, descending: $descending)';
}

/// A quest progress state as the tracker reports it.
///
/// `notStarted` is the absence of a `questProgress` row; the other three values
/// are persisted verbatim as `in-progress`, `completed` and `failed`.
enum QuestProgressState {
  /// No progress row exists for the quest and profile.
  notStarted,

  /// A `questProgress.state` of `in-progress`.
  inProgress,

  /// A `questProgress.state` of `completed`.
  completed,

  /// A `questProgress.state` of `failed`.
  failed;

  /// The `questProgress.state` value persisted for this state.
  ///
  /// [notStarted] has no stored value: the row is deleted instead.
  String? get storedValue => switch (this) {
    QuestProgressState.notStarted => null,
    QuestProgressState.inProgress => 'in-progress',
    QuestProgressState.completed => 'completed',
    QuestProgressState.failed => 'failed',
  };

  /// Maps a stored `questProgress.state` to a typed state.
  ///
  /// A missing row, an empty value or an unrecognized value maps to
  /// [notStarted]. The tracker only writes the three persisted values; treating
  /// anything else as "no progress" keeps an import or an interrupted write
  /// from claiming progress that does not exist.
  static QuestProgressState fromStoredValue(String? value) => switch (value) {
    'in-progress' => QuestProgressState.inProgress,
    'completed' => QuestProgressState.completed,
    'failed' => QuestProgressState.failed,
    _ => QuestProgressState.notStarted,
  };
}

/// The structured filters of a quest query.
///
/// Every field is optional and they combine with AND. A `null` field means
/// "no constraint", so clearing one filter never disturbs the others.
///
/// * [text] matches the quest name, case- and diacritic-insensitively. The text
///   is split into Unicode letter/digit tokens and every token must appear as a
///   substring of the bundle's `normalizedName`. A text with no token (for
///   example `"--"`) matches nothing; blank text is no filter at all.
/// * [traderId] and [mapId] match the upstream identifier exactly. A quest with
///   no map is never returned by a [mapId] filter.
/// * [minPlayerLevel] matches the quest's required level **exactly**.
/// * [maxPlayerLevel] is an inclusive upper bound: a quest matches when its
///   required level is **at or below** the value. Quests whose required level is
///   unknown (`null`) do not match, because their gate cannot be proven.
///   Set both bounds to the same value for "exactly this level".
/// * [state] filters the profile's recorded progress. It is evaluated against
///   `QuestQuery.profileId`: a quest with no progress row for that profile is
///   [QuestProgressState.notStarted]. With no profile id, no row can exist, so
///   only [QuestProgressState.notStarted] matches.
final class QuestFilters {
  const QuestFilters({
    this.text,
    this.traderId,
    this.mapId,
    this.minPlayerLevel,
    this.maxPlayerLevel,
    this.state,
  });

  final String? text;
  final String? traderId;
  final String? mapId;

  /// Exact required player level (`tasks.minPlayerLevel`).
  final int? minPlayerLevel;

  /// Inclusive upper bound on the required player level.
  final int? maxPlayerLevel;

  /// Recorded progress state for `QuestQuery.profileId`.
  final QuestProgressState? state;

  /// Whether no filter is active.
  bool get isEmpty =>
      _isBlank(text) &&
      _isBlank(traderId) &&
      _isBlank(mapId) &&
      minPlayerLevel == null &&
      maxPlayerLevel == null &&
      state == null;

  /// Whether at least one filter is active.
  bool get isNotEmpty => !isEmpty;

  /// Replaces the search text; `null` (or blank) clears it.
  QuestFilters withText(String? value) => QuestFilters(
    text: value,
    traderId: traderId,
    mapId: mapId,
    minPlayerLevel: minPlayerLevel,
    maxPlayerLevel: maxPlayerLevel,
    state: state,
  );

  /// Replaces the trader filter; `null` (or blank) clears it.
  QuestFilters withTrader(String? id) => QuestFilters(
    text: text,
    traderId: id,
    mapId: mapId,
    minPlayerLevel: minPlayerLevel,
    maxPlayerLevel: maxPlayerLevel,
    state: state,
  );

  /// Replaces the map filter; `null` (or blank) clears it.
  QuestFilters withMap(String? id) => QuestFilters(
    text: text,
    traderId: traderId,
    mapId: id,
    minPlayerLevel: minPlayerLevel,
    maxPlayerLevel: maxPlayerLevel,
    state: state,
  );

  /// Replaces the exact required-level filter; `null` clears it.
  QuestFilters withMinPlayerLevel(int? level) => QuestFilters(
    text: text,
    traderId: traderId,
    mapId: mapId,
    minPlayerLevel: level,
    maxPlayerLevel: maxPlayerLevel,
    state: state,
  );

  /// Replaces the at-or-below required-level filter; `null` clears it.
  QuestFilters withMaxPlayerLevel(int? level) => QuestFilters(
    text: text,
    traderId: traderId,
    mapId: mapId,
    minPlayerLevel: minPlayerLevel,
    maxPlayerLevel: level,
    state: state,
  );

  /// Replaces the progress-state filter; `null` clears it.
  QuestFilters withState(QuestProgressState? value) => QuestFilters(
    text: text,
    traderId: traderId,
    mapId: mapId,
    minPlayerLevel: minPlayerLevel,
    maxPlayerLevel: maxPlayerLevel,
    state: value,
  );

  /// Clears every filter.
  QuestFilters clear() => const QuestFilters();

  @override
  String toString() =>
      'QuestFilters(text: $text, traderId: $traderId, mapId: $mapId, '
      'minPlayerLevel: $minPlayerLevel, maxPlayerLevel: $maxPlayerLevel, '
      'state: ${state?.name})';
}

/// A complete quest query: filters, an optional sort, a page window and the
/// profile whose progress is read.
///
/// [limit] and [offset] are clamped deterministically when [effectiveLimit] and
/// [effectiveOffset] are read, rather than rejected:
///
/// * `limit < 1` becomes `1`, `limit > maxLimit` becomes [maxLimit];
/// * `offset < 0` becomes `0`.
///
/// This keeps a stale page number or a huge page size from throwing in the
/// middle of a frame while still bounding the work a caller can request.
final class QuestQuery {
  const QuestQuery({
    this.filters = const QuestFilters(),
    this.sort,
    this.limit = defaultLimit,
    this.offset = 0,
    this.profileId,
  });

  /// Page size used when the caller does not choose one.
  static const int defaultLimit = 50;

  /// Largest page a single query may return.
  static const int maxLimit = 200;

  final QuestFilters filters;

  /// The requested order, or `null` for ascending name.
  final QuestSort? sort;

  final int limit;
  final int offset;

  /// The profile whose `questProgress` rows are read, or `null` for none.
  ///
  /// Without a profile, every returned [QuestSummary.progressState] is
  /// [QuestProgressState.notStarted] and a state filter only matches
  /// `notStarted`.
  final String? profileId;

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

  /// Whether this query performs a text search.
  bool get hasText => filters.text != null && filters.text!.trim().isNotEmpty;

  QuestQuery withFilters(QuestFilters value) => QuestQuery(
    filters: value,
    sort: sort,
    limit: limit,
    offset: offset,
    profileId: profileId,
  );

  QuestQuery withSort(QuestSort? value) => QuestQuery(
    filters: filters,
    sort: value,
    limit: limit,
    offset: offset,
    profileId: profileId,
  );

  /// Replaces the page window; omitted arguments keep their current value.
  QuestQuery withPagination({int? limit, int? offset}) => QuestQuery(
    filters: filters,
    sort: sort,
    limit: limit ?? this.limit,
    offset: offset ?? this.offset,
    profileId: profileId,
  );

  /// Replaces the profile whose progress is read; `null` clears it.
  QuestQuery withProfile(String? id) => QuestQuery(
    filters: filters,
    sort: sort,
    limit: limit,
    offset: offset,
    profileId: id,
  );

  @override
  String toString() =>
      'QuestQuery(filters: $filters, sort: $sort, limit: $limit, '
      'offset: $offset, profileId: $profileId)';
}

/// One quest row, typed for the UI.
///
/// This is deliberately not a drift row: a widget never sees table names, the
/// stored payload, or the raw `questProgress.state` string.
final class QuestSummary {
  const QuestSummary({
    required this.id,
    required this.name,
    required this.traderId,
    required this.mapId,
    required this.minPlayerLevel,
    required this.experience,
    required this.kappaRequired,
    required this.progressState,
  });

  final String id;
  final String name;

  /// Trader that gives the quest, when upstream provides one.
  final String? traderId;

  /// Primary map of the quest, when upstream provides one.
  final String? mapId;

  /// Minimum player level required to accept the quest, when known.
  final int? minPlayerLevel;

  /// Experience reward, when upstream provides one.
  final int? experience;

  /// Whether the quest counts towards the Kappa container.
  final bool kappaRequired;

  /// The profile's recorded state, or [QuestProgressState.notStarted] when no
  /// row exists or no profile was supplied.
  final QuestProgressState progressState;

  @override
  String toString() => 'QuestSummary($id, $name, ${progressState.name})';
}

/// One page of quest rows plus the total that matched the filters.
///
/// [total] ignores [offset] and [limit], so a UI can render "showing X of Y"
/// and decide whether to request another page.
final class QuestPage {
  const QuestPage({
    required this.quests,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<QuestSummary> quests;
  final int total;

  /// The clamped limit the query actually used.
  final int limit;

  /// The clamped offset the query actually used.
  final int offset;

  /// Whether the filters matched nothing at all.
  bool get isEmpty => total == 0;

  /// Whether the page itself is empty (an offset past the end).
  bool get isPageEmpty => quests.isEmpty;

  /// Whether rows exist after this page.
  bool get hasMore => offset + quests.length < total;

  /// The offset a request for the next page should use.
  int get nextOffset => offset + quests.length;

  @override
  String toString() =>
      'QuestPage(${quests.length}/$total, limit: $limit, offset: $offset)';
}

/// Splits [text] into folded Unicode letter/digit tokens.
///
/// Characters that are not letters or digits are separators, so punctuation
/// can never become a search term. Tokens are lower-cased, diacritics are
/// folded (`CAFÉ` -> `cafe`), and duplicates are removed while order is kept.
/// Blank text returns an empty list, which means "no filter"; non-blank text
/// with no letter/digit token also returns an empty list, and the repository
/// treats that as "matches nothing".
List<String> questSearchTokens(String? text) {
  if (text == null) {
    return const [];
  }
  final tokens = <String>[];
  final seen = <String>{};
  for (final match in RegExp(
    r'[\p{L}\p{N}]+',
    unicode: true,
  ).allMatches(text)) {
    final token = foldQuestSearchText(match[0]!);
    if (token.isNotEmpty && seen.add(token)) {
      tokens.add(token);
    }
  }
  return tokens;
}

/// Lower-cases [value] and replaces common Latin diacritics with their base
/// letters.
///
/// Query text is folded so an unaccented search (`cafe`) matches the bundle's
/// normalized quest name (`cafe-creme`) and an accented search (`CAFÉ`) folds
/// to the same token. The normalized name itself comes from the pipeline, which
/// already publishes it lower-case and diacritic-free.
String foldQuestSearchText(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final character = String.fromCharCode(rune);
    buffer.write(_diacriticFolds[character] ?? character);
  }
  return buffer.toString();
}

/// Latin diacritics mapped to their base letters.
///
/// The list covers Latin-1 Supplement and the common Latin Extended-A/B
/// characters used by the localized quest names. Anything not listed is kept
/// as-is, so non-Latin scripts still match themselves exactly.
const Map<String, String> _diacriticFolds = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'æ': 'ae',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'ĉ': 'c',
  'ċ': 'c',
  'ď': 'd',
  'đ': 'd',
  'ð': 'd',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ė': 'e',
  'ę': 'e',
  'ě': 'e',
  'ğ': 'g',
  'ĝ': 'g',
  'ġ': 'g',
  'ģ': 'g',
  'ĥ': 'h',
  'ħ': 'h',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'į': 'i',
  'ı': 'i',
  'ĵ': 'j',
  'ķ': 'k',
  'ĺ': 'l',
  'ļ': 'l',
  'ľ': 'l',
  'ł': 'l',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ņ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ő': 'o',
  'œ': 'oe',
  'ŕ': 'r',
  'ř': 'r',
  'ś': 's',
  'š': 's',
  'ş': 's',
  'ŝ': 's',
  'ș': 's',
  'ß': 'ss',
  'ť': 't',
  'ţ': 't',
  'ț': 't',
  'þ': 'th',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ű': 'u',
  'ų': 'u',
  'ŵ': 'w',
  'ý': 'y',
  'ÿ': 'y',
  'ź': 'z',
  'ż': 'z',
  'ž': 'z',
};

bool _isBlank(String? value) => value == null || value.trim().isEmpty;
