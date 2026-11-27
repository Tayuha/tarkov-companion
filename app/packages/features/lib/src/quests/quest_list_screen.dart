import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import '../section_header.dart';
import 'quest_filter_bar.dart';
import 'quest_list_row.dart';

export 'quest_filter_bar.dart' show QuestFilterOption;
export 'quest_list_row.dart' show QuestStateBadge, questStateLabel;

/// The searchable, filterable quest catalog.
///
/// The screen owns presentation state only: the data layer executes every
/// query through [QuestRepository]. It deliberately does not decide quest
/// availability (task 6.3), open a detail view (tasks 6.4/6.5) or record
/// progress (task 6.6); a row tap is reported through [onQuestSelected].
///
/// Behavior:
///
/// * typing waits [searchDebounce] before it reaches the repository, and a
///   response that belongs to an older query is discarded, so fast typing
///   cannot make an old result overwrite a newer one;
/// * trader, map, level and state filters combine with AND with the search
///   text; each active filter appears as a removable chip and the reset action
///   clears every filter and the search field;
/// * progress state is read for [profileId] only, so two profiles render
///   independent badges over the same catalog;
/// * rows are built on demand by a `ListView.builder` and pages are appended
///   with the explicit load-more control, so a large catalog never
///   materializes as one widget tree;
/// * there is no network access: every row, count and page is local.
class QuestListScreen extends StatefulWidget {
  const QuestListScreen({
    super.key,
    required this.repository,
    this.profileId,
    this.onQuestSelected,
    this.pageSize = 50,
    this.searchDebounce = const Duration(milliseconds: 300),
    this.traderOptions = const [],
    this.mapOptions = const [],
  });

  final QuestRepository repository;

  /// The profile whose recorded progress supplies the state badges, or `null`
  /// for no profile (every quest then reads as not started).
  final String? profileId;

  /// Called with the quest id when a row is tapped.
  final ValueChanged<String>? onQuestSelected;

  /// Rows requested per page.
  final int pageSize;

  /// How long typing is idle before the query is sent.
  final Duration searchDebounce;

  /// Traders offered by the filter bar; see [QuestFilterOption].
  final List<QuestFilterOption> traderOptions;

  /// Maps offered by the filter bar; see [QuestFilterOption].
  final List<QuestFilterOption> mapOptions;

  @override
  State<QuestListScreen> createState() => _QuestListScreenState();
}

class _QuestListScreenState extends State<QuestListScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchTimer;

  QuestFilters _filters = const QuestFilters();

  final List<QuestSummary> _quests = <QuestSummary>[];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  late List<QuestFilterOption> _traderOptions;
  late List<QuestFilterOption> _mapOptions;

  /// Incremented for each repository request. Only the newest response may
  /// write to the state, which makes the debounce and page appends race-free.
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _traderOptions = widget.traderOptions;
    _mapOptions = widget.mapOptions;
    _fetchFilterOptions();
    _fetchFirstPage(++_requestGeneration);
  }

  @override
  void didUpdateWidget(covariant QuestListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.traderOptions != oldWidget.traderOptions) {
      _traderOptions = widget.traderOptions;
    }
    if (widget.mapOptions != oldWidget.mapOptions) {
      _mapOptions = widget.mapOptions;
    }
    if (widget.profileId != oldWidget.profileId ||
        widget.repository != oldWidget.repository ||
        widget.pageSize != oldWidget.pageSize) {
      _fetchFilterOptions();
      _reload();
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Loads trader and map names for the filters when the caller did not
  /// supply them. The app shell never supplies them, so this is the production
  /// path; tests pass explicit options when they need fixed labels.
  Future<void> _fetchFilterOptions() async {
    if (_traderOptions.isNotEmpty && _mapOptions.isNotEmpty) {
      return;
    }
    try {
      final traders = await widget.repository.traderLabels();
      final maps = await widget.repository.mapLabels();
      if (!mounted) {
        return;
      }
      setState(() {
        if (widget.traderOptions.isEmpty) {
          _traderOptions = [
            for (final label in traders)
              QuestFilterOption(id: label.id, label: label.name),
          ];
        }
        if (widget.mapOptions.isEmpty) {
          _mapOptions = [
            for (final label in maps)
              QuestFilterOption(id: label.id, label: label.name),
          ];
        }
      });
    } on Object {
      // Filters remain usable with the ids when labels cannot be loaded.
    }
  }

  bool get _hasMore => _quests.length < _total;

  QuestQuery _queryForOffset(int offset) => QuestQuery(
    filters: _filters,
    limit: widget.pageSize,
    offset: offset,
    profileId: widget.profileId,
  );

  Future<void> _fetchFirstPage(int generation) async {
    try {
      final page = await widget.repository.query(_queryForOffset(0));
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _quests
          ..clear()
          ..addAll(page.quests);
        _total = page.total;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error;
      });
    }
  }

  void _reload() {
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    _fetchFirstPage(generation);
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) {
      return;
    }
    final generation = ++_requestGeneration;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.repository.query(
        _queryForOffset(_quests.length),
      );
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _quests.addAll(page.quests);
        _total = page.total;
        _loadingMore = false;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _loadingMore = false;
        _error = error;
      });
    }
  }

  void _onSearchChanged(String value) {
    setState(() {}); // Refresh the clear button.
    _searchTimer?.cancel();
    _searchTimer = Timer(widget.searchDebounce, () => _applySearch(value));
  }

  void _onSearchSubmitted(String value) {
    _searchTimer?.cancel();
    _applySearch(value);
  }

  void _applySearch(String value) {
    final text = value.trim();
    final next = text.isEmpty ? null : text;
    if (next == _filters.text) {
      return;
    }
    _filters = _filters.withText(next);
    _reload();
  }

  void _clearSearch() {
    _searchTimer?.cancel();
    _searchController.clear();
    _applySearch('');
    setState(() {});
  }

  void _resetFilters() {
    _searchTimer?.cancel();
    final hadSearchText = _searchController.text.isNotEmpty;
    _searchController.clear();
    if (_filters.isEmpty && !hadSearchText) {
      return;
    }
    _filters = const QuestFilters();
    _reload();
  }

  void _setTrader(String? id) {
    final next = _nonBlank(id);
    if (next == _filters.traderId) {
      return;
    }
    _filters = _filters.withTrader(next);
    _reload();
  }

  void _setMap(String? id) {
    final next = _nonBlank(id);
    if (next == _filters.mapId) {
      return;
    }
    _filters = _filters.withMap(next);
    _reload();
  }

  void _setLevel(int? level) {
    if (level == _filters.maxPlayerLevel) {
      return;
    }
    _filters = _filters.withMaxPlayerLevel(level);
    _reload();
  }

  void _setState(QuestProgressState? state) {
    if (state == _filters.state) {
      return;
    }
    _filters = _filters.withState(state);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('quest-search-field'),
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search quests',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                key: const Key('quest-clear-search'),
                                tooltip: 'Clear search',
                                onPressed: _clearSearch,
                                icon: const Icon(Icons.close),
                              ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: _onSearchChanged,
                      onSubmitted: _onSearchSubmitted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              QuestFilterBar(
                filters: _filters,
                traderOptions: _traderOptions,
                mapOptions: _mapOptions,
                onTraderSelected: _setTrader,
                onMapSelected: _setMap,
                onLevelSelected: _setLevel,
                onStateSelected: _setState,
                onRemoveText: _clearSearch,
                onReset: _resetFilters,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SectionHeader(title: 'Quest catalog'),
                  const Spacer(),
                  Text(
                    _resultCountLabel,
                    key: const Key('quest-result-count'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading && _quests.isNotEmpty)
                const LinearProgressIndicator(key: Key('quest-loading-bar')),
              if (_error != null)
                _QuestErrorBanner(
                  message: 'Could not load quests.',
                  detail: '$_error',
                  onRetry: _reload,
                ),
              const SizedBox(height: 4),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  String get _resultCountLabel {
    if (_loading && _quests.isEmpty) {
      return 'Loading quests…';
    }
    return 'Showing ${_quests.length} of $_total quests';
  }

  Widget _buildBody() {
    if (_quests.isEmpty) {
      if (_loading) {
        return const Center(
          child: CircularProgressIndicator(key: Key('quest-loading')),
        );
      }
      if (_error != null) {
        return const SizedBox.shrink();
      }
      return _QuestEmptyState(filters: _filters, onReset: _resetFilters);
    }

    final showFooter = _hasMore || _loadingMore;
    return ListView.builder(
      key: const Key('quest-list'),
      itemCount: _quests.length + (showFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _quests.length) {
          return _LoadMoreFooter(
            loaded: _quests.length,
            total: _total,
            loading: _loadingMore,
            onLoadMore: _loadMore,
          );
        }
        final quest = _quests[index];
        return QuestListRow(
          quest: quest,
          traderLabel: _optionLabel(_traderOptions, quest.traderId),
          mapLabel: _optionLabel(_mapOptions, quest.mapId),
          onTap: widget.onQuestSelected == null
              ? null
              : () => widget.onQuestSelected!(quest.id),
        );
      },
    );
  }

  static String? _optionLabel(List<QuestFilterOption> options, String? id) {
    if (id == null) {
      return null;
    }
    for (final option in options) {
      if (option.id == id) {
        return option.label;
      }
    }
    return id;
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.loaded,
    required this.total,
    required this.loading,
    required this.onLoadMore,
  });

  final int loaded;
  final int total;
  final bool loading;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Text(
            '$loaded of $total loaded',
            key: const Key('quest-loaded-count'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('quest-load-more'),
            onPressed: loading ? null : onLoadMore,
            child: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Load more'),
          ),
        ],
      ),
    );
  }
}

class _QuestEmptyState extends StatelessWidget {
  const _QuestEmptyState({required this.filters, required this.onReset});

  final QuestFilters filters;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = filters.text?.trim();
    final headline = query != null && query.isNotEmpty
        ? 'No quests match "$query".'
        : filters.isNotEmpty
        ? 'No quests match the active filters.'
        : 'The quest catalog is empty.';
    final detail = query != null && query.isNotEmpty
        ? 'Try a different search, or reset the active filters.'
        : filters.isNotEmpty
        ? 'Remove a filter or reset them all to see the full catalog.'
        : 'Sync a quest dataset to populate the catalog.';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              headline,
              key: const Key('quest-empty-title'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (filters.isNotEmpty) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                key: const Key('quest-empty-reset'),
                onPressed: onReset,
                child: const Text('Reset filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuestErrorBanner extends StatelessWidget {
  const _QuestErrorBanner({
    required this.message,
    required this.detail,
    required this.onRetry,
  });

  final String message;
  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('quest-error-banner'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onErrorContainer),
                ),
              ],
            ),
          ),
          TextButton(
            key: const Key('quest-retry'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

String? _nonBlank(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}
