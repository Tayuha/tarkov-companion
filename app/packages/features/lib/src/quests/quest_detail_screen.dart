import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import '../catalog/item_detail_screen.dart';
import '../section_header.dart';
import 'quest_list_row.dart' show QuestStateBadge, questStateLabel;

/// The full, interactive view of one quest.
///
/// The screen combines [QuestRepository.detail] (the catalog record) with
/// [QuestRepository.statuses] (availability and the active profile's recorded
/// progress) and renders:
///
/// * a header with the quest name, recorded state badge, computed availability,
///   trader and map labels, level, experience, Kappa flag and wiki link;
/// * every objective with the profile's count and increment/decrement controls;
/// * the requirement list and the exact structured reasons the availability
///   engine reports, including advisor-only trader loyalty requirements;
/// * reward items, turn-in/required items and quest unlocks, each item opening
///   [ItemDetailScreen] and each quest pushing another detail screen;
/// * status controls for in progress, completed, failed and revert.
///
/// Marking a quest completed while required objectives are unsatisfied is the
/// explicit manual override: the screen asks for confirmation and the dialog
/// says that objective counts are not changed. That is also the only path that
/// sets [QuestStatus.manuallyCompleted] in the data layer.
///
/// The screen is presentation-only and is not wired into the app shell: it
/// receives its repositories and an optional [profileId]. With no profile the
/// catalog detail still renders, but no progress is read or written.
class QuestDetailScreen extends StatefulWidget {
  const QuestDetailScreen({
    super.key,
    required this.repository,
    required this.catalog,
    required this.questId,
    this.profileId,
    this.onBack,
  });

  final QuestRepository repository;
  final CatalogRepository catalog;

  /// Upstream quest id to resolve.
  final String questId;

  /// The profile whose progress and availability are shown, or `null` for a
  /// read-only catalog view with no progress.
  final String? profileId;

  /// Called by the not-found and orphaned back actions. When omitted, the
  /// screen pops the current route.
  final VoidCallback? onBack;

  @override
  State<QuestDetailScreen> createState() => _QuestDetailScreenState();
}

class _QuestDetailScreenState extends State<QuestDetailScreen> {
  QuestDetail? _detail;
  QuestStatus? _status;
  Map<String, QuestStatus> _statusesById = const {};
  Map<String, String> _itemNames = const {};
  OrphanedQuestProgress? _orphan;
  String? _traderLabel;
  String? _mapLabel;

  Object? _error;
  Object? _actionError;
  bool _loading = true;
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(QuestDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.questId != widget.questId ||
        oldWidget.repository != widget.repository ||
        oldWidget.catalog != widget.catalog ||
        oldWidget.profileId != widget.profileId) {
      _load();
    }
  }

  Future<void> _load({bool showLoading = true}) async {
    final generation = ++_generation;
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final detail = await widget.repository.detail(widget.questId);
      QuestStatus? status;
      var statusesById = <String, QuestStatus>{};
      var itemNames = <String, String>{};
      String? traderLabel;
      String? mapLabel;
      OrphanedQuestProgress? orphan;

      if (detail != null) {
        traderLabel = await widget.repository.traderName(detail.traderId);
        mapLabel = await widget.repository.mapName(detail.mapId);
        itemNames = await _loadItemNames(detail);
        final profileId = widget.profileId;
        if (profileId != null) {
          final statuses = await widget.repository.statuses(profileId);
          statusesById = {for (final entry in statuses) entry.id: entry};
          status = statusesById[widget.questId];
        }
      } else {
        final profileId = widget.profileId;
        if (profileId != null) {
          final orphans = await widget.repository.orphanedProgress(profileId);
          for (final entry in orphans) {
            if (entry.questId == widget.questId) {
              orphan = entry;
              break;
            }
          }
        }
      }

      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _detail = detail;
        _status = status;
        _statusesById = statusesById;
        _itemNames = itemNames;
        _orphan = orphan;
        _traderLabel = traderLabel;
        _mapLabel = mapLabel;
        _loading = false;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<Map<String, String>> _loadItemNames(QuestDetail detail) async {
    final ids = <String>{
      ...detail.rewardItemIds,
      ...detail.turnInItemIds,
      ...detail.objectiveItemIds,
      ...detail.unlockItemIds,
      for (final offer in detail.rewards.offerUnlocks) ?offer.itemId,
      for (final craft in detail.rewards.craftUnlocks) ?craft.itemId,
    }.toList();

    final names = <String, String>{};
    for (final id in ids) {
      names[id] = await _itemName(id);
    }
    return names;
  }

  Future<String> _itemName(String itemId) async {
    try {
      final item = await widget.catalog.itemDetail(itemId);
      return item?.name ?? itemId;
    } on Object catch (_) {
      return itemId;
    }
  }

  /// Re-reads only the profile-derived part after a progress write.
  Future<void> _refreshStatus() async {
    final profileId = widget.profileId;
    if (profileId == null) {
      return;
    }
    final generation = ++_generation;
    final statuses = await widget.repository.statuses(profileId);
    if (!mounted || generation != _generation) {
      return;
    }
    final statusesById = {for (final entry in statuses) entry.id: entry};
    setState(() {
      _statusesById = statusesById;
      _status = statusesById[widget.questId];
    });
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await action();
      await _refreshStatus();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _actionError = error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _changeState(QuestProgressState state) async {
    final profileId = widget.profileId;
    if (profileId == null) {
      return;
    }

    if (state == QuestProgressState.completed) {
      final status = _status;
      if (status != null && !status.objectivesSatisfied) {
        final confirmed = await _confirmManualOverride();
        if (confirmed != true) {
          return;
        }
      }
    }

    await _perform(
      () => widget.repository.setQuestState(profileId, widget.questId, state),
    );
  }

  Future<bool?> _confirmManualOverride() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('quest-override-dialog'),
        title: const Text('Complete without all objectives?'),
        content: const Text(
          'Some required objectives are not satisfied. Marking this quest '
          'completed is a manual override. Objective counts are not changed: '
          'the counts you recorded stay exactly as they are.',
        ),
        actions: [
          TextButton(
            key: const Key('quest-override-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('quest-override-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Complete anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _revert() async {
    final profileId = widget.profileId;
    if (profileId == null) {
      return;
    }
    final hasCounts =
        _status?.objectives.any((entry) => entry.count > 0) ?? false;
    final target = hasCounts
        ? QuestProgressState.inProgress
        : QuestProgressState.notStarted;
    await _perform(
      () => widget.repository.setQuestState(profileId, widget.questId, target),
    );
  }

  Future<void> _setObjectiveCount(
    QuestObjectiveProgress progress,
    int count,
  ) async {
    final profileId = widget.profileId;
    if (profileId == null) {
      return;
    }
    final required = progress.requiredCount;
    final clamped = count < 0
        ? 0
        : count > required
        ? required
        : count;
    await _perform(
      () => widget.repository.setObjectiveCount(
        profileId,
        widget.questId,
        progress.objective.id,
        clamped,
      ),
    );
  }

  void _openItem(String itemId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ItemDetailScreen(repository: widget.catalog, itemId: itemId),
      ),
    );
  }

  void _openQuest(String questId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuestDetailScreen(
          repository: widget.repository,
          catalog: widget.catalog,
          questId: questId,
          profileId: widget.profileId,
        ),
      ),
    );
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
      key: const Key('quest-detail-screen'),
      appBar: AppBar(
        leading: widget.onBack == null
            ? null
            : IconButton(
                key: const Key('quest-detail-app-back'),
                tooltip: 'Back',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
        title: Text(detail?.name ?? 'Quest detail'),
      ),
      body: SafeArea(child: _buildBody(detail)),
    );
  }

  Widget _buildBody(QuestDetail? detail) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(key: Key('quest-detail-loading')),
      );
    }
    final error = _error;
    if (error != null) {
      return _ErrorState(error: error, onRetry: _load);
    }
    if (detail != null) {
      return _DetailBody(
        detail: detail,
        status: _status,
        statusesById: _statusesById,
        itemNames: _itemNames,
        traderLabel: _traderLabel,
        mapLabel: _mapLabel,
        profileId: widget.profileId,
        busy: _busy,
        actionError: _actionError,
        onItemTap: _openItem,
        onQuestTap: _openQuest,
        onStateSelected: _changeState,
        onRevert: _revert,
        onObjectiveCount: _setObjectiveCount,
      );
    }
    final orphan = _orphan;
    if (orphan != null) {
      return _OrphanState(orphan: orphan, onBack: _back);
    }
    return _NotFoundState(questId: widget.questId, onBack: _back);
  }
}

// ---------------------------------------------------------------------------
// Detail body
// ---------------------------------------------------------------------------

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.detail,
    required this.status,
    required this.statusesById,
    required this.itemNames,
    required this.traderLabel,
    required this.mapLabel,
    required this.profileId,
    required this.busy,
    required this.actionError,
    required this.onItemTap,
    required this.onQuestTap,
    required this.onStateSelected,
    required this.onRevert,
    required this.onObjectiveCount,
  });

  final QuestDetail detail;
  final QuestStatus? status;
  final Map<String, QuestStatus> statusesById;
  final Map<String, String> itemNames;
  final String? traderLabel;
  final String? mapLabel;
  final String? profileId;
  final bool busy;
  final Object? actionError;
  final ValueChanged<String> onItemTap;
  final ValueChanged<String> onQuestTap;
  final ValueChanged<QuestProgressState> onStateSelected;
  final VoidCallback onRevert;
  final void Function(QuestObjectiveProgress progress, int count)
  onObjectiveCount;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('quest-detail-scroll'),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                detail: detail,
                status: status,
                traderLabel: traderLabel,
                mapLabel: mapLabel,
                hasProfile: profileId != null,
              ),
              const SizedBox(height: 24),
              _ObjectivesSection(
                detail: detail,
                status: status,
                hasProfile: profileId != null,
                busy: busy,
                itemNames: itemNames,
                onChanged: onObjectiveCount,
              ),
              const SizedBox(height: 24),
              _RequirementsSection(
                detail: detail,
                status: status,
                statusesById: statusesById,
                traderLabel: traderLabel,
                hasProfile: profileId != null,
                onQuestTap: onQuestTap,
              ),
              const SizedBox(height: 24),
              _RewardsSection(
                detail: detail,
                itemNames: itemNames,
                traderLabel: traderLabel,
                onItemTap: onItemTap,
              ),
              const SizedBox(height: 24),
              _ItemsSection(
                detail: detail,
                itemNames: itemNames,
                onItemTap: onItemTap,
              ),
              const SizedBox(height: 24),
              _UnlocksSection(
                detail: detail,
                statusesById: statusesById,
                onQuestTap: onQuestTap,
              ),
              const SizedBox(height: 24),
              _StatusSection(
                status: status,
                profileId: profileId,
                busy: busy,
                actionError: actionError,
                onStateSelected: onStateSelected,
                onRevert: onRevert,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.detail,
    required this.status,
    required this.traderLabel,
    required this.mapLabel,
    required this.hasProfile,
  });

  final QuestDetail detail;
  final QuestStatus? status;
  final String? traderLabel;
  final String? mapLabel;
  final bool hasProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final recordedState = status?.recordedState;
    final availability = status?.availability;
    final wikiLink = detail.wikiLink;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              detail.name,
              key: const Key('quest-detail-name'),
              style: theme.textTheme.headlineSmall,
            ),
            if (hasProfile && recordedState != null)
              QuestStateBadge(
                key: const Key('quest-detail-state'),
                state: recordedState,
              ),
            if (availability != null)
              _AvailabilityChip(
                key: const Key('quest-detail-availability'),
                availability: availability,
              ),
            if (!hasProfile)
              const Chip(
                key: Key('quest-detail-no-profile'),
                label: Text('No profile selected'),
                visualDensity: VisualDensity.compact,
              ),
            if (status?.manuallyCompleted ?? false)
              const Chip(
                key: Key('quest-detail-manual-override'),
                label: Text('Manual override'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        if (detail.description != null) ...[
          const SizedBox(height: 8),
          Text(
            detail.description!,
            key: const Key('quest-detail-description'),
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          key: const Key('quest-detail-metadata'),
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetadataChip(
              key: const Key('quest-detail-trader'),
              icon: Icons.storefront_outlined,
              label: traderLabel == null
                  ? 'No trader recorded'
                  : 'Trader: $traderLabel',
            ),
            _MetadataChip(
              key: const Key('quest-detail-map'),
              icon: Icons.map_outlined,
              label: mapLabel == null ? 'No map recorded' : 'Map: $mapLabel',
            ),
            _MetadataChip(
              key: const Key('quest-detail-level'),
              icon: Icons.person_outline,
              label: detail.minPlayerLevel == null
                  ? 'No level requirement'
                  : 'Level ${detail.minPlayerLevel}',
            ),
            _MetadataChip(
              key: const Key('quest-detail-experience'),
              icon: Icons.stars_outlined,
              label: detail.experience == null
                  ? 'No XP recorded'
                  : '${detail.experience} XP',
            ),
            _MetadataChip(
              key: const Key('quest-detail-kappa'),
              icon: Icons.workspace_premium_outlined,
              label: detail.kappaRequired
                  ? 'Kappa required'
                  : 'Not Kappa required',
            ),
            if (detail.restartable)
              const _MetadataChip(icon: Icons.refresh, label: 'Restartable'),
          ],
        ),
        if (wikiLink != null) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  'Wiki',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  wikiLink,
                  key: const Key('quest-detail-wiki-link'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _AvailabilityChip extends StatelessWidget {
  const _AvailabilityChip({super.key, required this.availability});

  final QuestAvailability availability;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground) = switch (availability) {
      QuestAvailability.locked => (
        'Locked',
        Colors.red.shade100,
        Colors.red.shade900,
      ),
      QuestAvailability.available => (
        'Available',
        Colors.teal.shade100,
        Colors.teal.shade900,
      ),
      QuestAvailability.inProgress => (
        'In progress',
        Colors.orange.shade100,
        Colors.orange.shade900,
      ),
      QuestAvailability.completed => (
        'Completed',
        Colors.green.shade100,
        Colors.green.shade900,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Objectives
// ---------------------------------------------------------------------------

class _ObjectivesSection extends StatelessWidget {
  const _ObjectivesSection({
    required this.detail,
    required this.status,
    required this.hasProfile,
    required this.busy,
    required this.itemNames,
    required this.onChanged,
  });

  final QuestDetail detail;
  final QuestStatus? status;
  final bool hasProfile;
  final bool busy;
  final Map<String, String> itemNames;
  final void Function(QuestObjectiveProgress progress, int count) onChanged;

  List<QuestObjectiveProgress> get _progress {
    final current = status;
    if (current != null) {
      return current.objectives;
    }
    return [
      for (final objective in detail.objectives)
        QuestObjectiveProgress(
          objective: objective,
          count: 0,
          satisfied: objective.requiredCount == 0,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final required = progress.where((entry) => !entry.optional).length;
    final satisfied = progress
        .where((entry) => !entry.optional && entry.satisfied)
        .length;
    final current = status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Objectives',
          subtitle: current == null
              ? 'Counts are recorded per profile.'
              : current.objectivesSatisfied
              ? 'All required objectives are satisfied.'
              : '$satisfied of $required required objectives satisfied.',
        ),
        const SizedBox(height: 8),
        if (progress.isEmpty)
          const Text('This quest has no objectives in the dataset.')
        else
          for (final entry in progress)
            _ObjectiveRow(
              key: ValueKey('quest-objective-${entry.objective.id}'),
              progress: entry,
              itemNames: itemNames,
              enabled: hasProfile && !busy,
              onChanged: (count) => onChanged(entry, count),
            ),
        if (current != null) ...[
          const SizedBox(height: 8),
          Text(
            current.objectivesSatisfied
                ? 'Quest completion can be recorded without an override.'
                : 'Marking complete now requires a manual override; the '
                      'objective counts stay unchanged.',
            key: const Key('quest-objectives-hint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _ObjectiveRow extends StatefulWidget {
  const _ObjectiveRow({
    super.key,
    required this.progress,
    required this.itemNames,
    required this.enabled,
    required this.onChanged,
  });

  final QuestObjectiveProgress progress;
  final Map<String, String> itemNames;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<_ObjectiveRow> createState() => _ObjectiveRowState();
}

class _ObjectiveRowState extends State<_ObjectiveRow> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.progress.count}',
  );

  @override
  void didUpdateWidget(_ObjectiveRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = '${widget.progress.count}';
    if (_controller.text != text) {
      _controller.text = text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) {
      _controller.text = '${widget.progress.count}';
      return;
    }
    widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = widget.progress;
    final objective = progress.objective;
    final required = progress.requiredCount;
    final count = progress.count;
    final canDecrement = widget.enabled && count > 0;
    final canIncrement = widget.enabled && count < required;
    final itemLabels = <String>[
      for (final id in objective.itemIds) widget.itemNames[id] ?? id,
      if (objective.questItemId case final id?) widget.itemNames[id] ?? id,
      for (final id in objective.requiredKeyItemIds) widget.itemNames[id] ?? id,
    ];
    final details = <String>[
      _humanizeType(objective.type),
      if (objective.optional) 'Optional',
      if (objective.mapIds.isNotEmpty) objective.mapIds.join(', '),
      if (objective.targetNames.isNotEmpty) objective.targetNames.join(', '),
      if (itemLabels.isNotEmpty) itemLabels.join(', '),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  progress.satisfied
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: progress.satisfied
                      ? Colors.green.shade700
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      objective.description,
                      key: ValueKey(
                        'quest-objective-description-${objective.id}',
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      details.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: ValueKey('quest-objective-decrement-${objective.id}'),
                    tooltip: 'Decrease objective count',
                    visualDensity: VisualDensity.compact,
                    onPressed: canDecrement
                        ? () => widget.onChanged(count - 1)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                  ),
                  SizedBox(
                    width: 56,
                    child: TextField(
                      key: ValueKey('quest-objective-count-${objective.id}'),
                      controller: _controller,
                      enabled: widget.enabled,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: _submit,
                    ),
                  ),
                  Text(
                    ' / $required',
                    key: ValueKey('quest-objective-required-${objective.id}'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  IconButton(
                    key: ValueKey('quest-objective-increment-${objective.id}'),
                    tooltip: 'Increase objective count',
                    visualDensity: VisualDensity.compact,
                    onPressed: canIncrement
                        ? () => widget.onChanged(count + 1)
                        : null,
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Requirements and lock reasons
// ---------------------------------------------------------------------------

class _RequirementsSection extends StatelessWidget {
  const _RequirementsSection({
    required this.detail,
    required this.status,
    required this.statusesById,
    required this.traderLabel,
    required this.hasProfile,
    required this.onQuestTap,
  });

  final QuestDetail detail;
  final QuestStatus? status;
  final Map<String, QuestStatus> statusesById;
  final String? traderLabel;
  final bool hasProfile;
  final ValueChanged<String> onQuestTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = status;
    final blocking = current?.blockingReasons ?? const <QuestLockReason>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Requirements',
          subtitle: current == null
              ? 'Availability is computed for the active profile.'
              : current.isLocked
              ? 'Locked: ${blocking.length} blocking requirement(s).'
              : 'Every blocking requirement is met.',
        ),
        const SizedBox(height: 8),
        if (detail.minPlayerLevel case final level?)
          _RequirementLine(
            key: const Key('quest-requirement-level'),
            icon: Icons.person_outline,
            title: 'Player level $level',
            detail: _levelDetail(current, level),
            satisfied: current == null
                ? null
                : !blocking.any((reason) => reason is PlayerLevelTooLow),
          ),
        for (final prerequisite in detail.prerequisites)
          _PrerequisiteLine(
            key: ValueKey('quest-prerequisite-${prerequisite.taskId}'),
            prerequisite: prerequisite,
            state: statusesById[prerequisite.taskId],
            hasProfile: hasProfile,
            onTap: statusesById.containsKey(prerequisite.taskId)
                ? () => onQuestTap(prerequisite.taskId)
                : null,
          ),
        for (final requirement in detail.traderRequirements)
          _RequirementLine(
            key: ValueKey('quest-trader-requirement-${requirement.traderId}'),
            icon: Icons.storefront_outlined,
            title:
                'Trader ${requirement.traderId == detail.traderId && traderLabel != null ? traderLabel : requirement.traderId} '
                '${requirement.isLoyaltyLevel ? 'loyalty level' : requirement.requirementType ?? 'requirement'}',
            detail:
                '${requirement.compareMethod ?? '>='} ${requirement.value ?? '?'} '
                '· advisory only (no local loyalty data)',
            satisfied: null,
          ),
        if (detail.prerequisites.isEmpty &&
            detail.traderRequirements.isEmpty &&
            detail.minPlayerLevel == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('No prerequisite quests, trader or level gates.'),
          ),
        if (hasProfile && current != null) ...[
          const SizedBox(height: 12),
          Text(
            'Why this state',
            key: const Key('quest-lock-reasons-title'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          if (current.reasons.isEmpty)
            const Text('No blocking reason is reported for this quest.')
          else
            for (var index = 0; index < current.reasons.length; index++)
              _ReasonLine(
                key: ValueKey('quest-lock-reason-$index'),
                reason: current.reasons[index],
              ),
        ],
      ],
    );
  }

  static String? _levelDetail(QuestStatus? status, int level) {
    if (status == null) {
      return null;
    }
    for (final reason in status.reasons) {
      if (reason is PlayerLevelTooLow) {
        return 'The profile is level ${reason.playerLevel}.';
      }
    }
    return 'The profile meets this level.';
  }
}

class _PrerequisiteLine extends StatelessWidget {
  const _PrerequisiteLine({
    super.key,
    required this.prerequisite,
    required this.state,
    required this.hasProfile,
    required this.onTap,
  });

  final QuestPrerequisite prerequisite;
  final QuestStatus? state;
  final bool hasProfile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final actual = state?.recordedState ?? QuestProgressState.notStarted;
    final required = prerequisite.requiredStatuses.isEmpty
        ? 'a recorded status'
        : prerequisite.requiredStatuses.join(' or ');
    final name = state?.name ?? prerequisite.taskId;
    final bool? satisfied;
    final String detail;
    if (!hasProfile) {
      satisfied = null;
      detail = 'Requires $required';
    } else if (state == null) {
      satisfied = false;
      detail = 'Missing from the current dataset';
    } else {
      satisfied = prerequisite.isSatisfiedBy(actual);
      detail = 'Requires $required · currently ${questStateLabel(actual)}';
    }

    return _RequirementLine(
      icon: Icons.flag_outlined,
      title: name,
      detail: detail,
      satisfied: satisfied,
      onTap: onTap,
    );
  }
}

class _RequirementLine extends StatelessWidget {
  const _RequirementLine({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.satisfied,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final bool? satisfied;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                if (detail != null)
                  Text(
                    detail!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (satisfied != null)
            Icon(
              satisfied! ? Icons.check : Icons.close,
              size: 18,
              color: satisfied!
                  ? Colors.green.shade700
                  : theme.colorScheme.error,
            ),
          if (onTap != null) const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );

    if (onTap == null) {
      return row;
    }
    return InkWell(onTap: onTap, child: row);
  }
}

class _ReasonLine extends StatelessWidget {
  const _ReasonLine({super.key, required this.reason});

  final QuestLockReason reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocking = reason.blocksStart;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            blocking ? Icons.lock_outline : Icons.info_outline,
            size: 16,
            color: blocking
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(reason.description, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rewards
// ---------------------------------------------------------------------------

class _RewardsSection extends StatelessWidget {
  const _RewardsSection({
    required this.detail,
    required this.itemNames,
    required this.traderLabel,
    required this.onItemTap,
  });

  final QuestDetail detail;
  final Map<String, String> itemNames;
  final String? traderLabel;
  final ValueChanged<String> onItemTap;

  @override
  Widget build(BuildContext context) {
    final rewards = detail.rewards;
    final theme = Theme.of(context);
    if (rewards.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Rewards'),
          SizedBox(height: 8),
          Text('No rewards are published for this quest.'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Rewards'),
        const SizedBox(height: 8),
        for (final item in rewards.items)
          _ItemLine(
            key: ValueKey('quest-reward-item-${item.itemId}'),
            itemId: item.itemId,
            label: itemNames[item.itemId] ?? item.itemId,
            trailing: '×${item.count}',
            onTap: () => onItemTap(item.itemId),
          ),
        for (final standing in rewards.traderStanding)
          Text(
            'Trader standing ${standing.standing >= 0 ? '+' : ''}'
            '${standing.standing} with '
            '${standing.traderId == detail.traderId && traderLabel != null ? traderLabel : standing.traderId}',
            style: theme.textTheme.bodyMedium,
          ),
        for (final skill in rewards.skills)
          _PlainLine(
            icon: Icons.trending_up,
            label: '${skill.skill} +${skill.level}',
          ),
        for (final offer in rewards.offerUnlocks)
          _ItemLine(
            key: ValueKey('quest-reward-offer-${offer.id}'),
            itemId: offer.itemId,
            label: offer.itemId == null
                ? 'Trader offer ${offer.id}'
                : itemNames[offer.itemId] ?? offer.itemId!,
            trailing: offer.level == null ? null : 'Level ${offer.level}',
            onTap: offer.itemId == null ? null : () => onItemTap(offer.itemId!),
          ),
        for (final craft in rewards.craftUnlocks)
          _ItemLine(
            key: ValueKey('quest-reward-craft-${craft.stationId}'),
            itemId: craft.itemId,
            label: craft.itemId == null
                ? 'Craft at ${craft.stationId}'
                : itemNames[craft.itemId] ?? craft.itemId!,
            trailing: craft.level == null ? null : 'Level ${craft.level}',
            onTap: craft.itemId == null ? null : () => onItemTap(craft.itemId!),
          ),
        for (final customization in rewards.customizations)
          _PlainLine(
            icon: Icons.palette_outlined,
            label: customization.name ?? customization.id,
          ),
        if (rewards.traderUnlockIds.isNotEmpty)
          _PlainLine(
            icon: Icons.storefront_outlined,
            label: 'Unlocks traders: ${rewards.traderUnlockIds.join(', ')}',
          ),
        if (rewards.locationUnlockIds.isNotEmpty)
          _PlainLine(
            icon: Icons.map_outlined,
            label: 'Unlocks locations: ${rewards.locationUnlockIds.join(', ')}',
          ),
        if (rewards.achievementIds.isNotEmpty)
          _PlainLine(
            icon: Icons.emoji_events_outlined,
            label: 'Achievements: ${rewards.achievementIds.join(', ')}',
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Turn-in and required items
// ---------------------------------------------------------------------------

class _ItemsSection extends StatelessWidget {
  const _ItemsSection({
    required this.detail,
    required this.itemNames,
    required this.onItemTap,
  });

  final QuestDetail detail;
  final Map<String, String> itemNames;
  final ValueChanged<String> onItemTap;

  @override
  Widget build(BuildContext context) {
    final rows = <({String itemId, String source, bool turnIn})>[];
    final seen = <String>{};
    for (final objective in detail.objectives) {
      final turnIn =
          objective.type == 'giveItem' || objective.type == 'giveQuestItem';
      final ids = <String>[
        ...objective.itemIds,
        ?objective.questItemId,
        ...objective.requiredKeyItemIds,
      ];
      for (final id in ids) {
        if (!seen.add(id)) {
          continue;
        }
        rows.add((itemId: id, source: objective.description, turnIn: turnIn));
      }
    }
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Turn-in and required items'),
        const SizedBox(height: 8),
        for (final row in rows)
          _ItemLine(
            key: ValueKey('quest-item-${row.itemId}'),
            itemId: row.itemId,
            label: itemNames[row.itemId] ?? row.itemId,
            trailing: row.turnIn ? 'Turn in' : 'Required',
            onTap: () => onItemTap(row.itemId),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Unlocks
// ---------------------------------------------------------------------------

class _UnlocksSection extends StatelessWidget {
  const _UnlocksSection({
    required this.detail,
    required this.statusesById,
    required this.onQuestTap,
  });

  final QuestDetail detail;
  final Map<String, QuestStatus> statusesById;
  final ValueChanged<String> onQuestTap;

  @override
  Widget build(BuildContext context) {
    if (detail.unlocks.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Unlocks'),
          SizedBox(height: 8),
          Text('No quest in the current dataset requires this one.'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Unlocks'),
        const SizedBox(height: 8),
        for (final unlock in detail.unlocks)
          _QuestLine(
            key: ValueKey('quest-unlock-${unlock.questId}'),
            name: unlock.name,
            detail: unlock.requiredStatuses.isEmpty
                ? 'Becomes available'
                : 'Requires ${unlock.requiredStatuses.join(' or ')}',
            state: statusesById[unlock.questId],
            onTap: () => onQuestTap(unlock.questId),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Status controls
// ---------------------------------------------------------------------------

class _StatusSection extends StatelessWidget {
  const _StatusSection({
    required this.status,
    required this.profileId,
    required this.busy,
    required this.actionError,
    required this.onStateSelected,
    required this.onRevert,
  });

  final QuestStatus? status;
  final String? profileId;
  final bool busy;
  final Object? actionError;
  final ValueChanged<QuestProgressState> onStateSelected;
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = status;
    final recorded = current?.recordedState;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Track progress'),
        const SizedBox(height: 8),
        if (profileId == null)
          const Text(
            'Choose a profile to record objective progress and quest state.',
            key: Key('quest-status-no-profile'),
          )
        else ...[
          if (actionError != null)
            Container(
              key: const Key('quest-action-error'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Could not save progress: $actionError',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const Key('quest-status-mark-in-progress'),
                onPressed: busy
                    ? null
                    : () => onStateSelected(QuestProgressState.inProgress),
                child: const Text('Mark in progress'),
              ),
              FilledButton(
                key: const Key('quest-status-mark-completed'),
                onPressed: busy
                    ? null
                    : () => onStateSelected(QuestProgressState.completed),
                child: Text(
                  recorded == QuestProgressState.completed
                      ? 'Completed'
                      : 'Mark completed',
                ),
              ),
              OutlinedButton(
                key: const Key('quest-status-mark-failed'),
                onPressed: busy
                    ? null
                    : () => onStateSelected(QuestProgressState.failed),
                child: const Text('Mark failed'),
              ),
              if (recorded != null && recorded != QuestProgressState.notStarted)
                TextButton(
                  key: const Key('quest-status-revert'),
                  onPressed: busy ? null : onRevert,
                  child: const Text('Revert'),
                ),
            ],
          ),
          if (current != null) ...[
            const SizedBox(height: 8),
            Text(
              current.manuallyCompleted
                  ? 'Completed by manual override. Objective counts were not '
                        'changed.'
                  : current.objectivesSatisfied
                  ? 'Every required objective is recorded; completion needs no '
                        'override.'
                  : 'Completing now needs confirmation and leaves objective '
                        'counts unchanged.',
              key: const Key('quest-status-hint'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared rows
// ---------------------------------------------------------------------------

class _ItemLine extends StatelessWidget {
  const _ItemLine({
    super.key,
    required this.itemId,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final String? itemId;
  final String label;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mergedId = itemId;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              key: mergedId == null
                  ? null
                  : ValueKey('quest-item-label-$mergedId'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: onTap == null ? null : theme.colorScheme.primary,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (onTap != null) const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );
    if (onTap == null) {
      return row;
    }
    return InkWell(
      key: mergedId == null ? null : ValueKey('quest-item-link-$mergedId'),
      onTap: onTap,
      child: row,
    );
  }
}

class _QuestLine extends StatelessWidget {
  const _QuestLine({
    super.key,
    required this.name,
    required this.detail,
    required this.state,
    required this.onTap,
  });

  final String name;
  final String detail;
  final QuestStatus? state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            const Icon(Icons.flag_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.bodyMedium),
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (state != null) QuestStateBadge(state: state!.recordedState),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

class _PlainLine extends StatelessWidget {
  const _PlainLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen states
// ---------------------------------------------------------------------------

class _NotFoundState extends StatelessWidget {
  const _NotFoundState({required this.questId, required this.onBack});

  final String questId;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.help_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Quest not found',
              key: const Key('quest-detail-not-found'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Quest $questId is not in the current dataset.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              key: const Key('quest-detail-back'),
              onPressed: onBack,
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrphanState extends StatelessWidget {
  const _OrphanState({required this.orphan, required this.onBack});

  final OrphanedQuestProgress orphan;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      key: const Key('quest-detail-orphaned'),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.link_off, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Quest unavailable upstream',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Quest ${orphan.questId} is no longer in the current dataset. '
                'The progress recorded for this profile is preserved and is '
                'not used to satisfy other quests.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text('Preserved state', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              QuestStateBadge(
                key: const Key('quest-orphan-state'),
                state: orphan.state,
              ),
              if (orphan.objectiveCounts.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Recorded objective counts',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                for (final entry in orphan.objectiveCounts.entries)
                  Text('${entry.key}: ${entry.value}'),
              ],
              if (orphan.updatedAt != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Last updated ${orphan.updatedAt}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.tonal(
                key: const Key('quest-orphan-back'),
                onPressed: onBack,
                child: const Text('Back'),
              ),
            ],
          ),
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
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              'Could not load this quest.',
              key: const Key('quest-detail-error'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '$error',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('quest-detail-retry'),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

String _humanizeType(String value) {
  if (value.isEmpty) {
    return 'Objective';
  }
  final spaced = value
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ')
      .trim();
  if (spaced.isEmpty) {
    return value;
  }
  return spaced[0].toUpperCase() + spaced.substring(1);
}
