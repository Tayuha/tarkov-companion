import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import 'quest_list_row.dart' show questStateLabel;

/// One selectable trader or map in the quest filter bar.
///
/// The quest dataset stores upstream identifiers only; display names are
/// localized game strings that the caller already has (or can fall back to the
/// id for). This mirrors `CatalogCategoryOption` in the item catalog.
final class QuestFilterOption {
  const QuestFilterOption({required this.id, required this.label});

  final String id;
  final String label;
}

/// Upper bounds offered by the level filter, as "at or below" levels.
///
/// The data layer supports both an exact `minPlayerLevel` and an inclusive
/// `maxPlayerLevel`; the screen uses the inclusive bound because "show quests I
/// can accept at level 15" is the useful question. Values are spaced so the
/// menu stays keyboard-navigable; a quest above the selected bound is hidden.
const questLevelFilterOptions = <int>[
  5,
  10,
  15,
  20,
  25,
  30,
  35,
  40,
  45,
  50,
  55,
  60,
  70,
  79,
];

/// The trader, map, level and state controls plus the active-filter chips.
///
/// The bar is stateless: the screen owns [filters] and receives one callback per
/// individual change, so removing one chip never disturbs the others.
class QuestFilterBar extends StatelessWidget {
  const QuestFilterBar({
    super.key,
    required this.filters,
    required this.traderOptions,
    required this.mapOptions,
    required this.onTraderSelected,
    required this.onMapSelected,
    required this.onLevelSelected,
    required this.onStateSelected,
    required this.onRemoveText,
    required this.onReset,
  });

  final QuestFilters filters;
  final List<QuestFilterOption> traderOptions;
  final List<QuestFilterOption> mapOptions;
  final ValueChanged<String?> onTraderSelected;
  final ValueChanged<String?> onMapSelected;
  final ValueChanged<int?> onLevelSelected;
  final ValueChanged<QuestProgressState?> onStateSelected;
  final VoidCallback onRemoveText;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final traderId = _nonBlank(filters.traderId);
    final mapId = _nonBlank(filters.mapId);
    final text = _nonBlank(filters.text);
    final traderLabel = _labelFor(traderOptions, traderId);
    final mapLabel = _labelFor(mapOptions, mapId);

    final activeChips = <Widget>[
      if (text != null)
        _ActiveFilterChip(
          key: const Key('quest-filter-chip-text'),
          label: 'Search: "$text"',
          onDeleted: onRemoveText,
        ),
      if (traderLabel != null)
        _ActiveFilterChip(
          key: const Key('quest-filter-chip-trader'),
          label: 'Trader: $traderLabel',
          onDeleted: () => onTraderSelected(null),
        ),
      if (mapLabel != null)
        _ActiveFilterChip(
          key: const Key('quest-filter-chip-map'),
          label: 'Map: $mapLabel',
          onDeleted: () => onMapSelected(null),
        ),
      if (filters.maxPlayerLevel case final level?)
        _ActiveFilterChip(
          key: const Key('quest-filter-chip-level'),
          label: 'Level ≤ $level',
          onDeleted: () => onLevelSelected(null),
        ),
      if (filters.state case final state?)
        _ActiveFilterChip(
          key: const Key('quest-filter-chip-state'),
          label: 'State: ${questStateLabel(state)}',
          onDeleted: () => onStateSelected(null),
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
              width: 220,
              child: DropdownButton<String>(
                key: const Key('quest-trader-filter'),
                value: traderId ?? '',
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: '', child: Text('Any trader')),
                  for (final option in _optionsWithFallback(
                    traderOptions,
                    traderId,
                  ))
                    DropdownMenuItem(
                      value: option.id,
                      child: Text(option.label),
                    ),
                ],
                onChanged: (value) => onTraderSelected(_nonBlank(value)),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButton<String>(
                key: const Key('quest-map-filter'),
                value: mapId ?? '',
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: '', child: Text('Any map')),
                  for (final option in _optionsWithFallback(mapOptions, mapId))
                    DropdownMenuItem(
                      value: option.id,
                      child: Text(option.label),
                    ),
                ],
                onChanged: (value) => onMapSelected(_nonBlank(value)),
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButton<int>(
                key: const Key('quest-level-filter'),
                value: filters.maxPlayerLevel ?? 0,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: 0, child: Text('Any level')),
                  for (final level in _levelValues(filters.maxPlayerLevel))
                    DropdownMenuItem(
                      value: level,
                      child: Text('Level ≤ $level'),
                    ),
                ],
                onChanged: (value) =>
                    onLevelSelected(value == null || value == 0 ? null : value),
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButton<String>(
                key: const Key('quest-state-filter'),
                value: filters.state?.name ?? 'any',
                isExpanded: true,
                items: [
                  const DropdownMenuItem(
                    value: 'any',
                    child: Text('Any state'),
                  ),
                  for (final state in QuestProgressState.values)
                    DropdownMenuItem(
                      value: state.name,
                      child: Text(questStateLabel(state)),
                    ),
                ],
                onChanged: (value) => onStateSelected(_stateFor(value)),
              ),
            ),
            if (filters.isNotEmpty)
              TextButton.icon(
                key: const Key('quest-reset-filters'),
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

  static List<QuestFilterOption> _optionsWithFallback(
    List<QuestFilterOption> options,
    String? activeId,
  ) {
    if (activeId == null || options.any((option) => option.id == activeId)) {
      return options;
    }
    return [...options, QuestFilterOption(id: activeId, label: activeId)];
  }

  static List<int> _levelValues(int? activeLevel) {
    final values = <int>{...questLevelFilterOptions};
    if (activeLevel != null) {
      values.add(activeLevel);
    }
    return values.toList()..sort();
  }

  static String? _labelFor(List<QuestFilterOption> options, String? id) {
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

  static QuestProgressState? _stateFor(String? value) {
    if (value == null || value == 'any') {
      return null;
    }
    for (final state in QuestProgressState.values) {
      if (state.name == value) {
        return state;
      }
    }
    return null;
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

String? _nonBlank(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}
