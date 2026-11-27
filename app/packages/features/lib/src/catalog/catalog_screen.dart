import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import '../theme/app_primitives.dart';
import '../theme/app_tokens.dart';
import 'catalog_filter_bar.dart';
import 'catalog_item_row.dart';
import 'item_image.dart';

export 'catalog_filter_bar.dart' show CatalogCategoryOption;
export 'catalog_item_row.dart'
    show
        CatalogItemRow,
        CatalogLayout,
        CatalogTableHeader,
        CatalogTableRow,
        catalogLayoutForWidth,
        formatObservationAge;

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
/// * the layout is adaptive: a five-column table at 1100 logical pixels, an
///   extra `Observed` column at 1600, and compact card rows below 1100;
/// * content width is capped at 1600 logical pixels so an ultra-wide monitor
///   never stretches the table into unreadable columns;
/// * rows render their `iconLink` through an optional disk-backed image cache,
///   falling back to the neutral placeholder without performing I/O when no
///   cache is supplied.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.repository,
    this.onItemSelected,
    this.pageSize = 50,
    this.searchDebounce = const Duration(milliseconds: 300),
    this.categories,
    this.types = defaultCatalogTypes,
    this.imageCache,
  });

  /// The widest the catalog chrome and table may grow.
  static const double maxContentWidth = 1600;

  final CatalogRepository repository;

  /// Called with the item id when a row is tapped.
  final ValueChanged<String>? onItemSelected;

  /// Rows requested per page.
  final int pageSize;

  /// How long typing is idle before the query is sent.
  final Duration searchDebounce;

  /// Categories offered by the filter bar.
  ///
  /// When omitted, the screen loads the real category labels from the applied
  /// bundle through `CatalogRepository.categoryOptions`, so the filter never
  /// depends on a hardcoded starter list. A caller may still pass explicit
  /// options (tests do) to keep a screen deterministic.
  final List<CatalogCategoryOption>? categories;

  /// Bundle `types[]` values offered by the filter bar.
  final List<String> types;

  /// Optional disk-backed item image cache. When absent, rows render the
  /// neutral placeholder and perform no I/O.
  final ItemImageCache? imageCache;

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
  List<CatalogCategoryOption> _categories = const [];
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
    _categories = widget.categories ?? const [];
    if (widget.categories == null) {
      _loadCategoryOptions();
    }
    _fetchFirstPage(++_requestGeneration);
  }

  @override
  void didUpdateWidget(CatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categories != widget.categories) {
      _categories = widget.categories ?? _categories;
      if (widget.categories == null) {
        _loadCategoryOptions();
      }
    }
  }

  /// Loads the real category labels from the applied bundle.
  ///
  /// Failure is quiet: the catalog still queries without a category filter. A
  /// later dataset refresh is picked up on the next screen open.
  Future<void> _loadCategoryOptions() async {
    try {
      final categories = await widget.repository.categoryOptions();
      if (!mounted) {
        return;
      }
      setState(() {
        _categories = [
          for (final category in categories)
            CatalogCategoryOption(
              id: category.id,
              label: category.name,
              kind: category.kind,
            ),
        ];
      });
    } on Object {
      // Keep the empty list; the rest of the catalog is unaffected.
    }
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
    for (final option in _categories) {
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
    final tokens = AppTokens.of(context);
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            key: const Key('catalog-content'),
            constraints: const BoxConstraints(
              maxWidth: CatalogScreen.maxContentWidth,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final layout = catalogLayoutForWidth(constraints.maxWidth);
                return Padding(
                  padding: EdgeInsets.all(tokens.spaceLg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SearchAndSortRow(
                        controller: _searchController,
                        sort: _sort,
                        onSearchChanged: _onSearchChanged,
                        onSearchSubmitted: _onSearchSubmitted,
                        onClearSearch: _clearSearch,
                        onSortChanged: _setSort,
                        onToggleSortDirection: _toggleSortDirection,
                      ),
                      SizedBox(height: tokens.spaceMd),
                      CatalogFilterBar(
                        filters: _filters,
                        categories: _categories,
                        types: widget.types,
                        onCategorySelected: _setCategory,
                        onTypeSelected: _setType,
                        onFleaEligibleSelected: _setFleaEligible,
                        onRemoveText: _clearSearch,
                        onReset: _resetFilters,
                      ),
                      SizedBox(height: tokens.spaceLg),
                      _CatalogHeading(resultCount: _resultCountLabel),
                      SizedBox(height: tokens.spaceSm),
                      if (layout != CatalogLayout.compact)
                        CatalogTableHeader(layout: layout),
                      if (_loading && _items.isNotEmpty)
                        LinearProgressIndicator(
                          key: const Key('catalog-loading-bar'),
                          color: tokens.accent,
                          backgroundColor: tokens.surfaceRaised,
                          minHeight: 2,
                        ),
                      if (_error != null)
                        _CatalogErrorBanner(
                          message: 'Could not load the catalog.',
                          detail: '$_error',
                          onRetry: _reload,
                        ),
                      if (layout == CatalogLayout.compact)
                        SizedBox(height: tokens.spaceSm),
                      Expanded(child: _buildBody(layout)),
                    ],
                  ),
                );
              },
            ),
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

  Widget _buildBody(CatalogLayout layout) {
    if (_items.isEmpty) {
      if (_loading) {
        return Center(
          child: CircularProgressIndicator(key: const Key('catalog-loading')),
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
        final onTap = widget.onItemSelected == null
            ? null
            : () => widget.onItemSelected!(item.id);
        if (layout == CatalogLayout.compact) {
          return CatalogItemRow(
            item: item,
            onTap: onTap,
            imageCache: widget.imageCache,
          );
        }
        return CatalogTableRow(
          item: item,
          layout: layout,
          index: index,
          onTap: onTap,
          imageCache: widget.imageCache,
        );
      },
    );
  }
}

/// The search field, sort field and sort-direction toggle.
class _SearchAndSortRow extends StatelessWidget {
  const _SearchAndSortRow({
    required this.controller,
    required this.sort,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onClearSearch,
    required this.onSortChanged,
    required this.onToggleSortDirection,
  });

  final TextEditingController controller;
  final CatalogSort? sort;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onClearSearch;
  final ValueChanged<CatalogSortField?> onSortChanged;
  final VoidCallback onToggleSortDirection;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final descending = sort?.descending ?? false;

    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('catalog-search-field'),
            controller: controller,
            textInputAction: TextInputAction.search,
            style: tokens.bodyStyle,
            decoration: InputDecoration(
              hintText: 'Search items',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      key: const Key('catalog-clear-search'),
                      tooltip: 'Clear search',
                      onPressed: onClearSearch,
                      icon: const Icon(Icons.close),
                    ),
            ),
            onChanged: onSearchChanged,
            onSubmitted: onSearchSubmitted,
          ),
        ),
        SizedBox(width: tokens.spaceLg),
        AppSectionLabel('Sort'),
        SizedBox(width: tokens.spaceSm),
        Container(
          height: 30,
          padding: EdgeInsets.symmetric(horizontal: tokens.spaceSm),
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<CatalogSortField?>(
              key: const Key('catalog-sort-field'),
              value: sort?.field,
              hint: Text('Default', style: tokens.bodyStyle),
              dropdownColor: tokens.surfaceRaised,
              isDense: true,
              icon: Icon(
                Icons.expand_more,
                size: tokens.h2Size,
                color: tokens.dim,
              ),
              style: tokens.bodyStyle,
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
              onChanged: onSortChanged,
            ),
          ),
        ),
        SizedBox(width: tokens.spaceXs),
        IconButton(
          key: const Key('catalog-sort-direction'),
          tooltip: descending ? 'Descending' : 'Ascending',
          onPressed: sort == null ? null : onToggleSortDirection,
          visualDensity: VisualDensity.compact,
          icon: Icon(
            descending ? Icons.arrow_downward : Icons.arrow_upward,
            size: tokens.h2Size,
          ),
          color: sort == null ? tokens.dim : tokens.muted,
        ),
      ],
    );
  }
}

/// The catalog title and the result count.
class _CatalogHeading extends StatelessWidget {
  const _CatalogHeading({required this.resultCount});

  final String resultCount;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppSectionLabel('Catalog'),
              SizedBox(height: tokens.spaceXs),
              Text('Item catalog', style: tokens.h1Style),
            ],
          ),
        ),
        Text(
          resultCount,
          key: const Key('catalog-result-count'),
          style: tokens.dataStyle.copyWith(color: tokens.muted),
        ),
      ],
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
    final tokens = AppTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spaceLg),
      child: Column(
        children: [
          Text(
            '$loaded of $total loaded',
            key: const Key('catalog-loaded-count'),
            style: tokens.dataStyle.copyWith(color: tokens.muted),
          ),
          SizedBox(height: tokens.spaceSm),
          AppButton(
            key: const Key('catalog-load-more'),
            label: 'Load more',
            variant: AppButtonVariant.secondary,
            onPressed: loading ? null : onLoadMore,
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
    final tokens = AppTokens.of(context);
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
            Icon(Icons.search_off, size: 48, color: tokens.dim),
            SizedBox(height: tokens.spaceMd),
            Text(
              headline,
              key: const Key('catalog-empty-title'),
              textAlign: TextAlign.center,
              style: tokens.h2Style,
            ),
            SizedBox(height: tokens.spaceXs),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: tokens.bodyStyle.copyWith(color: tokens.muted),
            ),
            if (filters.isNotEmpty) ...[
              SizedBox(height: tokens.spaceLg),
              AppButton(
                key: const Key('catalog-empty-reset'),
                label: 'Reset filters',
                variant: AppButtonVariant.secondary,
                onPressed: onReset,
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
    final tokens = AppTokens.of(context);
    return Container(
      key: const Key('catalog-error-banner'),
      margin: EdgeInsets.only(bottom: tokens.spaceSm),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spaceMd,
        vertical: tokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          tokens.danger.withValues(alpha: 0.12),
          tokens.surface,
        ),
        border: Border.all(color: tokens.danger.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: tokens.danger),
          SizedBox(width: tokens.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: tokens.bodyStyle.copyWith(color: tokens.danger),
                ),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.bodyStyle.copyWith(color: tokens.muted),
                ),
              ],
            ),
          ),
          AppButton(
            key: const Key('catalog-retry'),
            label: 'Retry',
            variant: AppButtonVariant.ghost,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
