import 'dart:async';

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import '../catalog/focus_ring.dart';
import '../common/app_status_strip.dart';
import '../common/upstream_status.dart';
import '../theme/app_primitives.dart';
import '../theme/app_tokens.dart';
import 'quest_filter_bar.dart';
import 'quest_list_row.dart';

export 'quest_filter_bar.dart' show QuestFilterOption;
export 'quest_list_row.dart'
    show
        QuestAvailabilityBadge,
        QuestLayout,
        QuestListRow,
        QuestStateBadge,
        QuestTableHeader,
        QuestTableRow,
        formatQuestProgress,
        questAvailabilityAppStatus,
        questLayoutForWidth,
        questListAppStatus,
        questProgressFraction,
        questStateAppStatus,
        questStateLabel;

/// The two views the quest screen switches between.
enum _QuestViewMode {
  /// Every quest in the active dataset, with search, filters and pagination.
  catalog,

  /// Only quests the active profile can start now, with its own ordering.
  available,
}

/// The searchable, filterable quest catalog plus the available-quests view.
///
/// The screen owns presentation state only: the data layer executes every
/// query through [QuestRepository]. It deliberately does not decide quest
/// availability, open a detail view or record progress; a row tap is reported
/// through [onQuestSelected].
///
/// Behavior:
///
/// * a Catalog/Available segment switches the list without changing route; the
///   available view uses the profile's derived statuses and its own ordering,
///   and explains an empty result instead of showing generic "no results";
/// * typing waits [searchDebounce] before it reaches the repository, and a
///   response that belongs to an older query is discarded, so fast typing
///   cannot make an old result overwrite a newer one;
/// * trader, map, level and state filters combine with AND with the search
///   text; each active filter appears as a removable token and the reset action
///   clears every filter and the search field;
/// * progress and game mode are read for [profileId] only: two profiles render
///   independent badges and never blend another mode's tasks; the repository
///   applies the mode filter, so a PvE-only quest is absent under a regular
///   profile;
/// * preserved progress for quests missing from the active dataset is listed in
///   an "Unavailable upstream" panel instead of being dropped;
/// * rows are built on demand by a `ListView.builder` and pages are appended
///   with the explicit load-more control, so a large catalog never
///   materializes as one widget tree;
/// * the layout is adaptive: a five-column table at 1100 logical pixels, an
///   extra `Level` column at 1600, and compact card rows below 1100;
/// * content width is capped at 1600 logical pixels so an ultra-wide monitor
///   never stretches the table into unreadable columns;
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
    this.upstreamCheck,
  });

  /// The widest the quest chrome and table may grow.
  static const double maxContentWidth = 1600;

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

  /// Optional upstream check. It runs beside the local query and never gates
  /// rows: a failure only adds a non-blocking status strip, or the explicit
  /// offline empty state when the current view has no saved results. The shell
  /// adapts `SyncService.prepare` to [UpstreamCheck].
  final UpstreamCheck? upstreamCheck;

  @override
  State<QuestListScreen> createState() => _QuestListScreenState();
}

class _QuestListScreenState extends State<QuestListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'quest-search');
  final FocusNode _screenFocus = FocusNode(
    debugLabel: 'quest-screen',
    skipTraversal: true,
  );
  Timer? _searchTimer;

  QuestFilters _filters = const QuestFilters();

  final List<QuestSummary> _quests = <QuestSummary>[];
  Map<String, QuestStatus> _statusById = const <String, QuestStatus>{};
  List<OrphanedQuestProgress> _orphans = const <OrphanedQuestProgress>[];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  late List<QuestFilterOption> _traderOptions;
  late List<QuestFilterOption> _mapOptions;

  _QuestViewMode _view = _QuestViewMode.catalog;
  QuestSort _availableSort = const QuestSort(QuestSortField.minPlayerLevel);

  /// Owns the optional upstream check; `null` when the shell supplied none.
  UpstreamStatusController? _upstream;

  /// Incremented for each repository request. Only the newest response may
  /// write to the state, which makes the debounce and page appends race-free.
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _traderOptions = widget.traderOptions;
    _mapOptions = widget.mapOptions;
    _attachUpstream(widget.upstreamCheck);
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
    if (oldWidget.upstreamCheck != widget.upstreamCheck) {
      _attachUpstream(widget.upstreamCheck);
    }
    if (widget.profileId != oldWidget.profileId ||
        widget.repository != oldWidget.repository ||
        widget.pageSize != oldWidget.pageSize) {
      _fetchFilterOptions();
      _reload();
    }
  }

  void _attachUpstream(UpstreamCheck? check) {
    _upstream?.removeListener(_onUpstreamChanged);
    _upstream?.dispose();
    _upstream = null;
    if (check == null) {
      return;
    }
    final controller = UpstreamStatusController(check: check);
    controller.addListener(_onUpstreamChanged);
    _upstream = controller;
    unawaited(controller.refresh());
  }

  void _onUpstreamChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _screenFocus.dispose();
    _upstream?.removeListener(_onUpstreamChanged);
    _upstream?.dispose();
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

  /// Reads the derived status for every quest so rows can show availability
  /// and an objective fraction. Without a profile there is nothing to derive;
  /// a profile that no longer exists also falls back to the recorded state.
  Future<Map<String, QuestStatus>> _loadStatuses() async {
    final profileId = widget.profileId;
    if (profileId == null) {
      return const <String, QuestStatus>{};
    }
    try {
      final statuses = await widget.repository.statuses(profileId);
      return <String, QuestStatus>{
        for (final status in statuses) status.id: status,
      };
    } on Object {
      return const <String, QuestStatus>{};
    }
  }

  bool get _hasMore => _quests.length < _total;

  QuestQuery _queryForOffset(int offset) => QuestQuery(
    filters: _filters,
    limit: widget.pageSize,
    offset: offset,
    profileId: widget.profileId,
  );

  /// Preserved progress whose quest left the active dataset.
  ///
  /// A read failure must not hide the catalog: the panel is additive, so it
  /// degrades to "no known orphans" instead of failing the screen.
  Future<List<OrphanedQuestProgress>> _loadOrphans() async {
    final profileId = widget.profileId;
    if (profileId == null) {
      return const <OrphanedQuestProgress>[];
    }
    try {
      return await widget.repository.orphanedProgress(profileId);
    } on Object {
      return const <OrphanedQuestProgress>[];
    }
  }

  Future<void> _fetchFirstPage(int generation) async {
    try {
      if (_view == _QuestViewMode.available) {
        final profileId = widget.profileId;
        final availableFuture = profileId == null
            ? Future<List<QuestStatus>>.value(const <QuestStatus>[])
            : widget.repository.availableQuests(
                profileId,
                sort: _availableSort,
              );
        final orphanFuture = _loadOrphans();
        final available = await availableFuture;
        final orphans = await orphanFuture;
        if (!mounted || generation != _requestGeneration) {
          return;
        }
        setState(() {
          _quests
            ..clear()
            ..addAll(available.map((status) => status.toSummary()));
          _statusById = <String, QuestStatus>{
            for (final status in available) status.id: status,
          };
          _total = available.length;
          _orphans = orphans;
          _loading = false;
          _loadingMore = false;
          _error = null;
        });
        return;
      }

      final pageFuture = widget.repository.query(_queryForOffset(0));
      final statusFuture = _loadStatuses();
      final orphanFuture = _loadOrphans();
      final page = await pageFuture;
      final statusById = await statusFuture;
      final orphans = await orphanFuture;
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _quests
          ..clear()
          ..addAll(page.quests);
        _total = page.total;
        _statusById = statusById;
        _orphans = orphans;
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
    if (_view != _QuestViewMode.catalog ||
        _loading ||
        _loadingMore ||
        !_hasMore) {
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

  void _setView(_QuestViewMode view) {
    if (view == _view) {
      return;
    }
    _searchTimer?.cancel();
    _searchFocus.unfocus();
    setState(() => _view = view);
    _reload();
  }

  /// `/` moves focus into the catalog search field and selects existing text.
  void _focusSearch() {
    _searchFocus.requestFocus();
    final text = _searchController.text;
    if (text.isNotEmpty) {
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: text.length,
      );
    }
  }

  /// Escape clears the search when there is text, then returns focus to the
  /// screen so the next Tab starts from the top of the list again.
  void _dismissSearch() {
    if (_searchController.text.isNotEmpty) {
      _clearSearch();
    }
    _screenFocus.requestFocus();
  }

  void _setAvailableSort(QuestSortField field) {
    final next = QuestSort(field);
    if (next == _availableSort) {
      return;
    }
    _availableSort = next;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final upstreamStrip = _buildUpstreamStrip();
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.slash): FocusSearchIntent(),
        SingleActivator(LogicalKeyboardKey.escape): DismissListFocusIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          FocusSearchIntent: GuardedCallbackAction<FocusSearchIntent>(
            enabled: () =>
                _view == _QuestViewMode.catalog && !_searchFocus.hasFocus,
            onInvoke: _focusSearch,
          ),
          DismissListFocusIntent: GuardedCallbackAction<DismissListFocusIntent>(
            enabled: () =>
                _searchFocus.hasFocus || _searchController.text.isNotEmpty,
            onInvoke: _dismissSearch,
          ),
        },
        child: Focus(
          key: const Key('quest-screen-focus'),
          focusNode: _screenFocus,
          autofocus: true,
          skipTraversal: true,
          includeSemantics: false,
          child: Scaffold(
            body: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  key: const Key('quest-content'),
                  constraints: const BoxConstraints(
                    maxWidth: QuestListScreen.maxContentWidth,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final layout = questLayoutForWidth(constraints.maxWidth);
                      return Padding(
                        padding: EdgeInsets.all(tokens.spaceLg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.profileId != null) ...[
                              _QuestViewSegment(
                                view: _view,
                                onChanged: _setView,
                              ),
                              SizedBox(height: tokens.spaceMd),
                            ],
                            if (_view == _QuestViewMode.catalog) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      key: const Key('quest-search-field'),
                                      controller: _searchController,
                                      focusNode: _searchFocus,
                                      textInputAction: TextInputAction.search,
                                      style: tokens.bodyStyle,
                                      decoration: InputDecoration(
                                        hintText: 'Search quests',
                                        prefixIcon: const Icon(Icons.search),
                                        suffixIcon:
                                            _searchController.text.isEmpty
                                            ? null
                                            : AppFocusRing(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      tokens.radiusPill,
                                                    ),
                                                focusKey: const Key(
                                                  'quest-clear-search-focus',
                                                ),
                                                ringKey: const Key(
                                                  'quest-clear-search-ring',
                                                ),
                                                child: IconButton(
                                                  key: const Key(
                                                    'quest-clear-search',
                                                  ),
                                                  tooltip: 'Clear search',
                                                  onPressed: _clearSearch,
                                                  icon: const Icon(Icons.close),
                                                ),
                                              ),
                                      ),
                                      onChanged: _onSearchChanged,
                                      onSubmitted: _onSearchSubmitted,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: tokens.spaceMd),
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
                            ] else
                              _AvailableToolbar(
                                sort: _availableSort,
                                onSortSelected: _setAvailableSort,
                              ),
                            SizedBox(height: tokens.spaceLg),
                            _QuestHeading(
                              title: _view == _QuestViewMode.available
                                  ? 'Available quests'
                                  : 'Quest catalog',
                              resultCount: _resultCountLabel,
                            ),
                            SizedBox(height: tokens.spaceSm),
                            if (upstreamStrip != null) ...[
                              AppFocusRing(
                                focusKey: const Key(
                                  'quest-upstream-retry-focus',
                                ),
                                ringKey: const Key('quest-upstream-retry-ring'),
                                child: upstreamStrip,
                              ),
                              SizedBox(height: tokens.spaceSm),
                            ],
                            if (_orphans.isNotEmpty) ...[
                              _UnavailableQuestsPanel(orphans: _orphans),
                              SizedBox(height: tokens.spaceSm),
                            ],
                            if (layout != QuestLayout.compact)
                              QuestTableHeader(layout: layout),
                            if (_loading && _quests.isNotEmpty)
                              LinearProgressIndicator(
                                key: const Key('quest-loading-bar'),
                                color: tokens.accent,
                                backgroundColor: tokens.surfaceRaised,
                                minHeight: 2,
                              ),
                            if (_error != null)
                              _QuestErrorBanner(
                                message: 'Could not load quests.',
                                detail: '$_error',
                                onRetry: _reload,
                              ),
                            if (layout == QuestLayout.compact)
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
          ),
        ),
      ),
    );
  }

  String get _resultCountLabel {
    if (_loading && _quests.isEmpty) {
      return 'Loading quests…';
    }
    if (_view == _QuestViewMode.available) {
      final count = _quests.length;
      return '$count available ${count == 1 ? 'quest' : 'quests'}';
    }
    return 'Showing ${_quests.length} of $_total quests';
  }

  /// Whether the body owns the offline state instead of the strip.
  bool get _showsOfflineEmpty {
    final status = _upstream?.status;
    if (status == null ||
        !status.isProblem ||
        _loading ||
        _error != null ||
        _quests.isNotEmpty) {
      return false;
    }
    return _view == _QuestViewMode.available || _filters.isEmpty;
  }

  Widget? _buildUpstreamStrip() {
    final controller = _upstream;
    if (controller == null) {
      return null;
    }
    final status = controller.status;
    if (status == null || _showsOfflineEmpty) {
      return null;
    }
    if (controller.isChecking && status.needsBanner) {
      return AppStatusStrip(
        key: const Key('quest-upstream-status'),
        kind: AppStatusStripKind.updating,
        message: 'Showing saved quests while the update check runs.',
      );
    }
    if (!status.needsBanner) {
      return null;
    }
    return AppStatusStrip.upstream(
      key: const Key('quest-upstream-status'),
      status: status,
      onRetry: controller.refresh,
    );
  }

  Widget _buildBody(QuestLayout layout) {
    if (_quests.isEmpty) {
      if (_loading) {
        return Center(
          child: CircularProgressIndicator(key: const Key('quest-loading')),
        );
      }
      if (_error != null) {
        return const SizedBox.shrink();
      }
      if (_showsOfflineEmpty) {
        final controller = _upstream!;
        if (_view == _QuestViewMode.available) {
          return _AvailableOfflineEmptyState(
            status: controller.status!,
            checking: controller.isChecking,
            onRetry: controller.isChecking ? null : controller.refresh,
            onOpenCatalog: () => _setView(_QuestViewMode.catalog),
          );
        }
        return _QuestOfflineEmptyState(
          status: controller.status!,
          checking: controller.isChecking,
          onRetry: controller.isChecking ? null : controller.refresh,
        );
      }
      if (_view == _QuestViewMode.available) {
        return _AvailableEmptyState(
          onOpenCatalog: () => _setView(_QuestViewMode.catalog),
        );
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
        final status = _statusById[quest.id];
        final onTap = widget.onQuestSelected == null
            ? null
            : () => widget.onQuestSelected!(quest.id);
        final Widget row;
        if (layout == QuestLayout.compact) {
          row = QuestListRow(
            quest: quest,
            status: status,
            traderLabel: _optionLabel(_traderOptions, quest.traderId),
            mapLabel: _optionLabel(_mapOptions, quest.mapId),
            onTap: onTap,
          );
        } else {
          row = QuestTableRow(
            quest: quest,
            layout: layout,
            status: status,
            index: index,
            traderLabel: _optionLabel(_traderOptions, quest.traderId),
            mapLabel: _optionLabel(_mapOptions, quest.mapId),
            onTap: onTap,
          );
        }
        return AppFocusRing(
          focusKey: ValueKey('quest-row-focus-${quest.id}'),
          ringKey: ValueKey('quest-row-focus-ring-${quest.id}'),
          borderRadius: BorderRadius.zero,
          scrollIntoView: true,
          child: row,
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

/// Switches the screen between the full catalog and the available-quests view.
class _QuestViewSegment extends StatelessWidget {
  const _QuestViewSegment({required this.view, required this.onChanged});

  final _QuestViewMode view;
  final ValueChanged<_QuestViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const Key('quest-view-segment'),
      spacing: AppTokens.of(context).spaceSm,
      runSpacing: AppTokens.of(context).spaceXs,
      children: [
        AppFocusRing(
          borderRadius: BorderRadius.circular(AppTokens.of(context).radiusPill),
          focusKey: const Key('quest-view-catalog-focus'),
          ringKey: const Key('quest-view-catalog-ring'),
          child: AppChip(
            key: const Key('quest-view-catalog'),
            label: 'Catalog',
            selected: view == _QuestViewMode.catalog,
            onTap: () => onChanged(_QuestViewMode.catalog),
          ),
        ),
        AppFocusRing(
          borderRadius: BorderRadius.circular(AppTokens.of(context).radiusPill),
          focusKey: const Key('quest-view-available-focus'),
          ringKey: const Key('quest-view-available-ring'),
          child: AppChip(
            key: const Key('quest-view-available'),
            label: 'Available',
            selected: view == _QuestViewMode.available,
            onTap: () => onChanged(_QuestViewMode.available),
          ),
        ),
      ],
    );
  }
}

/// The ordering control for the available-quests view.
///
/// The catalog filters do not apply here: the view is exactly "what can I start
/// now", so only the criterion the user chose is exposed.
class _AvailableToolbar extends StatelessWidget {
  const _AvailableToolbar({required this.sort, required this.onSortSelected});

  final QuestSort sort;
  final ValueChanged<QuestSortField> onSortSelected;

  static const _labels = <QuestSortField, String>{
    QuestSortField.minPlayerLevel: 'Level',
    QuestSortField.traderId: 'Trader',
    QuestSortField.mapId: 'Map',
    QuestSortField.name: 'Name',
  };

  static const _keys = <QuestSortField, String>{
    QuestSortField.minPlayerLevel: 'level',
    QuestSortField.traderId: 'trader',
    QuestSortField.mapId: 'map',
    QuestSortField.name: 'name',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Wrap(
      key: const Key('quest-available-ordering'),
      spacing: tokens.spaceSm,
      runSpacing: tokens.spaceXs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Order by', style: tokens.labelStyle),
        for (final field in _labels.keys)
          AppFocusRing(
            borderRadius: BorderRadius.circular(tokens.radiusPill),
            focusKey: Key('quest-available-order-${_keys[field]}-focus'),
            ringKey: Key('quest-available-order-${_keys[field]}-ring'),
            child: AppChip(
              key: Key('quest-available-order-${_keys[field]}'),
              label: _labels[field]!,
              selected: sort.field == field,
              onTap: () => onSortSelected(field),
            ),
          ),
      ],
    );
  }
}

/// The explicit empty state when no quest is saved and the upstream failed.
class _QuestOfflineEmptyState extends StatelessWidget {
  const _QuestOfflineEmptyState({
    required this.status,
    required this.checking,
    required this.onRetry,
  });

  final UpstreamStatus status;
  final bool checking;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          key: const Key('quest-offline-empty'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: tokens.danger),
            SizedBox(height: tokens.spaceMd),
            Text(
              status.state == UpstreamState.failed
                  ? 'No saved quests and the update failed.'
                  : 'No quests are saved yet.',
              key: const Key('quest-offline-empty-title'),
              textAlign: TextAlign.center,
              style: tokens.h2Style,
            ),
            SizedBox(height: tokens.spaceXs),
            Text(
              'Tarkov Companion reads from the local dataset first. There is '
              'no saved quest catalog on this device yet, and the last update '
              'check could not reach the upstream. Connect and retry to '
              'download it.',
              key: const Key('quest-offline-empty-detail'),
              textAlign: TextAlign.center,
              style: tokens.bodyStyle.copyWith(color: tokens.muted),
            ),
            SizedBox(height: tokens.spaceLg),
            AppFocusRing(
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              focusKey: const Key('quest-offline-retry-focus'),
              ringKey: const Key('quest-offline-retry-ring'),
              child: AppButton(
                key: const Key('quest-offline-retry'),
                label: checking ? 'Checking…' : 'Retry update',
                variant: AppButtonVariant.secondary,
                onPressed: onRetry,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The available view's explicit offline empty state.
///
/// Availability is derived from saved progress, so a failed upstream check
/// never invalidates an empty result; the copy says so and offers both a retry
/// and the catalog view.
class _AvailableOfflineEmptyState extends StatelessWidget {
  const _AvailableOfflineEmptyState({
    required this.status,
    required this.checking,
    required this.onRetry,
    required this.onOpenCatalog,
  });

  final UpstreamStatus status;
  final bool checking;
  final VoidCallback? onRetry;
  final VoidCallback onOpenCatalog;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          key: const Key('quest-available-offline-empty'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: tokens.danger),
            SizedBox(height: tokens.spaceMd),
            Text(
              'Nothing is available in the saved data.',
              key: const Key('quest-available-offline-title'),
              textAlign: TextAlign.center,
              style: tokens.h2Style,
            ),
            SizedBox(height: tokens.spaceXs),
            Text(
              'Availability is computed from saved progress, so the result is '
              'still valid while offline. The update check could not reach the '
              'upstream; retry to refresh the dataset, or open the catalog to '
              'review lock reasons.',
              key: const Key('quest-available-offline-detail'),
              textAlign: TextAlign.center,
              style: tokens.bodyStyle.copyWith(color: tokens.muted),
            ),
            SizedBox(height: tokens.spaceLg),
            Wrap(
              spacing: tokens.spaceSm,
              runSpacing: tokens.spaceSm,
              children: [
                AppFocusRing(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  focusKey: const Key('quest-available-offline-retry-focus'),
                  ringKey: const Key('quest-available-offline-retry-ring'),
                  child: AppButton(
                    key: const Key('quest-available-offline-retry'),
                    label: checking ? 'Checking…' : 'Retry update',
                    variant: AppButtonVariant.secondary,
                    onPressed: onRetry,
                  ),
                ),
                AppFocusRing(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  focusKey: const Key(
                    'quest-available-offline-open-catalog-focus',
                  ),
                  ringKey: const Key(
                    'quest-available-offline-open-catalog-ring',
                  ),
                  child: AppButton(
                    key: const Key('quest-available-offline-open-catalog'),
                    label: 'Open catalog',
                    variant: AppButtonVariant.ghost,
                    onPressed: onOpenCatalog,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The explanation shown when the profile can start nothing.
class _AvailableEmptyState extends StatelessWidget {
  const _AvailableEmptyState({required this.onOpenCatalog});

  final VoidCallback onOpenCatalog;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          key: const Key('quest-available-empty'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt, size: 48, color: tokens.dim),
            SizedBox(height: tokens.spaceMd),
            Text(
              'Nothing is available to start.',
              key: const Key('quest-available-empty-title'),
              textAlign: TextAlign.center,
              style: tokens.h2Style,
            ),
            SizedBox(height: tokens.spaceXs),
            Text(
              'Every quest is locked by a level, trader, or prerequisite '
              'requirement, already in progress, or completed. Open the '
              'catalog to see the specific lock reasons.',
              key: const Key('quest-available-empty-detail'),
              textAlign: TextAlign.center,
              style: tokens.bodyStyle.copyWith(color: tokens.muted),
            ),
            SizedBox(height: tokens.spaceLg),
            AppFocusRing(
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              focusKey: const Key('quest-available-open-catalog-focus'),
              ringKey: const Key('quest-available-open-catalog-ring'),
              child: AppButton(
                key: const Key('quest-available-open-catalog'),
                label: 'Open catalog',
                variant: AppButtonVariant.secondary,
                onPressed: onOpenCatalog,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Preserved progress for quests that are not in the active dataset.
///
/// The panel lists them separately instead of dropping them: the user's state
/// and objective counts are still there, but they are excluded from the
/// catalog, the available view and every prerequisite calculation.
class _UnavailableQuestsPanel extends StatelessWidget {
  const _UnavailableQuestsPanel({required this.orphans});

  final List<OrphanedQuestProgress> orphans;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return AppPanel(
      key: const Key('quest-unavailable-panel'),
      label: 'Unavailable upstream',
      trailing: AppStatusBadge(
        status: AppStatus.locked,
        label: '${orphans.length}',
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 180),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'These quests are missing from the active dataset. Their '
                'recorded progress is preserved, but they are excluded from '
                'requirement calculations.',
                key: const Key('quest-unavailable-detail'),
                style: tokens.bodyStyle.copyWith(color: tokens.muted),
              ),
              SizedBox(height: tokens.spaceSm),
              for (final orphan in orphans)
                Padding(
                  key: ValueKey('quest-unavailable-${orphan.questId}'),
                  padding: EdgeInsets.only(top: tokens.spaceXs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(orphan.questId, style: tokens.bodyStyle),
                            Text(
                              '${questStateLabel(orphan.state)} · '
                              '${orphan.objectiveCounts.length} objective '
                              '${orphan.objectiveCounts.length == 1 ? 'count' : 'counts'} '
                              'preserved',
                              style: tokens.labelStyle.copyWith(
                                color: tokens.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: tokens.spaceSm),
                      const AppStatusBadge(
                        status: AppStatus.locked,
                        label: 'Unavailable',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The quest title and the result count.
class _QuestHeading extends StatelessWidget {
  const _QuestHeading({required this.title, required this.resultCount});

  final String title;
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
              const AppSectionLabel('Quests'),
              SizedBox(height: tokens.spaceXs),
              Text(title, style: tokens.h1Style),
            ],
          ),
        ),
        Text(
          resultCount,
          key: const Key('quest-result-count'),
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
            key: const Key('quest-loaded-count'),
            style: tokens.dataStyle.copyWith(color: tokens.muted),
          ),
          SizedBox(height: tokens.spaceSm),
          AppFocusRing(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            focusKey: const Key('quest-load-more-focus'),
            ringKey: const Key('quest-load-more-ring'),
            child: AppButton(
              key: const Key('quest-load-more'),
              label: 'Load more',
              variant: AppButtonVariant.secondary,
              onPressed: loading ? null : onLoadMore,
            ),
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
    final tokens = AppTokens.of(context);
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
            Icon(Icons.search_off, size: 48, color: tokens.dim),
            SizedBox(height: tokens.spaceMd),
            Text(
              headline,
              key: const Key('quest-empty-title'),
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
              AppFocusRing(
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                focusKey: const Key('quest-empty-reset-focus'),
                ringKey: const Key('quest-empty-reset-ring'),
                child: AppButton(
                  key: const Key('quest-empty-reset'),
                  label: 'Reset filters',
                  variant: AppButtonVariant.secondary,
                  onPressed: onReset,
                ),
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
    final tokens = AppTokens.of(context);
    return Container(
      key: const Key('quest-error-banner'),
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
          AppFocusRing(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            focusKey: const Key('quest-retry-focus'),
            ringKey: const Key('quest-retry-ring'),
            child: AppButton(
              key: const Key('quest-retry'),
              label: 'Retry',
              variant: AppButtonVariant.ghost,
              onPressed: onRetry,
            ),
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
