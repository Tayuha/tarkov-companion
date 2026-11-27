import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import '../theme/app_primitives.dart';
import '../theme/app_tokens.dart';
import 'progress_file_picker.dart';

/// Manage the local profiles: facts, activation, reset, deletion, export and
/// import.
///
/// The screen owns presentation state only. Every read and write goes through
/// [ProfileServices] in `tarkov_companion_data`; the native save/open dialog is
/// behind [ProgressFilePicker]. It never deletes anything without an explicit
/// confirmation and import defaults to a non-destructive merge.
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({
    super.key,
    required this.services,
    this.picker = const PlatformProgressFilePicker(),
    this.appVersion = '0.1.0',
    this.onProfileChanged,
  });

  /// Widest content column, matching the other screens.
  static const double maxContentWidth = 1200;

  final ProfileServices services;

  /// File-dialog seam; production uses the platform picker.
  final ProgressFilePicker picker;

  /// Written into exported documents.
  final String appVersion;

  /// Reports the active profile after a change so the shell can refresh the
  /// quest tab. `null` means the last profile was deleted.
  final ValueChanged<Profile?>? onProfileChanged;

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  List<Profile> _profiles = const [];
  String? _activeId;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _notice;

  ProgressExportDocument? _pendingImport;
  ProgressImportPreview? _pendingPreview;
  ProgressImportStrategy _strategy = ProgressImportStrategy.merge;
  final Map<String, ProgressConflictResolution> _resolutions = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final profiles = await widget.services.profiles.list();
      final active = await widget.services.profiles.active();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _activeId = active?.id;
        _loading = false;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load profiles: $error';
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _reportActive(Profile? profile) {
    widget.onProfileChanged?.call(profile);
  }

  Profile? get _activeProfile {
    for (final profile in _profiles) {
      if (profile.id == _activeId) return profile;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Profile actions
  // -------------------------------------------------------------------------

  Future<void> _activate(Profile profile) {
    return _run(() async {
      final activated = await widget.services.profiles.activate(profile.id);
      await _reload();
      setState(() => _notice = 'Activated ${_modeLabel(profile)}.');
      _reportActive(activated);
    });
  }

  Future<void> _create(GameMode mode) {
    return _run(() async {
      final result = await widget.services.profiles.createForMode(mode);
      await _reload();
      setState(() {
        _notice = result.created
            ? 'Created the ${_modeLabel(result.profile)} profile.'
            : 'The ${_modeLabel(result.profile)} profile already exists.';
      });
      _reportActive(await widget.services.profiles.active());
    });
  }

  Future<void> _editLevel(Profile profile) async {
    final controller = TextEditingController(text: '${profile.playerLevel}');
    final level = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('profile-level-dialog'),
        title: Text('Player level · ${_modeLabel(profile)}'),
        content: TextField(
          key: const Key('profile-level-field'),
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Level (1–99)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          AppButton(
            key: const Key('profile-level-cancel'),
            label: 'Cancel',
            variant: AppButtonVariant.ghost,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          AppButton(
            key: const Key('profile-level-save'),
            label: 'Save',
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value == null ||
                  !ProfileRepository.isValidPlayerLevel(value)) {
                return;
              }
              Navigator.of(dialogContext).pop(value);
            },
          ),
        ],
      ),
    );
    if (level == null) return;

    await _run(() async {
      await widget.services.profiles.updatePlayerLevel(profile.id, level);
      await _reload();
      setState(
        () => _notice = 'Saved level $level for ${_modeLabel(profile)}.',
      );
      _reportActive(await widget.services.profiles.active());
    });
  }

  Future<void> _reset(Profile profile) async {
    final confirmed = await _confirm(
      title: 'Reset ${_modeLabel(profile)} progress?',
      message:
          'Every recorded quest state and objective count for this profile '
          'will be deleted. The profile and its player level stay, and other '
          'profiles are not touched. This cannot be undone.',
      confirmKey: const Key('profile-confirm-reset'),
      confirmLabel: 'Reset progress',
      confirmVariant: AppButtonVariant.danger,
    );
    if (confirmed != true) return;

    await _run(() async {
      final result = await widget.services.profiles.resetProgress(profile.id);
      await _reload();
      setState(() {
        _notice = result.wasEmpty
            ? '${_modeLabel(profile)} already had no recorded progress.'
            : 'Cleared ${result.questStatesCleared} quest state(s) and '
                  '${result.objectiveCountsCleared} objective count(s).';
      });
      _reportActive(await widget.services.profiles.active());
    });
  }

  Future<void> _delete(Profile profile) async {
    final confirmed = await _confirm(
      title: 'Delete the ${_modeLabel(profile)} profile?',
      message:
          'The profile and all of its recorded progress will be deleted. '
          'Another profile becomes active when one exists. This cannot be '
          'undone.',
      confirmKey: const Key('profile-confirm-delete'),
      confirmLabel: 'Delete profile',
      confirmVariant: AppButtonVariant.danger,
    );
    if (confirmed != true) return;

    await _run(() async {
      final result = await widget.services.profiles.delete(profile.id);
      await _reload();
      setState(() {
        _notice = result.active == null
            ? 'Deleted the last profile. Create a profile to keep tracking.'
            : 'Deleted ${_modeLabel(profile)}; '
                  '${_modeLabel(result.active!)} is now active.';
      });
      _reportActive(result.active);
    });
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required Key confirmKey,
    required String confirmLabel,
    AppButtonVariant confirmVariant = AppButtonVariant.primary,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('profile-confirm-dialog'),
        title: Text(title),
        content: Text(message),
        actions: [
          AppButton(
            key: const Key('profile-confirm-cancel'),
            label: 'Cancel',
            variant: AppButtonVariant.ghost,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            key: confirmKey,
            label: confirmLabel,
            variant: confirmVariant,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Export and import
  // -------------------------------------------------------------------------

  Future<void> _export({required bool allProfiles}) async {
    final active = _activeProfile;
    final suffix = allProfiles
        ? 'all-profiles'
        : (active == null ? 'profile' : _modeSlug(active));
    final suggested =
        'tarkov-companion-$suffix-'
        '${_timestamp(DateTime.now())}.json';

    await _run(() async {
      final path = await widget.picker.chooseSavePath(suggestedName: suggested);
      if (path == null) return;
      final export = await widget.services.exporter.build(
        appVersion: widget.appVersion,
        allProfiles: allProfiles,
      );
      await export.writeTo(path);
      if (!mounted) return;
      setState(() {
        _error = null;
        _notice =
            'Exported ${export.document.questCount} quest state(s) and '
            '${export.document.objectiveCount} objective count(s) to '
            '${path.split(Platform.pathSeparator).last}.';
      });
    });
  }

  Future<void> _chooseImport() async {
    await _run(() async {
      final path = await widget.picker.chooseOpenPath();
      if (path == null) return;
      final text = await File(path).readAsString();
      final document = ProgressExportDocument.parse(text);
      final preview = await widget.services.importer.preview(document);
      if (!mounted) return;
      setState(() {
        _pendingImport = document;
        _pendingPreview = preview;
        _strategy = ProgressImportStrategy.merge;
        _resolutions.clear();
        _error = null;
        _notice = 'Previewing an import. Nothing has been written yet.';
      });
    });
  }

  Future<void> _applyImport() async {
    final document = _pendingImport;
    if (document == null) return;

    if (_strategy == ProgressImportStrategy.replace) {
      final confirmed = await _confirm(
        title: 'Replace progress?',
        message:
            'The target profile progress will be replaced by the file. The '
            'previous state is discarded only after the write succeeds. This '
            'cannot be undone.',
        confirmKey: const Key('import-confirm-replace'),
        confirmLabel: 'Replace progress',
        confirmVariant: AppButtonVariant.danger,
      );
      if (confirmed != true) return;
    }

    await _run(() async {
      final result = await widget.services.importer.apply(
        document,
        strategy: _strategy,
        resolutions: Map.of(_resolutions),
      );
      await _reload();
      if (!mounted) return;
      setState(() {
        _pendingImport = null;
        _pendingPreview = null;
        _resolutions.clear();
        _error = null;
        _notice =
            'Imported ${result.profilesCreated} new profile(s) and wrote '
            '${result.rowsWritten} progress row(s).';
      });
      _reportActive(await widget.services.profiles.active());
    });
  }

  void _cancelImport() {
    setState(() {
      _pendingImport = null;
      _pendingPreview = null;
      _resolutions.clear();
      _notice = 'Import cancelled. No data changed.';
    });
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Scaffold(
      key: const Key('profiles-screen'),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ProfilesScreen.maxContentWidth,
            ),
            child: Padding(
              padding: EdgeInsets.all(tokens.spaceLg),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        _Heading(profileCount: _profiles.length),
                        SizedBox(height: tokens.spaceLg),
                        if (_error != null) ...[
                          _Banner(
                            key: const Key('profiles-error'),
                            message: _error!,
                            tone: _BannerTone.error,
                          ),
                          SizedBox(height: tokens.spaceMd),
                        ],
                        if (_notice != null) ...[
                          _Banner(
                            key: const Key('profiles-notice'),
                            message: _notice!,
                            tone: _BannerTone.notice,
                          ),
                          SizedBox(height: tokens.spaceMd),
                        ],
                        _profilesPanel(tokens),
                        SizedBox(height: tokens.spaceLg),
                        _transferPanel(tokens),
                        if (_pendingPreview != null) ...[
                          SizedBox(height: tokens.spaceLg),
                          _importPreviewPanel(tokens, _pendingPreview!),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _profilesPanel(AppTokens tokens) {
    return AppPanel(
      label: 'Profiles',
      trailing: Text(
        '${_profiles.length} of ${GameMode.values.length} modes',
        style: tokens.dataStyle.copyWith(color: tokens.muted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < _profiles.length; index++) ...[
            if (index > 0) SizedBox(height: tokens.spaceMd),
            _profileCard(tokens, _profiles[index]),
          ],
          if (_profiles.isEmpty)
            Text(
              'No profiles exist. Create one to start tracking.',
              key: const Key('profiles-empty'),
              style: tokens.bodyStyle.copyWith(color: tokens.muted),
            ),
          SizedBox(height: tokens.spaceLg),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Add a profile for a game mode that has none.',
                  style: tokens.bodyStyle.copyWith(color: tokens.muted),
                ),
              ),
              const SizedBox(width: 12),
              Wrap(
                spacing: tokens.spaceSm,
                runSpacing: tokens.spaceSm,
                children: [
                  for (final mode in GameMode.values)
                    if (!_profiles.any(
                      (profile) => profile.gameMode == mode.wireValue,
                    ))
                      AppChip(
                        key: Key('profiles-create-${_modeSlugForMode(mode)}'),
                        label: 'Add ${_modeLabelForMode(mode)}',
                        onTap: _busy ? null : () => _create(mode),
                      ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileCard(AppTokens tokens, Profile profile) {
    final mode = profile.gameMode;
    final isActive = profile.id == _activeId;
    return Container(
      key: Key('profile-card-$mode'),
      padding: EdgeInsets.all(tokens.spaceLg),
      decoration: BoxDecoration(
        color: isActive ? tokens.accentDeep : tokens.surfaceRaised,
        border: Border.all(color: isActive ? tokens.accent : tokens.borderSoft),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _modeLabel(profile),
                      style: tokens.h2Style.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isActive ? tokens.accent : tokens.text,
                      ),
                    ),
                    SizedBox(height: tokens.spaceXs),
                    Row(
                      children: [
                        AppSectionLabel('Level'),
                        SizedBox(width: tokens.spaceSm),
                        Text(
                          '${profile.playerLevel}',
                          key: Key('profile-level-$mode'),
                          style: tokens.dataStyle.copyWith(color: tokens.text),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isActive)
                AppStatusBadge(
                  key: Key('profile-active-$mode'),
                  status: AppStatus.available,
                  label: 'Active',
                )
              else
                AppButton(
                  key: Key('profile-activate-$mode'),
                  label: 'Activate',
                  variant: AppButtonVariant.secondary,
                  onPressed: _busy ? null : () => _activate(profile),
                ),
            ],
          ),
          SizedBox(height: tokens.spaceMd),
          Wrap(
            spacing: tokens.spaceSm,
            runSpacing: tokens.spaceSm,
            children: [
              AppButton(
                key: Key('profile-edit-$mode'),
                label: 'Edit level',
                variant: AppButtonVariant.ghost,
                onPressed: _busy ? null : () => _editLevel(profile),
              ),
              AppButton(
                key: Key('profile-reset-$mode'),
                label: 'Reset progress',
                variant: AppButtonVariant.ghost,
                onPressed: _busy ? null : () => _reset(profile),
              ),
              AppButton(
                key: Key('profile-delete-$mode'),
                label: 'Delete',
                variant: AppButtonVariant.danger,
                onPressed: _busy ? null : () => _delete(profile),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _transferPanel(AppTokens tokens) {
    return AppPanel(
      label: 'Portability',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Export writes one JSON file with a checksum. Import validates the '
            'file first, shows a preview, and merges by default; replace asks '
            'for confirmation.',
            style: tokens.bodyStyle.copyWith(color: tokens.muted),
          ),
          SizedBox(height: tokens.spaceLg),
          Wrap(
            spacing: tokens.spaceSm,
            runSpacing: tokens.spaceSm,
            children: [
              AppButton(
                key: const Key('profiles-export-active'),
                label: 'Export active',
                variant: AppButtonVariant.secondary,
                onPressed: _busy || _activeProfile == null
                    ? null
                    : () => _export(allProfiles: false),
              ),
              AppButton(
                key: const Key('profiles-export-all'),
                label: 'Export all',
                variant: AppButtonVariant.ghost,
                onPressed: _busy ? null : () => _export(allProfiles: true),
              ),
              AppButton(
                key: const Key('profiles-import'),
                label: 'Import file',
                variant: AppButtonVariant.primary,
                onPressed: _busy ? null : _chooseImport,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _importPreviewPanel(AppTokens tokens, ProgressImportPreview preview) {
    final conflicting = preview.questConflicts.length;
    return AppPanel(
      key: const Key('import-preview'),
      label: 'Import preview',
      trailing: AppChip(
        key: const Key('import-strategy-chip'),
        label: _strategy == ProgressImportStrategy.merge ? 'Merge' : 'Replace',
        selected: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${preview.profileCount} profile(s) · '
            '${preview.questStateCount} quest state(s) · '
            '${preview.objectiveCount} objective count(s)',
            key: const Key('import-counts'),
            style: tokens.h2Style.copyWith(
              fontSize: tokens.bodySize,
              color: tokens.text,
            ),
          ),
          SizedBox(height: tokens.spaceSm),
          Text(
            '${preview.newQuestStates} new quest state(s), '
            '$conflicting conflict(s), '
            '${preview.newObjectiveCounts} new objective count(s), '
            '${preview.conflictingObjectiveCounts} count conflict(s). '
            'Nothing has been written yet.',
            key: const Key('import-conflict-summary'),
            style: tokens.bodyStyle.copyWith(color: tokens.muted),
          ),
          SizedBox(height: tokens.spaceMd),
          Wrap(
            spacing: tokens.spaceSm,
            runSpacing: tokens.spaceSm,
            children: [
              AppChip(
                key: const Key('import-mode-merge'),
                label: 'Merge (non-destructive)',
                selected: _strategy == ProgressImportStrategy.merge,
                onTap: () =>
                    setState(() => _strategy = ProgressImportStrategy.merge),
              ),
              AppChip(
                key: const Key('import-mode-replace'),
                label: 'Replace',
                selected: _strategy == ProgressImportStrategy.replace,
                onTap: () =>
                    setState(() => _strategy = ProgressImportStrategy.replace),
              ),
            ],
          ),
          if (_strategy == ProgressImportStrategy.merge &&
              preview.questConflicts.isNotEmpty) ...[
            SizedBox(height: tokens.spaceLg),
            AppSectionLabel('Merge conflicts'),
            SizedBox(height: tokens.spaceSm),
            for (final conflict in preview.questConflicts) ...[
              _conflictRow(tokens, conflict),
              SizedBox(height: tokens.spaceSm),
            ],
          ],
          SizedBox(height: tokens.spaceLg),
          Wrap(
            spacing: tokens.spaceSm,
            runSpacing: tokens.spaceSm,
            children: [
              AppButton(
                key: const Key('import-apply'),
                label: 'Apply import',
                onPressed: _busy ? null : _applyImport,
              ),
              AppButton(
                key: const Key('import-cancel'),
                label: 'Cancel',
                variant: AppButtonVariant.ghost,
                onPressed: _busy ? null : _cancelImport,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _conflictRow(AppTokens tokens, ProgressQuestConflict conflict) {
    final key = conflict.key;
    final selected = _resolutions[key] ?? ProgressConflictResolution.keepLocal;
    final slug = conflict.questId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
    return Container(
      padding: EdgeInsets.all(tokens.spaceMd),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border.all(color: tokens.borderSoft),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conflict.questId,
                  style: tokens.dataStyle.copyWith(color: tokens.text),
                ),
                SizedBox(height: tokens.spaceXs),
                Text(
                  'Local ${_stateLabel(conflict.localState)} · '
                  'File ${_stateLabel(conflict.importedState)}',
                  style: tokens.bodyStyle.copyWith(color: tokens.muted),
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.spaceMd),
          Wrap(
            spacing: tokens.spaceSm,
            children: [
              AppChip(
                key: Key('import-conflict-$slug-keep'),
                label: 'Keep local',
                selected: selected == ProgressConflictResolution.keepLocal,
                onTap: () => setState(
                  () =>
                      _resolutions[key] = ProgressConflictResolution.keepLocal,
                ),
              ),
              AppChip(
                key: Key('import-conflict-$slug-use'),
                label: 'Use file',
                selected: selected == ProgressConflictResolution.useImported,
                onTap: () => setState(
                  () => _resolutions[key] =
                      ProgressConflictResolution.useImported,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.profileCount});

  final int profileCount;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profiles',
                style: tokens.h1Style.copyWith(color: tokens.text),
              ),
              SizedBox(height: tokens.spaceXs),
              Text(
                'Player facts and portable progress. Everything stays on this '
                'device unless you export it.',
                style: tokens.bodyStyle.copyWith(color: tokens.muted),
              ),
            ],
          ),
        ),
        Text(
          '$profileCount PROFILE${profileCount == 1 ? '' : 'S'}',
          style: tokens.labelStyle.copyWith(color: tokens.muted),
        ),
      ],
    );
  }
}

enum _BannerTone { error, notice }

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.message, required this.tone});

  final String message;
  final _BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final color = tone == _BannerTone.error ? tokens.danger : tokens.info;
    return Container(
      padding: EdgeInsets.all(tokens.spaceMd),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.08), tokens.surface),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Text(message, style: tokens.bodyStyle.copyWith(color: color)),
    );
  }
}

String _modeLabel(Profile profile) {
  for (final mode in GameMode.values) {
    if (mode.wireValue == profile.gameMode) {
      return _modeLabelForMode(mode);
    }
  }
  return profile.gameMode;
}

String _modeLabelForMode(GameMode mode) => switch (mode) {
  GameMode.regular => 'Regular',
  GameMode.pve => 'PvE',
  GameMode.pvpSeason => 'PvP Season',
};

String _modeSlug(Profile profile) => profile.gameMode;

String _modeSlugForMode(GameMode mode) => mode.wireValue;

String _stateLabel(QuestProgressState state) => switch (state) {
  QuestProgressState.notStarted => 'not started',
  QuestProgressState.inProgress => 'in progress',
  QuestProgressState.completed => 'completed',
  QuestProgressState.failed => 'failed',
};

String _timestamp(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}${two(time.month)}${two(time.day)}-'
      '${two(time.hour)}${two(time.minute)}';
}
