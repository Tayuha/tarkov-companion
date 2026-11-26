import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import '../section_header.dart';
import 'catalog_filter_bar.dart';
import 'catalog_item_row.dart';

export 'catalog_filter_bar.dart' show CatalogCategoryOption;
export 'catalog_item_row.dart' show CatalogItemRow;

/// The searchable, filterable item catalog.
///
/// The screen owns presentation state only: the data layer executes every
/// query through [CatalogRepository]. It deliberately does not wire navigation;
/// a row tap is reported through [onItemSelected] with the item's game id.
///
/// Behavior:
///
/// * typing waits [searchDebounce] before it reaches the repository, and a
///   response that belongs to an older query is discarded, so fast typing
///   cannot make an old result overwrite a newer one;
/// * filters combine with AND and are cleared one chip at a time; reset clears
///   every filter and the search field;
/// * rows are built on demand by a `ListView.builder` and pages are appended
///   with the explicit load-more control, so a large catalog never materializes
///   as one widget tree;
/// * images are a fixed neutral placeholder until task 5.6 adds the image cache.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.repository,
    this.onItemSelected,
    this.pageSize = 50,
    this.searchDebounce = const Duration(milliseconds: 300),
    this.categories = defaultCatalogCategories,
    this.types = defaultCatalogTypes,
  });

  final CatalogRepository repository;

  /// Called with the item id when a row is tapped.
  final ValueChanged<String>? onItemSelected;

  /// Rows requested per page.
  final int pageSize;

  /// How long typing is idle before the query is sent.
  final Duration searchDebounce;

  /// Categories offered by the filter bar; see [CatalogCategoryOption].
  final List<CatalogCategoryOption> categories;

  /// Bundle `types[]` values offered by the filter bar.
  final List<String> types;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchTimer;

  CatalogFilters _filters = const CatalogFilters();

  /// `null` keeps the repository default: relevance while searching, name
  /// otherwise. Choosing a field makes the order explicit.
  CatalogSort? _sort;

  final List<ItemSummary> _items = <ItemSummary>[];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  /// Incremented for each repository request. Only the newest response may
  /// write to the state, which makes the debounce and page appends race-free.
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _fetchFirstPage(++_requestGeneration);
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasMore => _items.length < _total;

  CatalogQuery _queryForOffset(int offset) => CatalogQuery(
    filters: _filters,
    sort: _sort,
    limit: widget.pageSize,
    offset: offset,
  );

  Future<void> _fetchFirstPage(int generation) async {
    try {
      final page = await widget.repository.query(_queryForOffset(0));
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
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
        _queryForOffset(_items.length),
      );
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _items.addAll(page.items);
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
    _searchController.clear();
    if (_filters.isEmpty) {
      return;
    }
    _filters = const CatalogFilters();
    _reload();
  }

  void _setCategory(String? id) {
    final next = id == null || id.trim().isEmpty ? null : id;
    if (next == _filters.categoryId) {
      return;
    }
    final option = _categoryOption(next);
    _filters = _filters.withCategory(next, kind: option?.kind);
    _reload();
  }

  CatalogCategoryOption? _categoryOption(String? id) {
    if (id == null) {
      return null;
    }
    for (final option in widget.categories) {
      if (option.id == id) {
        return option;
      }
    }
    return null;
  }

  void _setType(String? type) {
    final next = type?.trim();
    final current = _filters.type;
    final normalized = next == null || next.isEmpty ? null : next;
    if (normalized == current) {
      return;
    }
    _filters = _filters.withType(normalized);
    _reload();
  }

  void _setFleaEligible(bool? eligible) {
    if (eligible == _filters.fleaEligible) {
      return;
    }
    _filters = _filters.withFleaEligible(eligible);
    _reload();
  }

  void _setSort(CatalogSortField? field) {
    if (field == null) {
      if (_sort == null) {
        return;
      }
      _sort = null;
      _reload();
      return;
    }
    if (field == _sort?.field) {
      return;
    }
    _sort = CatalogSort(field, descending: _sort?.descending ?? false);
    _reload();
  }

  void _toggleSortDirection() {
    final sort = _sort;
    if (sort == null) {
      return;
    }
    _sort = sort.reversed();
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
                      key: const Key('catalog-search-field'),
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search items',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                key: const Key('catalog-clear-search'),
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
                  const SizedBox(width: 16),
                  Text('Sort', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(width: 8),
                  DropdownButton<CatalogSortField?>(
                    key: const Key('catalog-sort-field'),
                    value: _sort?.field,
                    hint: const Text('Default'),
                    items: const [
                      DropdownMenuItem<CatalogSortField?>(
                        value: null,
                        child: Text('Default'),
                      ),
                      DropdownMenuItem(
                        value: CatalogSortField.name,
                        child: Text('Name'),
                      ),
                      DropdownMenuItem(
                        value: CatalogSortField.basePrice,
                        child: Text('Base price'),
                      ),
                      DropdownMenuItem(
                        value: CatalogSortField.fleaPrice,
                        child: Text('Flea price'),
                      ),
                      DropdownMenuItem(
                        value: CatalogSortField.weight,
                        child: Text('Weight'),
                      ),
                    ],
                    onChanged: _setSort,
                  ),
                  IconButton(
                    key: const Key('catalog-sort-direction'),
                    tooltip: (_sort?.descending ?? false)
                        ? 'Descending'
                        : 'Ascending',
                    onPressed: _sort == null ? null : _toggleSortDirection,
                    icon: Icon(
                      (_sort?.descending ?? false)
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CatalogFilterBar(
                filters: _filters,
                categories: widget.categories,
                types: widget.types,
                onCategorySelected: _setCategory,
                onTypeSelected: _setType,
                onFleaEligibleSelected: _setFleaEligible,
                onRemoveText: _clearSearch,
                onReset: _resetFilters,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SectionHeader(title: 'Item catalog'),
                  const Spacer(),
                  Text(
                    _resultCountLabel,
                    key: const Key('catalog-result-count'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading && _items.isNotEmpty)
                const LinearProgressIndicator(key: Key('catalog-loading-bar')),
              if (_error != null)
                _CatalogErrorBanner(
                  message: 'Could not load the catalog.',
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
    if (_loading && _items.isEmpty) {
      return 'Loading items…';
    }
    return 'Showing ${_items.length} of $_total items';
  }

  Widget _buildBody() {
    if (_items.isEmpty) {
      if (_loading) {
        return const Center(
          child: CircularProgressIndicator(key: Key('catalog-loading')),
        );
      }
      if (_error != null) {
        return const SizedBox.shrink();
      }
      return _CatalogEmptyState(filters: _filters, onReset: _resetFilters);
    }

    final showFooter = _hasMore || _loadingMore;
    return ListView.builder(
      key: const Key('catalog-list'),
      itemCount: _items.length + (showFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return _LoadMoreFooter(
            loaded: _items.length,
            total: _total,
            loading: _loadingMore,
            onLoadMore: _loadMore,
          );
        }
        final item = _items[index];
        return CatalogItemRow(
          item: item,
          onTap: widget.onItemSelected == null
              ? null
              : () => widget.onItemSelected!(item.id),
        );
      },
    );
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
            key: const Key('catalog-loaded-count'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('catalog-load-more'),
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

class _CatalogEmptyState extends StatelessWidget {
  const _CatalogEmptyState({required this.filters, required this.onReset});

  final CatalogFilters filters;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = filters.text?.trim();
    final headline = query != null && query.isNotEmpty
        ? 'No items match "$query".'
        : filters.isNotEmpty
        ? 'No items match the active filters.'
        : 'The item catalog is empty.';
    final detail = query != null && query.isNotEmpty
        ? 'Try a different search, or reset the active filters.'
        : filters.isNotEmpty
        ? 'Remove a filter or reset them all to see the full catalog.'
        : 'Sync an item dataset to populate the catalog.';

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
              key: const Key('catalog-empty-title'),
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
                key: const Key('catalog-empty-reset'),
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

class _CatalogErrorBanner extends StatelessWidget {
  const _CatalogErrorBanner({
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
      key: const Key('catalog-error-banner'),
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
            key: const Key('catalog-retry'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
