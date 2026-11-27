import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import '../theme/app_tokens.dart';
import 'item_image.dart';

/// The responsive layouts of the catalog.
enum CatalogLayout {
  /// Touch-sized card rows without a header, below 1100 logical pixels.
  compact,

  /// The five-column table: item, flea/base, 24 h, weight and slots.
  standard,

  /// The standard table plus the price-observation age and a wider item cell.
  wide,
}

/// Picks the catalog layout for a content width.
///
/// `wide` starts at the 1600 px content cap, so only a 1920-class window (or
/// wider) gets the extra `Observed` column. Windows below 1100 keep the compact
/// card list.
CatalogLayout catalogLayoutForWidth(double width) {
  if (width >= 1600) {
    return CatalogLayout.wide;
  }
  if (width >= 1100) {
    return CatalogLayout.standard;
  }
  return CatalogLayout.compact;
}

/// One two-line cell for the desktop table header and its data rows.
class CatalogTableCell extends StatelessWidget {
  const CatalogTableCell({
    super.key,
    required this.child,
    this.alignment = CrossAxisAlignment.start,
    this.horizontalPadding = 0,
  });

  final Widget child;
  final CrossAxisAlignment alignment;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Column(
        crossAxisAlignment: alignment,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [child],
      ),
    );
  }
}

/// The column frame shared by [CatalogTableHeader] and [CatalogTableRow].
///
/// Keeping one widget for both means the header and the cells can never drift
/// apart when a column is added or widened.
class _CatalogColumns extends StatelessWidget {
  const _CatalogColumns({required this.layout, required this.cells});

  final CatalogLayout layout;

  /// Item, flea/base, 24 h, weight, slots and (wide only) observed.
  final List<Widget> cells;

  bool get _showObserved => layout == CatalogLayout.wide;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final itemFlex = layout == CatalogLayout.wide ? 5 : 3;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: itemFlex, child: cells[0]),
        SizedBox(width: tokens.spaceSm),
        SizedBox(width: 170, child: cells[1]),
        SizedBox(width: 90, child: cells[2]),
        SizedBox(width: 90, child: cells[3]),
        SizedBox(width: 64, child: cells[4]),
        if (_showObserved) ...[
          SizedBox(width: tokens.spaceSm),
          SizedBox(width: 96, child: cells[5]),
        ],
      ],
    );
  }
}

/// The desktop table header: item, flea/base, change, weight and slots.
class CatalogTableHeader extends StatelessWidget {
  const CatalogTableHeader({super.key, required this.layout});

  final CatalogLayout layout;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    Widget label(
      String text, {
      CrossAxisAlignment align = CrossAxisAlignment.start,
    }) {
      return CatalogTableCell(
        alignment: align,
        child: Text(
          text.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.labelStyle,
        ),
      );
    }

    return Container(
      key: const Key('catalog-table-header'),
      height: 34,
      padding: EdgeInsets.symmetric(horizontal: tokens.spaceMd),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border(
          top: BorderSide(color: tokens.border),
          bottom: BorderSide(color: tokens.border),
        ),
      ),
      child: _CatalogColumns(
        layout: layout,
        cells: <Widget>[
          Padding(padding: EdgeInsets.only(left: 52), child: label('Item')),
          label('Flea'),
          label('24h'),
          label('Weight'),
          label('Slots'),
          if (layout == CatalogLayout.wide) label('Observed'),
        ],
      ),
    );
  }
}

/// One desktop table row driven by an [ItemSummary].
class CatalogTableRow extends StatelessWidget {
  const CatalogTableRow({
    super.key,
    required this.item,
    required this.layout,
    this.index = 0,
    this.onTap,
    this.imageCache,
  });

  final ItemSummary item;
  final CatalogLayout layout;

  /// Optional disk-backed image source; when absent the row keeps its
  /// neutral placeholder and never touches the network or disk.
  final ItemImageCache? imageCache;

  /// Row position, used only to alternate the resting surface.
  final int index;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final change = item.change48hPercent;
    final price = formatRoubles(item.fleaPrice);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('catalog-item-${item.id}'),
        onTap: onTap,
        hoverColor: tokens.accent.withValues(alpha: 0.06),
        child: Container(
          key: ValueKey('catalog-row-surface-${item.id}'),
          height: 72,
          padding: EdgeInsets.symmetric(horizontal: tokens.spaceMd),
          decoration: BoxDecoration(
            color: index.isEven ? tokens.surface : tokens.background,
            border: Border(bottom: BorderSide(color: tokens.borderSoft)),
          ),
          child: _CatalogColumns(
            layout: layout,
            cells: <Widget>[
              _ItemCell(
                key: ValueKey('catalog-row-item-${item.id}'),
                item: item,
                imageCache: imageCache,
              ),
              CatalogTableCell(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      price,
                      key: ValueKey('catalog-row-price-${item.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.dataStyle.copyWith(
                        fontWeight: FontWeight.w600,
                        color: item.fleaPrice == null
                            ? tokens.muted
                            : tokens.value,
                      ),
                    ),
                    SizedBox(height: tokens.spaceXs),
                    Text(
                      'BASE ${formatRoubles(item.basePrice)}',
                      key: ValueKey('catalog-row-base-${item.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.labelStyle.copyWith(color: tokens.dim),
                    ),
                  ],
                ),
              ),
              CatalogTableCell(
                child: Text(
                  formatChange(change),
                  key: ValueKey('catalog-row-change-${item.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.dataStyle.copyWith(
                    color: changeColor(tokens, change),
                  ),
                ),
              ),
              CatalogTableCell(
                child: Text(
                  formatWeight(item.weight) ?? '—',
                  key: ValueKey('catalog-row-weight-${item.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.dataStyle.copyWith(
                    color: item.weight == null ? tokens.muted : tokens.text,
                  ),
                ),
              ),
              CatalogTableCell(
                alignment: CrossAxisAlignment.end,
                child: Text(
                  formatGridSlots(item.width, item.height),
                  key: ValueKey('catalog-row-slots-${item.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.dataStyle.copyWith(
                    color: item.width == null && item.height == null
                        ? tokens.muted
                        : tokens.text,
                  ),
                ),
              ),
              if (layout == CatalogLayout.wide)
                CatalogTableCell(
                  alignment: CrossAxisAlignment.end,
                  child: Text(
                    formatObservationAge(item.priceObservedAt),
                    key: ValueKey('catalog-row-observed-${item.id}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.dataStyle.copyWith(color: tokens.muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The compact, touch-sized catalog row used below 1100 logical pixels.
///
/// The row stays image-free: a neutral placeholder preserves the row height
/// whether or not an image cache ever supplies artwork.
class CatalogItemRow extends StatelessWidget {
  const CatalogItemRow({
    super.key,
    required this.item,
    this.onTap,
    this.imageCache,
  });

  final ItemSummary item;
  final VoidCallback? onTap;

  /// Optional disk-backed image source; see [ItemImageCache].
  final ItemImageCache? imageCache;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final change = item.change48hPercent;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('catalog-item-${item.id}'),
        onTap: onTap,
        hoverColor: tokens.accent.withValues(alpha: 0.06),
        child: Container(
          key: const Key('catalog-compact-row'),
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spaceLg,
            vertical: tokens.spaceMd,
          ),
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border(bottom: BorderSide(color: tokens.borderSoft)),
          ),
          child: Row(
            children: [
              ItemImage(
                cache: imageCache,
                url: item.iconLink,
                size: 40,
                iconSize: 20,
                placeholderKey: ValueKey('catalog-row-icon-${item.id}'),
                imageKey: ValueKey('catalog-row-image-${item.id}'),
              ),
              SizedBox(width: tokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.h2Style.copyWith(
                        fontSize: tokens.bodySize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: tokens.spaceXs),
                    Text(
                      _compactMeta(item).toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.labelStyle,
                    ),
                  ],
                ),
              ),
              SizedBox(width: tokens.spaceMd),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatRoubles(item.fleaPrice),
                    style: tokens.dataStyle.copyWith(
                      fontWeight: FontWeight.w600,
                      color: item.fleaPrice == null
                          ? tokens.muted
                          : tokens.value,
                    ),
                  ),
                  SizedBox(height: tokens.spaceXs),
                  Text(
                    formatChange(change),
                    style: tokens.dataStyle.copyWith(
                      color: changeColor(tokens, change),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _compactMeta(ItemSummary item) {
    final parts = <String>[item.shortName];
    final weight = formatWeight(item.weight);
    if (weight != null) {
      parts.add(weight);
    }
    if (item.fleaEligible == false) {
      parts.add('flea banned');
    }
    return parts.join(' · ');
  }
}

/// The item identity cell: placeholder tile, name and mono meta.
class _ItemCell extends StatelessWidget {
  const _ItemCell({super.key, required this.item, this.imageCache});

  final ItemSummary item;
  final ItemImageCache? imageCache;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final type = item.types.isEmpty ? null : humanizeToken(item.types.first);
    final meta = <String>[
      item.shortName,
      ?type,
      if (item.fleaEligible == false) 'flea banned',
    ].join(' · ');

    return Row(
      children: [
        ItemImage(
          cache: imageCache,
          url: item.iconLink,
          size: 40,
          iconSize: 20,
          placeholderKey: ValueKey('catalog-row-icon-${item.id}'),
          imageKey: ValueKey('catalog-row-image-${item.id}'),
        ),
        SizedBox(width: tokens.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.h2Style.copyWith(
                  fontSize: tokens.bodySize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: tokens.spaceXs),
              Text(
                meta.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.labelStyle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Formats a rouble amount with thousands separators; a missing value is an
/// em dash rather than a zero price.
String formatRoubles(int? value) {
  if (value == null) {
    return '—';
  }
  final digits = value.abs().toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${value < 0 ? '-' : ''}$grouped ₽';
}

/// Formats a weight in kilograms, or `null` when the bundle has no weight.
String? formatWeight(double? value) {
  if (value == null) {
    return null;
  }
  final fixed = value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '$fixed kg';
}

/// Formats a footprint as `W×H`, or an em dash when either side is unknown.
String formatGridSlots(int? width, int? height) {
  if (width == null || height == null) {
    return '—';
  }
  return '$width×$height';
}

/// Formats a signed percentage with one decimal, or an em dash.
String formatChange(double? percent) {
  if (percent == null) {
    return '—';
  }
  final sign = percent > 0 ? '+' : '';
  return '$sign${percent.toStringAsFixed(1)}%';
}

/// The semantic colour for a price change; unknown values stay muted.
Color changeColor(AppTokens tokens, double? percent) {
  if (percent == null) {
    return tokens.muted;
  }
  if (percent > 0) {
    return tokens.success;
  }
  if (percent < 0) {
    return tokens.danger;
  }
  return tokens.muted;
}

/// Formats the age of a price observation as a short relative label.
///
/// The catalog only ever shows a coarse age (`now`, `12m`, `4h`, `3d`); callers
/// that need an exact instant use the freshness contract instead.
String formatObservationAge(DateTime? observedAt, {DateTime? now}) {
  if (observedAt == null) {
    return '—';
  }
  final age = (now ?? DateTime.now()).difference(observedAt);
  if (age.isNegative || age.inMinutes < 1) {
    return 'now';
  }
  if (age.inMinutes < 60) {
    return '${age.inMinutes}m';
  }
  if (age.inHours < 24) {
    return '${age.inHours}h';
  }
  if (age.inDays < 365) {
    return '${age.inDays}d';
  }
  return '${age.inDays ~/ 365}y';
}

/// Turns a bundle token into a display label (`gun` -> `Gun`,
/// `specialSlot` -> `Special slot`).
String humanizeToken(String value) {
  final spaced = value
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (spaced.isEmpty) {
    return value;
  }
  return spaced[0].toUpperCase() + spaced.substring(1);
}
