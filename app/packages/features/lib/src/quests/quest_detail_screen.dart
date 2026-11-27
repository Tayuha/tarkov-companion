import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import '../catalog/item_detail_screen.dart';
import '../common/app_status_strip.dart';
import '../common/upstream_status.dart';
import '../theme/app_primitives.dart';
import '../theme/app_tokens.dart';
import 'quest_list_row.dart'
    show QuestAvailabilityBadge, QuestStateBadge, questStateLabel;

/// The full, interactive view of one quest.
///
/// The screen combines [QuestRepository.detail] (the catalog record) with
/// [QuestRepository.statuses] (availability and the active profile's recorded
/// progress) and renders:
///
/// * a tokenised header with the quest name, recorded state badge, computed
///   availability, trader and map labels, level, experience, Kappa flag and
///   wiki link;
/// * every objective in an [AppPanel] row with its progress rail and the
///   profile's increment/decrement controls;
/// * the requirement list and the exact structured reasons the availability
///   engine reports, including advisor-only trader loyalty requirements;
/// * reward tiles, turn-in/required items and quest unlocks, each item opening
///   [ItemDetailScreen] and each quest pushing another detail screen;
/// * status controls for in progress, completed, failed and revert.
///
/// Missing fields render nothing: a quest without a description has no notes
/// panel, an empty reward block has no rewards panel, and a quest with no
/// unlocks has no unlocks panel. Derived explanatory copy (the requirement and
/// objective summaries) is not a placeholder for a missing field.
///
/// From 1080 logical pixels the content splits into two columns: objectives,
/// required items and notes on the left; rewards, requirements, unlocks and
/// status on the right. Below that the same content is one ordered column. The
/// content is capped at 1180 logical pixels.
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
    this.upstreamCheck,
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

  /// Optional upstream check shown as a non-blocking strip above the detail.
  /// The pushed route keeps its content while the check fails; retry only
  /// re-runs the check.
  final UpstreamCheck? upstreamCheck;

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

  /// Owns the optional upstream check; `null` when the caller supplied none.
  UpstreamStatusController? _upstream;

  @override
  void initState() {
    super.initState();
    _attachUpstream(widget.upstreamCheck);
    _load();
  }

  @override
  void didUpdateWidget(QuestDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.upstreamCheck != widget.upstreamCheck) {
      _attachUpstream(widget.upstreamCheck);
    }
    if (oldWidget.questId != widget.questId ||
        oldWidget.repository != widget.repository ||
        oldWidget.catalog != widget.catalog ||
        oldWidget.profileId != widget.profileId) {
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

  Future<void> _load({bool showLoading = true}) async {
    final generation = ++_generation;
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final detail = await widget.repository.detail(
        widget.questId,
        profileId: widget.profileId,
      );
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
      return Center(
        child: CircularProgressIndicator(
          key: const Key('quest-detail-loading'),
        ),
      );
    }
    final error = _error;
    if (error != null) {
      return isUpstreamError(error)
          ? _UpstreamErrorState(error: error, onRetry: _load)
          : _ErrorState(error: error, onRetry: _load);
    }
    final Widget content;
    if (detail != null) {
      content = _DetailBody(
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
    } else {
      final orphan = _orphan;
      if (orphan != null) {
        content = _OrphanState(orphan: orphan, onBack: _back);
      } else {
        content = _NotFoundState(questId: widget.questId, onBack: _back);
      }
    }
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
        key: const Key('quest-detail-upstream-status'),
        kind: AppStatusStripKind.updating,
        message: 'Showing the saved quest while the update check runs.',
      );
    }
    if (!status.needsBanner) {
      return null;
    }
    return AppStatusStrip.upstream(
      key: const Key('quest-detail-upstream-status'),
      status: status,
      onRetry: controller.refresh,
    );
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

  /// The widest the inspector grows, even on a 1920 monitor.
  static const double maxContentWidth = 1180;

  /// At or above this width, content moves into a second column.
  static const double twoColumnBreakpoint = 1080;

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
    final tokens = AppTokens.of(context);
    final description = detail.description?.trim();
    final notes = description == null || description.isEmpty
        ? null
        : _NotesSection(description: description);
    final items = _ItemsSection.hasRows(detail)
        ? _ItemsSection(
            detail: detail,
            itemNames: itemNames,
            onItemTap: onItemTap,
          )
        : null;
    final rewards = detail.rewards.isEmpty
        ? null
        : _RewardsSection(
            detail: detail,
            itemNames: itemNames,
            traderLabel: traderLabel,
            onItemTap: onItemTap,
          );
    final unlocks = detail.unlocks.isEmpty
        ? null
        : _UnlocksSection(
            detail: detail,
            statusesById: statusesById,
            onQuestTap: onQuestTap,
          );

    final left = <Widget>[
      _ObjectivesSection(
        detail: detail,
        status: status,
        hasProfile: profileId != null,
        busy: busy,
        itemNames: itemNames,
        onChanged: onObjectiveCount,
      ),
      ?items,
      ?notes,
    ];
    final right = <Widget>[
      ?rewards,
      _RequirementsSection(
        detail: detail,
        status: status,
        statusesById: statusesById,
        traderLabel: traderLabel,
        hasProfile: profileId != null,
        onQuestTap: onQuestTap,
      ),
      ?unlocks,
      _StatusSection(
        status: status,
        profileId: profileId,
        busy: busy,
        actionError: actionError,
        onStateSelected: onStateSelected,
        onRevert: onRevert,
      ),
    ];

    return SingleChildScrollView(
      key: const Key('quest-detail-scroll'),
      padding: EdgeInsets.all(tokens.spaceXl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxContentWidth),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final twoColumn =
                  constraints.maxWidth >= twoColumnBreakpoint &&
                  right.isNotEmpty;
              final content = twoColumn
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _Stack(children: left)),
                        SizedBox(width: tokens.spaceXl),
                        SizedBox(width: 380, child: _Stack(children: right)),
                      ],
                    )
                  : _Stack(children: [...left, ...right]);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    detail: detail,
                    status: status,
                    traderLabel: traderLabel,
                    mapLabel: mapLabel,
                    hasProfile: profileId != null,
                  ),
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
    final tokens = AppTokens.of(context);
    final recordedState = status?.recordedState;
    final availability = status?.availability;
    final wikiLink = detail.wikiLink;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionLabel('Quest detail'),
        SizedBox(height: tokens.spaceXs),
        Wrap(
          spacing: tokens.spaceMd,
          runSpacing: tokens.spaceSm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              detail.name,
              key: const Key('quest-detail-name'),
              style: tokens.h1Style,
            ),
            if (hasProfile && recordedState != null)
              QuestStateBadge(
                key: const Key('quest-detail-state'),
                state: recordedState,
              ),
            if (availability != null)
              QuestAvailabilityBadge(
                key: const Key('quest-detail-availability'),
                availability: availability,
              ),
            if (!hasProfile)
              const AppChip(
                key: Key('quest-detail-no-profile'),
                label: 'No profile selected',
              ),
            if (status?.manuallyCompleted ?? false)
              const AppChip(
                key: Key('quest-detail-manual-override'),
                label: 'Manual override',
                selected: true,
              ),
          ],
        ),
        SizedBox(height: tokens.spaceMd),
        Wrap(
          key: const Key('quest-detail-metadata'),
          spacing: tokens.spaceSm,
          runSpacing: tokens.spaceSm,
          children: [
            _MetadataTag(
              key: const Key('quest-detail-trader'),
              icon: Icons.storefront_outlined,
              label: traderLabel == null
                  ? 'No trader recorded'
                  : 'Trader: $traderLabel',
            ),
            _MetadataTag(
              key: const Key('quest-detail-map'),
              icon: Icons.map_outlined,
              label: mapLabel == null ? 'No map recorded' : 'Map: $mapLabel',
            ),
            _MetadataTag(
              key: const Key('quest-detail-level'),
              icon: Icons.person_outline,
              label: detail.minPlayerLevel == null
                  ? 'No level requirement'
                  : 'Level ${detail.minPlayerLevel}',
            ),
            _MetadataTag(
              key: const Key('quest-detail-experience'),
              icon: Icons.stars_outlined,
              label: detail.experience == null
                  ? 'No XP recorded'
                  : '${detail.experience} XP',
            ),
            _MetadataTag(
              key: const Key('quest-detail-kappa'),
              icon: Icons.workspace_premium_outlined,
              label: detail.kappaRequired
                  ? 'Kappa required'
                  : 'Not Kappa required',
            ),
            if (detail.restartable)
              const _MetadataTag(icon: Icons.refresh, label: 'Restartable'),
          ],
        ),
        if (wikiLink != null) ...[
          SizedBox(height: tokens.spaceMd),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 56, child: const AppSectionLabel('Wiki')),
              Expanded(
                child: SelectableText(
                  wikiLink,
                  key: const Key('quest-detail-wiki-link'),
                  style: tokens.bodyStyle.copyWith(color: tokens.info),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A quiet bordered metadata tag that keeps its sentence-case label.
///
/// [AppChip] uppercases by design; trader, map and level labels are field
/// values, so they get the same geometry without the filter treatment.
class _MetadataTag extends StatelessWidget {
  const _MetadataTag({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      height: 24,
      padding: EdgeInsets.only(left: tokens.spaceSm, right: tokens.spaceMd),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border.all(color: tokens.borderSoft),
        borderRadius: BorderRadius.circular(tokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: tokens.bodySize, color: tokens.dim),
          SizedBox(width: tokens.spaceXs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.bodyStyle.copyWith(
              fontSize: tokens.dataSize,
              color: tokens.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotesSection extends StatelessWidget {
  const _NotesSection({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return AppPanel(
      key: const Key('quest-detail-section-notes'),
      label: 'Notes',
      child: Text(
        description,
        key: const Key('quest-detail-description'),
        style: tokens.bodyStyle.copyWith(color: tokens.muted),
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
    final tokens = AppTokens.of(context);
    final progress = _progress;
    final required = progress.where((entry) => !entry.optional).length;
    final satisfied = progress
        .where((entry) => !entry.optional && entry.satisfied)
        .length;
    final current = status;

    return AppPanel(
      key: const Key('quest-detail-section-objectives'),
      label: 'Objectives',
      trailing: progress.isEmpty
          ? null
          : Text(
              '$satisfied / $required',
              style: tokens.dataStyle.copyWith(color: tokens.muted),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            current == null
                ? 'Counts are recorded per profile.'
                : current.objectivesSatisfied
                ? 'All required objectives are satisfied.'
                : '$satisfied of $required required objectives satisfied.',
            key: const Key('quest-objectives-summary'),
            style: tokens.bodyStyle.copyWith(color: tokens.muted),
          ),
          SizedBox(height: tokens.spaceMd),
          if (progress.isEmpty)
            Text(
              'This quest has no objectives in the dataset.',
              style: tokens.bodyStyle.copyWith(color: tokens.muted),
            )
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
            SizedBox(height: tokens.spaceSm),
            Text(
              current.objectivesSatisfied
                  ? 'Quest completion can be recorded without an override.'
                  : 'Marking complete now requires a manual override; the '
                        'objective counts stay unchanged.',
              key: const Key('quest-objectives-hint'),
              style: tokens.bodyStyle.copyWith(color: tokens.muted),
            ),
          ],
        ],
      ),
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
    final tokens = AppTokens.of(context);
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
    final fraction = required <= 0 ? 1.0 : count / required;

    return Container(
      margin: EdgeInsets.only(bottom: tokens.spaceSm),
      padding: EdgeInsets.all(tokens.spaceMd),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border.all(color: tokens.borderSoft),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: tokens.spaceXs / 2),
                child: Icon(
                  progress.satisfied
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: tokens.h2Size,
                  color: progress.satisfied ? tokens.success : tokens.dim,
                ),
              ),
              SizedBox(width: tokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      objective.description,
                      key: ValueKey(
                        'quest-objective-description-${objective.id}',
                      ),
                      style: tokens.bodyStyle,
                    ),
                    SizedBox(height: tokens.spaceXs / 2),
                    Text(
                      details.join(' · '),
                      style: tokens.labelStyle.copyWith(color: tokens.muted),
                    ),
                  ],
                ),
              ),
              SizedBox(width: tokens.spaceMd),
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
                      style: tokens.dataStyle,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: tokens.spaceXs,
                          vertical: tokens.spaceSm,
                        ),
                      ),
                      onSubmitted: _submit,
                    ),
                  ),
                  Text(
                    ' / $required',
                    key: ValueKey('quest-objective-required-${objective.id}'),
                    style: tokens.dataStyle,
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
          SizedBox(height: tokens.spaceSm),
          AppProgressBar(
            value: fraction,
            trailing: '$count / $required',
            color: progress.satisfied ? tokens.accent : tokens.info,
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
    final tokens = AppTokens.of(context);
    final current = status;
    final blocking = current?.blockingReasons ?? const <QuestLockReason>[];
    final hasGates =
        detail.minPlayerLevel != null ||
        detail.prerequisites.isNotEmpty ||
        detail.traderRequirements.isNotEmpty;

    return AppPanel(
      key: const Key('quest-detail-section-requirements'),
      label: 'Requirements',
      trailing: current == null
          ? null
          : Text(
              current.isLocked ? '${blocking.length} blocking' : 'met',
              style: tokens.dataStyle.copyWith(
                color: current.isLocked ? tokens.danger : tokens.success,
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            current == null
                ? 'Availability is computed for the active profile.'
                : current.isLocked
                ? 'Locked: ${blocking.length} blocking requirement(s).'
                : 'Every blocking requirement is met.',
            key: const Key('quest-requirements-summary'),
            style: tokens.bodyStyle.copyWith(color: tokens.muted),
          ),
          SizedBox(height: tokens.spaceSm),
          if (!hasGates)
            Text(
              'No prerequisite quests, trader or level gates.',
              style: tokens.bodyStyle.copyWith(color: tokens.muted),
            ),
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
          if (hasProfile && current != null) ...[
            SizedBox(height: tokens.spaceMd),
            const AppSectionLabel(
              'Why this state',
              key: Key('quest-lock-reasons-title'),
            ),
            SizedBox(height: tokens.spaceXs),
            if (current.reasons.isEmpty)
              Text(
                'No blocking reason is reported for this quest.',
                style: tokens.bodyStyle.copyWith(color: tokens.muted),
              )
            else
              for (var index = 0; index < current.reasons.length; index++)
                _ReasonLine(
                  key: ValueKey('quest-lock-reason-$index'),
                  reason: current.reasons[index],
                ),
          ],
        ],
      ),
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
    final tokens = AppTokens.of(context);
    final detail = this.detail;
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: tokens.h2Size, color: tokens.dim),
          SizedBox(width: tokens.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tokens.bodyStyle.copyWith(
                    color: onTap == null ? tokens.text : tokens.info,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail,
                    style: tokens.bodyStyle.copyWith(color: tokens.muted),
                  ),
              ],
            ),
          ),
          if (satisfied != null)
            Icon(
              satisfied! ? Icons.check : Icons.close,
              size: tokens.h2Size,
              color: satisfied! ? tokens.success : tokens.danger,
            ),
          if (onTap != null)
            Icon(Icons.chevron_right, size: tokens.h2Size, color: tokens.dim),
        ],
      ),
    );

    if (onTap == null) {
      return row;
    }
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        hoverColor: tokens.accent.withValues(alpha: 0.06),
        child: row,
      ),
    );
  }
}

class _ReasonLine extends StatelessWidget {
  const _ReasonLine({super.key, required this.reason});

  final QuestLockReason reason;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final blocking = reason.blocksStart;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spaceXs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            blocking ? Icons.lock_outline : Icons.info_outline,
            size: tokens.h2Size,
            color: blocking ? tokens.danger : tokens.dim,
          ),
          SizedBox(width: tokens.spaceSm),
          Expanded(
            child: Text(
              reason.description,
              style: tokens.bodyStyle.copyWith(color: tokens.muted),
            ),
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
    final tiles = <Widget>[
      for (final item in rewards.items)
        _RewardTile(
          key: ValueKey('quest-reward-item-${item.itemId}'),
          linkKey: ValueKey('quest-item-link-${item.itemId}'),
          label: 'Item',
          value: itemNames[item.itemId] ?? item.itemId,
          subtitle: '×${item.count}',
          onTap: () => onItemTap(item.itemId),
        ),
      for (final standing in rewards.traderStanding)
        _RewardTile(
          key: ValueKey('quest-reward-standing-${standing.traderId}'),
          label: 'Reputation',
          value: '${standing.standing >= 0 ? '+' : ''}${standing.standing}',
          subtitle: standing.traderId == detail.traderId && traderLabel != null
              ? traderLabel
              : standing.traderId,
        ),
      for (final skill in rewards.skills)
        _RewardTile(
          key: ValueKey('quest-reward-skill-${skill.skill}'),
          label: 'Skill',
          value: '${skill.skill} +${skill.level}',
        ),
      for (final offer in rewards.offerUnlocks)
        _RewardTile(
          key: ValueKey('quest-reward-offer-${offer.id}'),
          linkKey: offer.itemId == null
              ? null
              : ValueKey('quest-item-link-${offer.itemId}'),
          label: 'Trader offer',
          value: offer.itemId == null
              ? 'Trader offer ${offer.id}'
              : itemNames[offer.itemId] ?? offer.itemId!,
          subtitle: offer.level == null ? null : 'Level ${offer.level}',
          onTap: offer.itemId == null ? null : () => onItemTap(offer.itemId!),
        ),
      for (final craft in rewards.craftUnlocks)
        _RewardTile(
          key: ValueKey('quest-reward-craft-${craft.stationId}'),
          linkKey: craft.itemId == null
              ? null
              : ValueKey('quest-item-link-${craft.itemId}'),
          label: 'Craft',
          value: craft.itemId == null
              ? 'Craft at ${craft.stationId}'
              : itemNames[craft.itemId] ?? craft.itemId!,
          subtitle: craft.level == null ? null : 'Level ${craft.level}',
          onTap: craft.itemId == null ? null : () => onItemTap(craft.itemId!),
        ),
      for (final customization in rewards.customizations)
        _RewardTile(
          key: ValueKey('quest-reward-customization-${customization.id}'),
          label: 'Customization',
          value: customization.name ?? customization.id,
        ),
      if (rewards.traderUnlockIds.isNotEmpty)
        _RewardTile(
          label: 'Traders',
          value: rewards.traderUnlockIds.join(', '),
        ),
      if (rewards.locationUnlockIds.isNotEmpty)
        _RewardTile(
          label: 'Locations',
          value: rewards.locationUnlockIds.join(', '),
        ),
      if (rewards.achievementIds.isNotEmpty)
        _RewardTile(
          label: 'Achievements',
          value: rewards.achievementIds.join(', '),
        ),
    ];

    return AppPanel(
      key: const Key('quest-detail-section-rewards'),
      label: 'Rewards',
      child: _RewardGrid(tiles: tiles),
    );
  }
}

class _RewardGrid extends StatelessWidget {
  const _RewardGrid({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    if (tiles.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 160).floor().clamp(1, 4);
        final gap = tokens.spaceSm;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

class _RewardTile extends StatelessWidget {
  const _RewardTile({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.linkKey,
    this.onTap,
  });

  final String label;
  final String value;
  final String? subtitle;
  final Key? linkKey;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final tile = AppStatTile(label: label, value: value, subtitle: subtitle);
    if (onTap == null) {
      return tile;
    }
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: linkKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        hoverColor: tokens.accent.withValues(alpha: 0.06),
        child: tile,
      ),
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

  /// Whether any objective references an item, so the screen can omit the
  /// section rather than render an empty panel.
  static bool hasRows(QuestDetail detail) {
    final seen = <String>{};
    for (final objective in detail.objectives) {
      final ids = <String>[
        ...objective.itemIds,
        ?objective.questItemId,
        ...objective.requiredKeyItemIds,
      ];
      for (final id in ids) {
        if (seen.add(id)) {
          return true;
        }
      }
    }
    return false;
  }

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

    return AppPanel(
      key: const Key('quest-detail-section-items'),
      label: 'Turn-in and required items',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows)
            _ItemLine(
              key: ValueKey('quest-item-${row.itemId}'),
              itemId: row.itemId,
              label: itemNames[row.itemId] ?? row.itemId,
              trailing: row.turnIn ? 'Turn in' : 'Required',
              onTap: () => onItemTap(row.itemId),
            ),
        ],
      ),
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
    return AppPanel(
      key: const Key('quest-detail-section-unlocks'),
      label: 'Unlocks',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
      ),
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
    final tokens = AppTokens.of(context);
    final current = status;
    final recorded = current?.recordedState;

    return AppPanel(
      key: const Key('quest-detail-section-status'),
      label: 'Status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (profileId == null)
            Text(
              'Choose a profile to record objective progress and quest state.',
              key: const Key('quest-status-no-profile'),
              style: tokens.bodyStyle.copyWith(color: tokens.muted),
            )
          else ...[
            if (actionError != null)
              Container(
                key: const Key('quest-action-error'),
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
                  border: Border.all(
                    color: tokens.danger.withValues(alpha: 0.6),
                  ),
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
                child: Text(
                  'Could not save progress: $actionError',
                  style: tokens.bodyStyle.copyWith(color: tokens.danger),
                ),
              ),
            AppButton(
              key: const Key('quest-status-mark-in-progress'),
              label: 'Mark in progress',
              variant: AppButtonVariant.secondary,
              expand: true,
              onPressed: busy
                  ? null
                  : () => onStateSelected(QuestProgressState.inProgress),
            ),
            SizedBox(height: tokens.spaceSm),
            AppButton(
              key: const Key('quest-status-mark-completed'),
              label: recorded == QuestProgressState.completed
                  ? 'Completed'
                  : 'Mark completed',
              onPressed: busy
                  ? null
                  : () => onStateSelected(QuestProgressState.completed),
            ),
            SizedBox(height: tokens.spaceSm),
            AppButton(
              key: const Key('quest-status-mark-failed'),
              label: 'Mark failed',
              variant: AppButtonVariant.danger,
              expand: true,
              onPressed: busy
                  ? null
                  : () => onStateSelected(QuestProgressState.failed),
            ),
            if (recorded != null &&
                recorded != QuestProgressState.notStarted) ...[
              SizedBox(height: tokens.spaceSm),
              AppButton(
                key: const Key('quest-status-revert'),
                label: 'Revert',
                variant: AppButtonVariant.ghost,
                expand: true,
                onPressed: busy ? null : onRevert,
              ),
            ],
            if (current != null) ...[
              SizedBox(height: tokens.spaceSm),
              Text(
                current.manuallyCompleted
                    ? 'Completed by manual override. Objective counts were not '
                          'changed.'
                    : current.objectivesSatisfied
                    ? 'Every required objective is recorded; completion needs '
                          'no override.'
                    : 'Completing now needs confirmation and leaves objective '
                          'counts unchanged.',
                key: const Key('quest-status-hint'),
                style: tokens.bodyStyle.copyWith(color: tokens.muted),
              ),
            ],
          ],
        ],
      ),
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
    final tokens = AppTokens.of(context);
    final mergedId = itemId;
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spaceXs),
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: tokens.h2Size,
            color: tokens.dim,
          ),
          SizedBox(width: tokens.spaceSm),
          Expanded(
            child: Text(
              label,
              key: mergedId == null
                  ? null
                  : ValueKey('quest-item-label-$mergedId'),
              style: tokens.bodyStyle.copyWith(
                color: onTap == null ? tokens.text : tokens.info,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: tokens.dataStyle.copyWith(color: tokens.muted),
            ),
          if (onTap != null)
            Icon(Icons.chevron_right, size: tokens.h2Size, color: tokens.dim),
        ],
      ),
    );
    if (onTap == null) {
      return row;
    }
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: mergedId == null ? null : ValueKey('quest-item-link-$mergedId'),
        onTap: onTap,
        hoverColor: tokens.accent.withValues(alpha: 0.06),
        child: row,
      ),
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
    final tokens = AppTokens.of(context);
    final state = this.state;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        hoverColor: tokens.accent.withValues(alpha: 0.06),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: tokens.spaceXs),
          child: Row(
            children: [
              Icon(Icons.flag_outlined, size: tokens.h2Size, color: tokens.dim),
              SizedBox(width: tokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: tokens.bodyStyle),
                    Text(
                      detail,
                      style: tokens.bodyStyle.copyWith(color: tokens.muted),
                    ),
                  ],
                ),
              ),
              if (state != null) QuestStateBadge(state: state.recordedState),
              SizedBox(width: tokens.spaceXs),
              Icon(Icons.chevron_right, size: tokens.h2Size, color: tokens.dim),
            ],
          ),
        ),
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
    final tokens = AppTokens.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.help_outline, size: 48, color: tokens.dim),
            SizedBox(height: tokens.spaceMd),
            Text(
              'Quest not found',
              key: const Key('quest-detail-not-found'),
              textAlign: TextAlign.center,
              style: tokens.h2Style,
            ),
            SizedBox(height: tokens.spaceXs),
            Text(
              'Quest $questId is not in the current dataset.',
              textAlign: TextAlign.center,
              style: tokens.bodyStyle.copyWith(color: tokens.muted),
            ),
            SizedBox(height: tokens.spaceLg),
            AppButton(
              key: const Key('quest-detail-back'),
              label: 'Back',
              variant: AppButtonVariant.secondary,
              onPressed: onBack,
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
    final tokens = AppTokens.of(context);
    return SingleChildScrollView(
      key: const Key('quest-detail-orphaned'),
      padding: EdgeInsets.all(tokens.spaceXl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.link_off, color: tokens.danger),
                  SizedBox(width: tokens.spaceSm),
                  Expanded(
                    child: Text(
                      'Quest unavailable upstream',
                      style: tokens.h1Style,
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.spaceSm),
              Text(
                'Quest ${orphan.questId} is no longer in the current dataset. '
                'The progress recorded for this profile is preserved and is '
                'not used to satisfy other quests.',
                style: tokens.bodyStyle,
              ),
              SizedBox(height: tokens.spaceLg),
              const AppSectionLabel('Preserved state'),
              SizedBox(height: tokens.spaceXs),
              QuestStateBadge(
                key: const Key('quest-orphan-state'),
                state: orphan.state,
              ),
              if (orphan.objectiveCounts.isNotEmpty) ...[
                SizedBox(height: tokens.spaceLg),
                const AppSectionLabel('Recorded objective counts'),
                SizedBox(height: tokens.spaceXs),
                for (final entry in orphan.objectiveCounts.entries)
                  Text('${entry.key}: ${entry.value}', style: tokens.dataStyle),
              ],
              if (orphan.updatedAt != null) ...[
                SizedBox(height: tokens.spaceMd),
                Text(
                  'Last updated ${orphan.updatedAt}',
                  style: tokens.bodyStyle.copyWith(color: tokens.muted),
                ),
              ],
              SizedBox(height: tokens.spaceLg),
              AppButton(
                key: const Key('quest-orphan-back'),
                label: 'Back',
                variant: AppButtonVariant.secondary,
                onPressed: onBack,
              ),
            ],
          ),
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
    final status = UpstreamStatus.fromError(error);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppStatusStrip.upstream(
              key: const Key('quest-detail-upstream-error'),
              status: status,
              onRetry: onRetry,
            ),
            SizedBox(height: tokens.spaceLg),
            Text(
              'The saved quest could not be refreshed.',
              key: const Key('quest-detail-offline-title'),
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
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: tokens.danger),
            SizedBox(height: tokens.spaceMd),
            Text(
              'Could not load this quest.',
              key: const Key('quest-detail-error'),
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
              key: const Key('quest-detail-retry'),
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
