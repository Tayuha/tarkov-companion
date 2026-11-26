import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

/// One selectable category in the catalog filter bar.
///
/// The item catalog only stores category ids and the data package does not own
/// a category taxonomy table, so the screen takes the labels from the caller.
/// The defaults below are the well-known top-level Tarkov categories; the app
/// shell can replace them once a full taxonomy is available.
final class CatalogCategoryOption {
  const CatalogCategoryOption({
    required this.id,
    required this.label,
    this.kind = CatalogCategoryKind.item,
  });

  final String id;
  final String label;
  final CatalogCategoryKind kind;
}

/// Starter category set used when the caller passes no [CatalogCategoryOption]s.
const defaultCatalogCategories = <CatalogCategoryOption>[
  CatalogCategoryOption(id: '5422acb9af1c889c16000029', label: 'Weapons'),
  CatalogCategoryOption(id: '5448fe124bdc2da5018b4567', label: 'Weapon mods'),
  CatalogCategoryOption(id: '543be5cb4bdc2deb348b4568', label: 'Ammo'),
  CatalogCategoryOption(id: '543be5664bdc2dd4348b4569', label: 'Meds'),
  CatalogCategoryOption(id: '5448e5284bdc2dcb718b4567', label: 'Armor'),
  CatalogCategoryOption(id: '566168634bdc2d144c8b456c', label: 'Containers'),
];

/// Type tags that can be used as a filter when the caller passes none.
///
/// Values are the bundle `types[]` vocabulary (`gun`, `ammo`, `mods`, ...),
/// not display names.
const defaultCatalogTypes = <String>[
  'gun',
  'ammo',
  'mods',
  'armor',
  'rig',
  'backpack',
  'helmet',
  'headphones',
  'glasses',
  'meds',
  'provisions',
  'keys',
  'grenade',
  'barter',
  'specialSlot',
];

/// Display label for a bundle type tag.
String catalogTypeLabel(String type) {
  if (type == 'specialSlot') {
    return 'Special slot';
  }
  if (type.isEmpty) {
    return type;
  }
  return '${type[0].toUpperCase()}${type.substring(1)}';
}

/// The category, type and flea controls plus the active-filter chips.
///
/// The bar is stateless: the screen owns [filters] and receives one callback
/// per individual change, so clearing one chip never disturbs the others.
class CatalogFilterBar extends StatelessWidget {
  const CatalogFilterBar({
    super.key,
    required this.filters,
    required this.categories,
    required this.types,
    required this.onCategorySelected,
    required this.onTypeSelected,
    required this.onFleaEligibleSelected,
    required this.onRemoveText,
    required this.onReset,
  });

  final CatalogFilters filters;
  final List<CatalogCategoryOption> categories;
  final List<String> types;
  final ValueChanged<String?> onCategorySelected;
  final ValueChanged<String?> onTypeSelected;
  final ValueChanged<bool?> onFleaEligibleSelected;
  final VoidCallback onRemoveText;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final categoryLabel = _categoryLabel(filters);
    final activeChips = <Widget>[
      if (_text(filters) case final text?)
        _ActiveFilterChip(
          key: const Key('catalog-filter-chip-text'),
          label: 'Search: "$text"',
          onDeleted: onRemoveText,
        ),
      if (categoryLabel != null)
        _ActiveFilterChip(
          key: const Key('catalog-filter-chip-category'),
          label: 'Category: $categoryLabel',
          onDeleted: () => onCategorySelected(null),
        ),
      if (_type(filters) case final type?)
        _ActiveFilterChip(
          key: const Key('catalog-filter-chip-type'),
          label: 'Type: ${catalogTypeLabel(type)}',
          onDeleted: () => onTypeSelected(null),
        ),
      if (filters.fleaEligible case final eligible?)
        _ActiveFilterChip(
          key: const Key('catalog-filter-chip-flea'),
          label: eligible ? 'Flea eligible' : 'Flea banned',
          onDeleted: () => onFleaEligibleSelected(null),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 230,
              child: DropdownButton<String>(
                key: const Key('catalog-category-filter'),
                value: _categoryId(filters) ?? '',
                isExpanded: true,
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Any category'),
                  ),
                  for (final category in categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(category.label),
                    ),
                ],
                onChanged: (value) => onCategorySelected(
                  value == null || value.isEmpty ? null : value,
                ),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButton<String>(
                key: const Key('catalog-type-filter'),
                value: _type(filters) ?? '',
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: '', child: Text('Any type')),
                  for (final type in types)
                    DropdownMenuItem(
                      value: type,
                      child: Text(catalogTypeLabel(type)),
                    ),
                ],
                onChanged: (value) => onTypeSelected(
                  value == null || value.isEmpty ? null : value,
                ),
              ),
            ),
            FilterChip(
              key: const Key('catalog-flea-filter'),
              label: const Text('Flea eligible'),
              selected: filters.fleaEligible == true,
              onSelected: (selected) =>
                  onFleaEligibleSelected(selected ? true : null),
            ),
            if (filters.isNotEmpty)
              TextButton.icon(
                key: const Key('catalog-reset-filters'),
                onPressed: onReset,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text('Reset'),
              ),
          ],
        ),
        if (activeChips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, runSpacing: 4, children: activeChips),
          ),
      ],
    );
  }

  static String? _text(CatalogFilters filters) {
    final text = filters.text?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _categoryId(CatalogFilters filters) {
    final id = filters.categoryId?.trim();
    return id == null || id.isEmpty ? null : id;
  }

  static String? _type(CatalogFilters filters) {
    final type = filters.type?.trim();
    return type == null || type.isEmpty ? null : type;
  }

  String? _categoryLabel(CatalogFilters filters) {
    final id = _categoryId(filters);
    if (id == null) {
      return null;
    }
    for (final category in categories) {
      if (category.id == id) {
        return category.label;
      }
    }
    return id;
  }
}

class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({
    super.key,
    required this.label,
    required this.onDeleted,
  });

  final String label;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label),
      onDeleted: onDeleted,
      deleteIcon: const Icon(Icons.close, size: 16),
      visualDensity: VisualDensity.compact,
    );
  }
}
