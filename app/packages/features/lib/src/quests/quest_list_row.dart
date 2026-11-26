import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

/// Human-readable label for a recorded quest state.
String questStateLabel(QuestProgressState state) => switch (state) {
  QuestProgressState.notStarted => 'Not started',
  QuestProgressState.inProgress => 'In progress',
  QuestProgressState.completed => 'Completed',
  QuestProgressState.failed => 'Failed',
};

/// A plain-Material badge for one recorded quest state.
///
/// The four states get distinct background/foreground pairs rather than a
/// single tinted chip, so "not started" never looks like "in progress" and a
/// failed quest is unmistakable. The badge is presentation only: the state
/// comes from the profile-scoped query, never from local derivation (that is
/// the availability engine, task 6.3).
class QuestStateBadge extends StatelessWidget {
  const QuestStateBadge({super.key, required this.state});

  final QuestProgressState state;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (state) {
      QuestProgressState.notStarted => (
        Colors.blueGrey.shade100,
        Colors.blueGrey.shade900,
      ),
      QuestProgressState.inProgress => (
        Colors.orange.shade100,
        Colors.orange.shade900,
      ),
      QuestProgressState.completed => (
        Colors.green.shade100,
        Colors.green.shade900,
      ),
      QuestProgressState.failed => (Colors.red.shade100, Colors.red.shade900),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        questStateLabel(state),
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// One virtualized quest row: name, trader, required level, map and state.
///
/// The row is deliberately small and fixed-height. It does not decide
/// availability, open a detail view, or fetch anything; the screen reports a
/// tap through its callback.
class QuestListRow extends StatelessWidget {
  const QuestListRow({
    super.key,
    required this.quest,
    this.traderLabel,
    this.mapLabel,
    this.onTap,
  });

  final QuestSummary quest;

  /// Display name for [QuestSummary.traderId], when the caller supplied one.
  final String? traderLabel;

  /// Display name for [QuestSummary.mapId], when the caller supplied one.
  final String? mapLabel;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      key: ValueKey('quest-row-${quest.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    quest.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _secondaryLabel(quest, traderLabel, mapLabel),
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
            QuestStateBadge(
              key: ValueKey('quest-state-${quest.id}'),
              state: quest.progressState,
            ),
          ],
        ),
      ),
    );
  }

  static String _secondaryLabel(
    QuestSummary quest,
    String? traderLabel,
    String? mapLabel,
  ) {
    final parts = <String>[
      ?traderLabel,
      if (quest.minPlayerLevel != null) 'Level ${quest.minPlayerLevel}',
      ?mapLabel,
    ];
    return parts.isEmpty
        ? 'No trader, level or map recorded'
        : parts.join(' · ');
  }
}
