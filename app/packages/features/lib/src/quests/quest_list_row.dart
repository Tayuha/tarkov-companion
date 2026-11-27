import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import '../theme/app_primitives.dart';
import '../theme/app_tokens.dart';

/// The responsive layouts of the quest catalog.
enum QuestLayout {
  /// Touch-sized card rows without a header, below 1100 logical pixels.
  compact,

  /// Quest, trader, map, status and progress columns.
  standard,

  /// The standard table plus the level requirement and a wider quest cell.
  wide,
}

/// Picks the quest layout for a content width.
///
/// `wide` starts at the 1600 px content cap, so only a 1920-class window (or
/// wider) gets the extra `Level` column. Windows below 1100 keep the compact
/// card list.
QuestLayout questLayoutForWidth(double width) {
  if (width >= 1600) {
    return QuestLayout.wide;
  }
  if (width >= 1100) {
    return QuestLayout.standard;
  }
  return QuestLayout.compact;
}

/// Human-readable label for a recorded quest state.
String questStateLabel(QuestProgressState state) => switch (state) {
  QuestProgressState.notStarted => 'Not started',
  QuestProgressState.inProgress => 'In progress',
  QuestProgressState.completed => 'Completed',
  QuestProgressState.failed => 'Failed',
};

/// The design-system status for a recorded progress state.
///
/// A quest with no recorded state is not yet available, so it uses the locked
/// treatment; the badge label still says "Not started".
AppStatus questStateAppStatus(QuestProgressState state) => switch (state) {
  QuestProgressState.notStarted => AppStatus.locked,
  QuestProgressState.inProgress => AppStatus.inProgress,
  QuestProgressState.completed => AppStatus.completed,
  QuestProgressState.failed => AppStatus.failed,
};

/// The design-system status for a derived availability value.
AppStatus questAvailabilityAppStatus(QuestAvailability availability) =>
    switch (availability) {
      QuestAvailability.locked => AppStatus.locked,
      QuestAvailability.available => AppStatus.available,
      QuestAvailability.inProgress => AppStatus.inProgress,
      QuestAvailability.completed => AppStatus.completed,
    };

/// The status shown in the quest list.
///
/// With a profile, the derived availability is authoritative and adds the
/// "available" and "locked" states the catalog query cannot express. A failed
/// quest keeps the failed badge even though its availability is locked. Without
/// a profile there is no derived status, so the recorded state is used.
AppStatus questListAppStatus(QuestSummary quest, QuestStatus? status) {
  if (status == null) {
    return questStateAppStatus(quest.progressState);
  }
  if (status.recordedState == QuestProgressState.failed) {
    return AppStatus.failed;
  }
  return questAvailabilityAppStatus(status.availability);
}

/// The quest-list badge for one recorded progress state.
class QuestStateBadge extends StatelessWidget {
  const QuestStateBadge({super.key, required this.state});

  final QuestProgressState state;

  @override
  Widget build(BuildContext context) {
    return AppStatusBadge(
      status: questStateAppStatus(state),
      label: questStateLabel(state),
    );
  }
}

/// The quest-list badge for a derived availability value.
class QuestAvailabilityBadge extends StatelessWidget {
  const QuestAvailabilityBadge({super.key, required this.availability});

  final QuestAvailability availability;

  @override
  Widget build(BuildContext context) {
    return AppStatusBadge(status: questAvailabilityAppStatus(availability));
  }
}

/// Required objective progress as a fraction, or `null` when there is nothing
/// countable to show. Optional objectives never appear in the denominator.
({int done, int total})? questProgressFraction(QuestStatus? status) {
  if (status == null) {
    return null;
  }
  final required = [
    for (final objective in status.objectives)
      if (!objective.optional) objective,
  ];
  if (required.isEmpty) {
    return null;
  }
  return (
    done: required.where((objective) => objective.satisfied).length,
    total: required.length,
  );
}

/// Formats a progress fraction for the list (`2 / 3`), or an em dash.
String formatQuestProgress(QuestStatus? status) {
  final fraction = questProgressFraction(status);
  if (fraction == null) {
    return '—';
  }
  return '${fraction.done} / ${fraction.total}';
}

/// One two-line cell for the desktop table header and its data rows.
class QuestTableCell extends StatelessWidget {
  const QuestTableCell({
    super.key,
    required this.child,
    this.alignment = CrossAxisAlignment.start,
  });

  final Widget child;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [child],
    );
  }
}

/// The column frame shared by [QuestTableHeader] and [QuestTableRow].
///
/// One widget for both means the header and the cells can never drift apart
/// when a column is added or widened.
class _QuestColumns extends StatelessWidget {
  const _QuestColumns({required this.layout, required this.cells});

  final QuestLayout layout;

  /// Quest, trader, map, status, progress and (wide only) level.
  final List<Widget> cells;

  bool get _showLevel => layout == QuestLayout.wide;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final questFlex = layout == QuestLayout.wide ? 5 : 3;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: questFlex, child: cells[0]),
        SizedBox(width: tokens.spaceSm),
        SizedBox(width: 150, child: cells[1]),
        SizedBox(width: 150, child: cells[2]),
        SizedBox(width: 120, child: cells[3]),
        SizedBox(width: 84, child: cells[4]),
        if (_showLevel) ...[
          SizedBox(width: tokens.spaceSm),
          SizedBox(width: 64, child: cells[5]),
        ],
      ],
    );
  }
}

/// The desktop table header: quest, trader, map, status and progress.
class QuestTableHeader extends StatelessWidget {
  const QuestTableHeader({super.key, required this.layout});

  final QuestLayout layout;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    Widget label(
      String text, {
      CrossAxisAlignment align = CrossAxisAlignment.start,
    }) {
      return QuestTableCell(
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
      key: const Key('quest-table-header'),
      height: 34,
      padding: EdgeInsets.symmetric(horizontal: tokens.spaceMd),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border(
          top: BorderSide(color: tokens.border),
          bottom: BorderSide(color: tokens.border),
        ),
      ),
      child: _QuestColumns(
        layout: layout,
        cells: <Widget>[
          label('Quest'),
          label('Trader'),
          label('Map'),
          label('Status'),
          label('Progress', align: CrossAxisAlignment.end),
          if (layout == QuestLayout.wide)
            label('Level', align: CrossAxisAlignment.end),
        ],
      ),
    );
  }
}

/// One desktop table row driven by a [QuestSummary] and its derived status.
class QuestTableRow extends StatelessWidget {
  const QuestTableRow({
    super.key,
    required this.quest,
    required this.layout,
    required this.status,
    this.traderLabel,
    this.mapLabel,
    this.index = 0,
    this.onTap,
  });

  final QuestSummary quest;
  final QuestLayout layout;
  final QuestStatus? status;

  /// Display name for [QuestSummary.traderId], when the caller supplied one.
  final String? traderLabel;

  /// Display name for [QuestSummary.mapId], when the caller supplied one.
  final String? mapLabel;

  /// Row position, used only to alternate the resting surface.
  final int index;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final appStatus = questListAppStatus(quest, status);
    final statusLabel = status == null
        ? questStateLabel(quest.progressState)
        : null;
    final progress = formatQuestProgress(status);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('quest-row-${quest.id}'),
        onTap: onTap,
        hoverColor: tokens.accent.withValues(alpha: 0.06),
        child: Container(
          key: ValueKey('quest-row-surface-${quest.id}'),
          height: 72,
          padding: EdgeInsets.symmetric(horizontal: tokens.spaceMd),
          decoration: BoxDecoration(
            color: index.isEven ? tokens.surface : tokens.background,
            border: Border(bottom: BorderSide(color: tokens.borderSoft)),
          ),
          child: _QuestColumns(
            layout: layout,
            cells: <Widget>[
              _QuestCell(
                key: ValueKey('quest-row-quest-${quest.id}'),
                quest: quest,
              ),
              QuestTableCell(
                child: Text(
                  traderLabel ?? '—',
                  key: ValueKey('quest-row-trader-${quest.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.bodyStyle.copyWith(
                    color: traderLabel == null ? tokens.muted : tokens.text,
                  ),
                ),
              ),
              QuestTableCell(
                child: Text(
                  mapLabel ?? '—',
                  key: ValueKey('quest-row-map-${quest.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.bodyStyle.copyWith(
                    color: mapLabel == null ? tokens.muted : tokens.text,
                  ),
                ),
              ),
              QuestTableCell(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppStatusBadge(
                    key: ValueKey('quest-state-${quest.id}'),
                    status: appStatus,
                    label: statusLabel,
                  ),
                ),
              ),
              QuestTableCell(
                alignment: CrossAxisAlignment.end,
                child: Text(
                  progress,
                  key: ValueKey('quest-row-progress-${quest.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.dataStyle.copyWith(
                    color: progress == '—' ? tokens.muted : tokens.text,
                  ),
                ),
              ),
              if (layout == QuestLayout.wide)
                QuestTableCell(
                  alignment: CrossAxisAlignment.end,
                  child: Text(
                    quest.minPlayerLevel?.toString() ?? '—',
                    key: ValueKey('quest-row-level-${quest.id}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.dataStyle.copyWith(
                      color: quest.minPlayerLevel == null
                          ? tokens.muted
                          : tokens.text,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The quest identity cell: name and a mono meta line.
class _QuestCell extends StatelessWidget {
  const _QuestCell({super.key, required this.quest});

  final QuestSummary quest;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final meta = <String>[..._metaParts(quest)].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          quest.name,
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
          style: tokens.labelStyle.copyWith(color: tokens.muted),
        ),
      ],
    );
  }

  static List<String> _metaParts(QuestSummary quest) {
    return <String>[
      if (quest.experience != null) '${quest.experience} xp',
      if (quest.kappaRequired) 'kappa',
    ];
  }
}

/// The compact, touch-sized quest row used below 1100 logical pixels.
///
/// The row stays a card: name and trader/level/map meta on the left, status and
/// progress on the right. It is the only row that adds a list item in the
/// compact layout.
class QuestListRow extends StatelessWidget {
  const QuestListRow({
    super.key,
    required this.quest,
    this.status,
    this.traderLabel,
    this.mapLabel,
    this.onTap,
  });

  final QuestSummary quest;

  /// Derived status for the active profile, when one was supplied.
  final QuestStatus? status;

  /// Display name for [QuestSummary.traderId], when the caller supplied one.
  final String? traderLabel;

  /// Display name for [QuestSummary.mapId], when the caller supplied one.
  final String? mapLabel;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final appStatus = questListAppStatus(quest, status);
    final statusLabel = status == null
        ? questStateLabel(quest.progressState)
        : null;
    final progress = formatQuestProgress(status);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('quest-row-${quest.id}'),
        onTap: onTap,
        hoverColor: tokens.accent.withValues(alpha: 0.06),
        child: Container(
          key: const Key('quest-compact-row'),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      quest.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.h2Style.copyWith(
                        fontSize: tokens.bodySize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: tokens.spaceXs),
                    Text(
                      _secondaryLabel(quest, traderLabel, mapLabel),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.labelStyle.copyWith(color: tokens.muted),
                    ),
                  ],
                ),
              ),
              SizedBox(width: tokens.spaceMd),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppStatusBadge(
                    key: ValueKey('quest-state-${quest.id}'),
                    status: appStatus,
                    label: statusLabel,
                  ),
                  SizedBox(height: tokens.spaceXs),
                  Text(
                    progress,
                    key: ValueKey('quest-row-progress-${quest.id}'),
                    style: tokens.dataStyle.copyWith(
                      color: progress == '—' ? tokens.dim : tokens.muted,
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
