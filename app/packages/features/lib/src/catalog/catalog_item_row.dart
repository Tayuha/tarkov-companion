import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

/// One virtualized catalog row.
///
/// The row is deliberately image-free: task 5.6 owns the disk-backed image
/// cache, so this widget renders a neutral placeholder at a fixed size instead.
/// Keeping the slot fixed means the list height is stable whether or not an
/// image ever loads, and the placeholder is not an error state.
class CatalogItemRow extends StatelessWidget {
  const CatalogItemRow({super.key, required this.item, this.onTap});

  final ItemSummary item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      key: ValueKey('catalog-item-${item.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _PlaceholderIcon(colorScheme: colorScheme),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _secondaryLabel(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatRoubles(item.fleaPrice),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'base ${formatRoubles(item.basePrice)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _secondaryLabel(ItemSummary item) {
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

/// A neutral item icon slot.
///
/// This is intentionally not an image widget: no network or disk access happens
/// here, and a missing image never changes the row's height.
class _PlaceholderIcon extends StatelessWidget {
  const _PlaceholderIcon({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.inventory_2_outlined,
        size: 24,
        color: colorScheme.onSurfaceVariant,
      ),
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
