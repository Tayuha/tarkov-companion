import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import '../common/app_status_strip.dart';
import '../common/upstream_status.dart';
import '../theme/app_primitives.dart';
import '../theme/app_tokens.dart';
import 'catalog_item_row.dart' show changeColor, formatChange, formatRoubles;
import 'item_image.dart';
import 'price_history_chart.dart';

/// The full item detail view.
///
/// The screen reads one [ItemDetail] and its [ItemRelations] through
/// [CatalogRepository] and renders a header, the base properties every item
/// has, prices, acquisition/disposition relationships and one type-specific
/// section. Sections and rows are built from the typed [ItemProperties]
/// subclass, so a property that does not apply to the item's kind cannot reach
/// the tree: a weapon never shows damage, ammunition never shows ergonomics,
/// and a barter-only item gets no type-specific section at all. A missing fact
/// produces no row; a zero *price* is the one real observation that gets an
/// explicit label instead of being omitted.
///
/// The layout caps its width and, from 1080 logical pixels, splits
/// base/price/typed facts from categories, links, relationships and history
/// into two columns. Narrow windows keep the single ordered column.
///
/// Both the image cache and the price-history repository are injectable. When
/// they are omitted the header keeps its neutral placeholder and the history
/// section is omitted, so the screen still performs no I/O.
class ItemDetailScreen extends StatefulWidget {
  const ItemDetailScreen({
    super.key,
    required this.repository,
    required this.itemId,
    this.onBack,
    this.imageCache,
    this.priceHistory,
    this.offline = false,
    this.upstreamCheck,
  });

  final CatalogRepository repository;

  /// Upstream item id to resolve.
  final String itemId;

  /// Called by the not-found back action. When omitted, the screen pops the
  /// current route, which is the normal behavior for a pushed detail page.
  final VoidCallback? onBack;

  /// Optional disk-backed item image cache. Without it the header keeps its
  /// neutral placeholder and performs no I/O.
  final ItemImageCache? imageCache;

  /// Optional on-demand price-history source. Without it the history section
  /// is omitted entirely rather than rendering an empty chart.
  final PriceHistoryRepository? priceHistory;

  /// Whether the history fetch runs in offline mode (cache only).
  final bool offline;

  /// Optional upstream check shown as a non-blocking strip above the detail.
  /// The saved item stays visible while the check fails.
  final UpstreamCheck? upstreamCheck;

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  ItemDetail? _detail;
  ItemRelations? _relations;
  PriceHistorySnapshot? _history;
  Object? _error;
  bool _loading = true;
  bool _historyLoading = false;
  int _generation = 0;

  /// Owns the optional upstream check; `null` when the caller supplied none.
  UpstreamStatusController? _upstream;

  @override
  void initState() {
    super.initState();
    _attachUpstream(widget.upstreamCheck);
    _load();
  }

  @override
  void didUpdateWidget(ItemDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.upstreamCheck != widget.upstreamCheck) {
      _attachUpstream(widget.upstreamCheck);
    }
    if (oldWidget.itemId != widget.itemId ||
        oldWidget.repository != widget.repository ||
        oldWidget.priceHistory != widget.priceHistory ||
        oldWidget.offline != widget.offline) {
      _load();
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
    _upstream?.removeListener(_onUpstreamChanged);
    _upstream?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _detail = null;
      _relations = null;
      _history = null;
      _historyLoading = widget.priceHistory != null;
      _error = null;
    });
    try {
      final detail = await widget.repository.itemDetail(widget.itemId);
      final relations = detail == null
          ? null
          : await widget.repository.itemRelations(widget.itemId);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _detail = detail;
        _relations = relations;
        _loading = false;
      });

      final history = widget.priceHistory;
      if (detail == null || history == null) {
        if (mounted && generation == _generation) {
          setState(() => _historyLoading = false);
        }
        return;
      }
      final snapshot = await history.load(
        widget.itemId,
        offline: widget.offline,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _history = snapshot;
        _historyLoading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _loading = false;
        _historyLoading = false;
        _error = error;
      });
    }
  }

  Future<void> _reloadHistory() async {
    final history = widget.priceHistory;
    final detail = _detail;
    if (history == null || detail == null) {
      return;
    }
    final generation = _generation;
    setState(() => _historyLoading = true);
    try {
      final snapshot = await history.load(
        widget.itemId,
        offline: widget.offline,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _history = snapshot;
        _historyLoading = false;
      });
    } on Object {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() => _historyLoading = false);
    }
  }

  void _back() {
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      key: const Key('item-detail-screen'),
      appBar: AppBar(title: Text(detail?.name ?? 'Item detail')),
      body: SafeArea(child: _buildBody(detail)),
    );
  }

  Widget _buildBody(ItemDetail? detail) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(key: const Key('item-detail-loading')),
      );
    }
    final error = _error;
    if (error != null) {
      return isUpstreamError(error)
          ? _UpstreamErrorState(error: error, onRetry: _load)
          : _ErrorState(error: error, onRetry: _load);
    }
    if (detail == null) {
      return _NotFoundState(itemId: widget.itemId, onBack: _back);
    }
    final content = _DetailBody(
      detail: detail,
      relations: _relations,
      history: _history,
      historyLoading: _historyLoading,
      imageCache: widget.imageCache,
      onHistoryRetry: widget.priceHistory == null ? null : _reloadHistory,
    );
    final strip = _buildUpstreamStrip();
    if (strip == null) {
      return content;
    }
    final tokens = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            tokens.spaceXl,
            tokens.spaceXl,
            tokens.spaceXl,
            0,
          ),
          child: strip,
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget? _buildUpstreamStrip() {
    final controller = _upstream;
    final status = controller?.status;
    if (controller == null || status == null) {
      return null;
    }
    if (controller.isChecking && status.needsBanner) {
      return AppStatusStrip(
        key: const Key('item-detail-upstream-status'),
        kind: AppStatusStripKind.updating,
        message: 'Showing the saved item while the update check runs.',
      );
    }
    if (!status.needsBanner) {
      return null;
    }
    return AppStatusStrip.upstream(
      key: const Key('item-detail-upstream-status'),
      status: status,
      onRetry: controller.refresh,
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.detail,
    required this.relations,
    required this.history,
    required this.historyLoading,
    required this.imageCache,
    required this.onHistoryRetry,
  });

  /// The widest the inspector grows, even on a 1920 monitor.
  static const double _maxContentWidth = 1180;

  /// At or above this width, related facts move into a second column.
  static const double _twoColumnBreakpoint = 1080;

  final ItemDetail detail;
  final ItemRelations? relations;
  final PriceHistorySnapshot? history;
  final bool historyLoading;
  final ItemImageCache? imageCache;
  final VoidCallback? onHistoryRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final typed = _buildTypedSection(detail.properties);
    final properties = _buildProperties(context, detail);
    final price = _buildPriceSection(context, detail);
    final historySection = _buildHistorySection(context);
    final acquisition = _buildAcquisition(context, relations);
    final disposition = _buildDisposition(context, relations);
    final categories = detail.categories.isEmpty
        ? null
        : _DetailSection(
            title: 'Categories',
            children: [
              Wrap(
                key: const Key('item-detail-categories'),
                spacing: tokens.spaceSm,
                runSpacing: tokens.spaceSm,
                children: [
                  for (final category in detail.categories)
                    _TagChip(label: category.name),
                ],
              ),
            ],
          );
    final links = detail.wikiLink == null && detail.link == null
        ? null
        : _DetailSection(
            title: 'Links',
            children: [
              if (detail.wikiLink != null)
                _PropertyRow(
                  label: 'Wiki',
                  child: SelectableText(
                    detail.wikiLink!,
                    key: const Key('item-detail-wiki-link'),
                    style: tokens.bodyStyle.copyWith(color: tokens.info),
                  ),
                ),
              if (detail.link != null)
                _PropertyRow(
                  label: 'Page',
                  child: SelectableText(
                    detail.link!,
                    key: const Key('item-detail-page-link'),
                    style: tokens.bodyStyle.copyWith(color: tokens.info),
                  ),
                ),
            ],
          );
    final description = detail.description == null
        ? null
        : _DetailSection(
            title: 'Description',
            children: [
              Text(
                detail.description!,
                style: tokens.bodyStyle.copyWith(color: tokens.muted),
              ),
            ],
          );

    return SingleChildScrollView(
      key: const Key('item-detail-scroll'),
      padding: EdgeInsets.all(tokens.spaceXl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final twoColumn = constraints.maxWidth >= _twoColumnBreakpoint;
              final left = <Widget>[?properties, ?price, ?typed, ?description];
              final right = <Widget>[
                ?categories,
                ?links,
                ?acquisition,
                ?disposition,
                ?historySection,
              ];

              final content = twoColumn && right.isNotEmpty
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _Stack(children: left)),
                        SizedBox(width: tokens.spaceXl),
                        SizedBox(width: 340, child: _Stack(children: right)),
                      ],
                    )
                  : _Stack(
                      children: [
                        ?properties,
                        ?price,
                        ?categories,
                        ?links,
                        ?acquisition,
                        ?disposition,
                        ?historySection,
                        ?typed,
                        ?description,
                      ],
                    );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(detail: detail, imageCache: imageCache),
                  SizedBox(height: tokens.spaceXl),
                  content,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget? _buildProperties(BuildContext context, ItemDetail detail) {
    final tokens = AppTokens.of(context);
    final tiles = <Widget>[
      if (detail.weight != null)
        AppStatTile(
          label: 'Weight',
          value: '${_formatNumber(detail.weight!)} kg',
        ),
      if (detail.gridSize != null)
        AppStatTile(label: 'Grid size', value: '${detail.gridSize} slots'),
      if (detail.stackMaxSize != null)
        AppStatTile(label: 'Stack limit', value: '${detail.stackMaxSize}'),
    ];
    if (tiles.isEmpty) {
      return null;
    }
    return _DetailSection(
      key: const Key('item-detail-section-properties'),
      title: 'Properties',
      children: [
        Wrap(
          spacing: tokens.spaceSm,
          runSpacing: tokens.spaceSm,
          children: [
            for (final tile in tiles) SizedBox(width: 180, child: tile),
          ],
        ),
      ],
    );
  }

  Widget? _buildPriceSection(BuildContext context, ItemDetail detail) {
    final price = detail.price;
    if (price.isEmpty && detail.basePrice == null) {
      return null;
    }
    final tokens = AppTokens.of(context);
    final rows = <Widget>[];
    final fleaLabel = Text(
      detail.fleaEligible
          ? 'No flea price observed yet.'
          : 'Not available on the flea market.',
      key: const Key('item-detail-price-missing'),
      style: tokens.bodyStyle.copyWith(color: tokens.muted),
    );
    final lastLow = price.fleaLastLow;
    final average = price.fleaAvg24h;
    if (lastLow == null && average == null) {
      rows.add(_PropertyRow(label: 'Flea market', child: fleaLabel));
    } else {
      if (lastLow != null) {
        if (lastLow == 0) {
          rows.add(
            _PropertyRow(
              label: 'Flea · low',
              child: Text(
                'No flea offers (0 ₽)',
                key: const Key('item-detail-price-zero'),
                style: tokens.dataStyle.copyWith(color: tokens.muted),
              ),
            ),
          );
        } else {
          rows.add(
            _PropertyRow(
              label: 'Flea · low',
              child: Text(
                formatRoubles(lastLow),
                key: const Key('item-detail-price-flea'),
                style: tokens.dataStyle.copyWith(color: tokens.value),
              ),
            ),
          );
        }
      }
      if (average != null && average > 0) {
        rows.add(
          _PropertyRow(
            label: 'Flea · 24 h avg',
            child: Text(
              formatRoubles(average),
              key: const Key('item-detail-price-avg'),
              style: tokens.dataStyle.copyWith(color: tokens.text),
            ),
          ),
        );
      }
      final change = price.change48hPercent;
      if (change != null) {
        rows.add(
          _PropertyRow(
            label: 'Flea · 48 h',
            child: Text(
              _formatPriceChange(change, price.change48hAbsolute),
              key: const Key('item-detail-price-change'),
              style: tokens.dataStyle.copyWith(
                color: changeColor(tokens, change),
              ),
            ),
          ),
        );
      }
    }
    if (detail.basePrice != null) {
      rows.add(
        _PropertyRow(
          label: 'Trader · base',
          child: Text(
            formatRoubles(detail.basePrice),
            key: const Key('item-detail-price-base'),
            style: tokens.dataStyle.copyWith(color: tokens.text),
          ),
        ),
      );
    }
    final observedAt = price.observedAt;
    if (observedAt != null) {
      rows.add(
        _PropertyRow(
          label: 'Observed',
          child: Text(
            _formatTimestamp(observedAt),
            key: const Key('item-detail-price-observed'),
            style: tokens.dataStyle.copyWith(color: tokens.muted),
          ),
        ),
      );
    }
    if (rows.isEmpty) {
      return null;
    }
    return _DetailSection(
      key: const Key('item-detail-section-prices'),
      title: 'Prices',
      children: rows,
    );
  }

  Widget? _buildHistorySection(BuildContext context) {
    if (!historyLoading && history == null) {
      return null;
    }
    final tokens = AppTokens.of(context);
    return _DetailSection(
      key: const Key('item-detail-section-history'),
      title: 'Price history',
      children: [
        if (historyLoading)
          LinearProgressIndicator(
            key: const Key('item-detail-history-loading'),
            color: tokens.accent,
            backgroundColor: tokens.surfaceRaised,
            minHeight: 2,
          )
        else if (history != null)
          PriceHistoryChart(snapshot: history!, onRetry: onHistoryRetry),
      ],
    );
  }

  Widget? _buildAcquisition(BuildContext context, ItemRelations? relations) {
    if (relations == null) {
      return null;
    }
    final rows = <Widget>[
      for (final offer in relations.buyOffers)
        _PropertyRow(
          key: ValueKey('item-detail-buy-${offer.traderId}'),
          label: offer.traderName,
          child: _offerLine(context, offer),
        ),
      for (final barter in relations.barters)
        _PropertyRow(
          key: ValueKey('item-detail-barter-${barter.id}'),
          label: barter.traderName,
          child: _relationLine(
            context,
            '${_formatQuantities(barter.requiredItems)} → '
            '${_formatQuantity(barter.offeredItem)}',
          ),
        ),
      for (final craft in relations.crafts)
        _PropertyRow(
          key: ValueKey('item-detail-craft-${craft.id}'),
          label: craft.stationName,
          child: _relationLine(
            context,
            '${_formatQuantities(craft.requiredItems)} → '
            '${_formatQuantity(craft.product)} · '
            '${_formatDuration(craft.durationSeconds)}',
          ),
        ),
      for (final quest in relations.quests)
        _PropertyRow(
          key: ValueKey(
            'item-detail-quest-${quest.questId}-${quest.kind.name}',
          ),
          label: quest.questName,
          child: _relationLine(
            context,
            quest.detail ?? 'Requires this item',
            key: ValueKey('item-detail-quest-detail-${quest.questId}'),
          ),
        ),
    ];
    if (rows.isEmpty) {
      return null;
    }
    return _DetailSection(
      key: const Key('item-detail-section-acquisition'),
      title: 'Acquisition',
      children: rows,
    );
  }

  Widget? _buildDisposition(BuildContext context, ItemRelations? relations) {
    if (relations == null) {
      return null;
    }
    final rows = <Widget>[
      for (final offer in relations.sellOffers)
        _PropertyRow(
          key: ValueKey('item-detail-sell-${offer.traderId}'),
          label: offer.traderName,
          child: _offerLine(context, offer),
        ),
      for (final barter in relations.bartersUsing)
        _PropertyRow(
          key: ValueKey('item-detail-barter-input-${barter.id}'),
          label: barter.traderName,
          child: _relationLine(
            context,
            'Used for ${_formatQuantity(barter.offeredItem)}',
          ),
        ),
      for (final craft in relations.craftsUsing)
        _PropertyRow(
          key: ValueKey('item-detail-craft-input-${craft.id}'),
          label: craft.stationName,
          child: _relationLine(
            context,
            'Used for ${_formatQuantity(craft.product)}',
          ),
        ),
    ];
    if (rows.isEmpty) {
      return null;
    }
    return _DetailSection(
      key: const Key('item-detail-section-disposition'),
      title: 'Disposition',
      children: rows,
    );
  }

  Widget _offerLine(BuildContext context, TraderOffer offer) {
    final tokens = AppTokens.of(context);
    final meta = <String>[
      if (offer.loyaltyLevel != null) 'LL ${offer.loyaltyLevel}',
      if (offer.buyLimit != null) 'limit ${offer.buyLimit}',
      if (offer.taskUnlockName != null) 'unlocked by ${offer.taskUnlockName}',
    ];
    return Row(
      children: [
        Text(
          _formatCurrency(offer.price, offer.currency),
          style: tokens.dataStyle.copyWith(color: tokens.value),
        ),
        if (meta.isNotEmpty) ...[
          SizedBox(width: tokens.spaceSm),
          Flexible(
            child: Text(
              meta.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.labelStyle.copyWith(color: tokens.dim),
            ),
          ),
        ],
      ],
    );
  }

  Widget _relationLine(BuildContext context, String text, {Key? key}) {
    final tokens = AppTokens.of(context);
    return Text(
      text,
      key: key,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: tokens.dataStyle.copyWith(color: tokens.text),
    );
  }

  Widget? _buildTypedSection(ItemProperties properties) {
    return switch (properties) {
      WeaponProperties() => _WeaponSection(properties: properties),
      AmmunitionProperties() => _AmmunitionSection(properties: properties),
      ArmorProperties() => _ArmorSection(properties: properties),
      MedicalProperties() => _MedicalSection(properties: properties),
      GenericProperties() => null,
    };
  }
}

/// A vertical stack with the 16 px section rhythm.
class _Stack extends StatelessWidget {
  const _Stack({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) SizedBox(height: tokens.spaceLg),
          children[index],
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detail, this.imageCache});

  final ItemDetail detail;
  final ItemImageCache? imageCache;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ItemImage(
          cache: imageCache,
          url: detail.iconLink,
          size: 120,
          iconSize: 52,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          placeholderKey: const Key('item-detail-icon-placeholder'),
          imageKey: const Key('item-detail-icon'),
        ),
        SizedBox(width: tokens.spaceXl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSectionLabel('Item ${detail.id}'),
              SizedBox(height: tokens.spaceXs),
              Text(
                detail.name,
                key: const Key('item-detail-name'),
                style: tokens.h1Style,
              ),
              SizedBox(height: tokens.spaceXs),
              Text(
                detail.shortName,
                key: const Key('item-detail-short-name'),
                style: tokens.dataStyle.copyWith(color: tokens.muted),
              ),
              SizedBox(height: tokens.spaceMd),
              Wrap(
                spacing: tokens.spaceSm,
                runSpacing: tokens.spaceSm,
                children: [
                  for (final type in detail.types)
                    _TagChip(label: humanizeLabel(type)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeaponSection extends StatelessWidget {
  const _WeaponSection({required this.properties});

  final WeaponProperties properties;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final caliber = properties.caliber;
    if (caliber != null) {
      rows.add(_PropertyRow(label: 'Caliber', value: formatCaliber(caliber)));
    }
    if (properties.fireRate != null) {
      rows.add(
        _PropertyRow(label: 'Fire rate', value: '${properties.fireRate} rpm'),
      );
    }
    if (properties.ergonomics != null) {
      rows.add(
        _PropertyRow(label: 'Ergonomics', value: '${properties.ergonomics}'),
      );
    }
    final recoil = _formatRecoil(properties);
    if (recoil != null) {
      rows.add(_PropertyRow(label: 'Recoil', value: recoil));
    }
    if (properties.effectiveDistance != null) {
      rows.add(
        _PropertyRow(
          label: 'Effective range',
          value: '${properties.effectiveDistance} m',
        ),
      );
    }
    if (properties.fireModes.isNotEmpty) {
      rows.add(
        _PropertyRow(
          label: 'Fire modes',
          value: properties.fireModes.join(' · '),
        ),
      );
    }
    if (properties.slots.isNotEmpty) {
      rows.add(
        _PropertyRow(
          label: 'Compatible slots',
          child: Wrap(
            key: const Key('item-detail-weapon-slots'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final slot in properties.slots)
                _TagChip(
                  label: slot.required ? '${slot.name} · required' : slot.name,
                ),
            ],
          ),
        ),
      );
    }
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return _DetailSection(
      key: const Key('item-detail-section-weapon'),
      title: 'Weapon',
      children: rows,
    );
  }

  static String? _formatRecoil(WeaponProperties properties) {
    final vertical = properties.recoilVertical;
    final horizontal = properties.recoilHorizontal;
    if (vertical != null && horizontal != null) {
      return 'Vertical $vertical · Horizontal $horizontal';
    }
    if (vertical != null) {
      return 'Vertical $vertical';
    }
    if (horizontal != null) {
      return 'Horizontal $horizontal';
    }
    return null;
  }
}

class _AmmunitionSection extends StatelessWidget {
  const _AmmunitionSection({required this.properties});

  final AmmunitionProperties properties;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final caliber = properties.caliber;
    if (caliber != null) {
      rows.add(_PropertyRow(label: 'Caliber', value: formatCaliber(caliber)));
    }
    if (properties.damage != null) {
      rows.add(_PropertyRow(label: 'Damage', value: '${properties.damage}'));
    }
    if (properties.penetrationPower != null) {
      rows.add(
        _PropertyRow(
          label: 'Penetration',
          value: '${properties.penetrationPower}',
        ),
      );
    }
    if (properties.armorDamage != null) {
      rows.add(
        _PropertyRow(label: 'Armor damage', value: '${properties.armorDamage}'),
      );
    }
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return _DetailSection(
      key: const Key('item-detail-section-ammunition'),
      title: 'Ammunition',
      children: rows,
    );
  }
}

class _ArmorSection extends StatelessWidget {
  const _ArmorSection({required this.properties});

  final ArmorProperties properties;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (properties.armorClass != null) {
      rows.add(
        _PropertyRow(label: 'Class', value: 'Class ${properties.armorClass}'),
      );
    }
    if (properties.durability != null) {
      rows.add(
        _PropertyRow(label: 'Durability', value: '${properties.durability}'),
      );
    }
    if (properties.zones.isNotEmpty) {
      rows.add(
        _PropertyRow(
          label: 'Protected zones',
          value: properties.zones.join(', '),
        ),
      );
    }
    if (properties.material != null) {
      rows.add(
        _PropertyRow(
          label: 'Material',
          value: humanizeLabel(properties.material!),
        ),
      );
    }
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return _DetailSection(
      key: const Key('item-detail-section-armor'),
      title: 'Armor',
      children: rows,
    );
  }
}

class _MedicalSection extends StatelessWidget {
  const _MedicalSection({required this.properties});

  final MedicalProperties properties;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (properties.uses != null) {
      rows.add(_PropertyRow(label: 'Uses', value: '${properties.uses}'));
    }
    final healing = _formatHealing(properties);
    if (healing != null) {
      rows.add(_PropertyRow(label: 'Healing', value: healing));
    }
    final effects = _formatEffects(properties);
    if (effects != null) {
      rows.add(_PropertyRow(label: 'Effects', value: effects));
    }
    if (properties.useTime != null) {
      rows.add(
        _PropertyRow(
          label: 'Use time',
          value: '${_formatNumber(properties.useTime!)} s',
        ),
      );
    }
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return _DetailSection(
      key: const Key('item-detail-section-medical'),
      title: 'Medical',
      children: rows,
    );
  }

  static String? _formatHealing(MedicalProperties properties) {
    final parts = <String>[
      if (properties.hitpoints != null) '${properties.hitpoints} HP',
      if (properties.maxHealPerUse != null)
        '${properties.maxHealPerUse} HP per use',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String? _formatEffects(MedicalProperties properties) {
    final effects = <String>[
      for (final cure in properties.cures) humanizeLabel(cure),
      for (final stim in properties.stimEffects)
        if (stim.type != null) humanizeLabel(stim.type!),
    ];
    return effects.isEmpty ? null : effects.join(', ');
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// One label/value row. A caller only adds a row when it has a value; [value]
/// and [child] are therefore never an "N/A" fallback.
class _PropertyRow extends StatelessWidget {
  const _PropertyRow({super.key, required this.label, this.value, this.child});

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: tokens.bodyStyle.copyWith(color: tokens.muted),
            ),
          ),
          Expanded(
            child:
                child ??
                Text(
                  value ?? '',
                  style: tokens.dataStyle.copyWith(color: tokens.text),
                ),
          ),
        ],
      ),
    );
  }
}

/// A quiet bordered tag that keeps its sentence-case label.
///
/// [AppChip] uppercases by design; item categories and slots are proper names,
/// so they get the same geometry without the case transform.
class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      height: 24,
      padding: EdgeInsets.symmetric(horizontal: tokens.spaceMd),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border.all(color: tokens.borderSoft),
        borderRadius: BorderRadius.circular(tokens.radiusPill),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.bodyStyle.copyWith(
            fontSize: tokens.dataSize,
            color: tokens.muted,
          ),
        ),
      ),
    );
  }
}

class _NotFoundState extends StatelessWidget {
  const _NotFoundState({required this.itemId, required this.onBack});

  final String itemId;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: tokens.dim),
            SizedBox(height: tokens.spaceMd),
            Text(
              'Item no longer available',
              key: const Key('item-detail-not-found'),
              textAlign: TextAlign.center,
              style: tokens.h2Style,
            ),
            SizedBox(height: tokens.spaceXs),
            Text(
              'Item $itemId is not in the current dataset. It may have been '
              'removed upstream.',
              textAlign: TextAlign.center,
              style: tokens.bodyStyle.copyWith(color: tokens.muted),
            ),
            SizedBox(height: tokens.spaceLg),
            AppButton(
              key: const Key('item-detail-back'),
              label: 'Back to catalog',
              variant: AppButtonVariant.secondary,
              onPressed: onBack,
            ),
          ],
        ),
      ),
    );
  }
}

class _UpstreamErrorState extends StatelessWidget {
  const _UpstreamErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppStatusStrip.upstream(
              key: const Key('item-detail-upstream-error'),
              status: UpstreamStatus.fromError(error),
              onRetry: onRetry,
            ),
            SizedBox(height: tokens.spaceLg),
            Text(
              'The saved item could not be refreshed.',
              key: const Key('item-detail-offline-title'),
              textAlign: TextAlign.center,
              style: tokens.h2Style,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: tokens.danger),
            SizedBox(height: tokens.spaceMd),
            Text(
              'Could not load this item.',
              key: const Key('item-detail-error'),
              textAlign: TextAlign.center,
              style: tokens.h2Style,
            ),
            SizedBox(height: tokens.spaceXs),
            Text(
              '$error',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: tokens.bodyStyle.copyWith(color: tokens.muted),
            ),
            SizedBox(height: tokens.spaceLg),
            AppButton(
              key: const Key('item-detail-retry'),
              label: 'Retry',
              variant: AppButtonVariant.secondary,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatPriceChange(double percent, int? absolute) {
  final direction = percent > 0 ? 'Rising' : (percent < 0 ? 'Falling' : 'Flat');
  final parts = <String>[direction, formatChange(percent)];
  if (absolute != null && absolute != 0) {
    parts.add(_formatSignedRoubles(absolute));
  }
  return parts.join(' · ');
}

String _formatSignedRoubles(int value) {
  final sign = value > 0 ? '+' : '';
  return '$sign${formatRoubles(value)}';
}

String _formatTimestamp(DateTime value) {
  final utc = value.toUtc();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
      '${two(utc.hour)}:${two(utc.minute)} UTC';
}

String _formatCurrency(int amount, String currency) {
  final symbol = switch (currency.toUpperCase()) {
    'RUB' => '₽',
    'USD' => '\$',
    'EUR' => '€',
    _ => currency,
  };
  final digits = amount.abs().toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${amount < 0 ? '-' : ''}$grouped $symbol';
}

String _formatQuantity(ItemQuantity quantity) =>
    '${quantity.count} × ${quantity.name}';

String _formatQuantities(List<ItemQuantity> quantities) =>
    quantities.map(_formatQuantity).join(' + ');

String _formatDuration(int seconds) {
  if (seconds <= 0) {
    return 'instant';
  }
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remaining = seconds % 60;
  if (hours > 0) {
    return minutes > 0 ? '$hours h $minutes min' : '$hours h';
  }
  if (minutes > 0) {
    return remaining > 0 ? '$minutes min $remaining s' : '$minutes min';
  }
  return '$remaining s';
}

/// Turns a bundle token into a display label (`noFlea` -> `No flea`,
/// `LightBleeding` -> `Light bleeding`).
String humanizeLabel(String value) {
  final spaced = value
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
  if (spaced.isEmpty) {
    return value;
  }
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// Formats a bundle caliber id (`Caliber556x45NATO` -> `5.56x45 NATO`).
String formatCaliber(String value) {
  final raw = value.startsWith('Caliber')
      ? value.substring('Caliber'.length)
      : value;
  final match = RegExp(r'^(\d+)x(\d+)(.*)$').firstMatch(raw);
  if (match == null) {
    return humanizeLabel(raw);
  }
  final first = _caliberNumber(int.parse(match.group(1)!));
  final second = _caliberNumber(int.parse(match.group(2)!));
  final suffix = match.group(3)!.trim();
  return suffix.isEmpty ? '${first}x$second' : '${first}x$second $suffix';
}

String _caliberNumber(int value) {
  if (value < 100) {
    return '$value';
  }
  return (value / 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
