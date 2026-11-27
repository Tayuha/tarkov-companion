import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import 'app_session.dart';
import 'deep_links.dart';
import 'home_shell.dart';

/// Opens a session. Injected so widget tests can start from a fake session.
typedef AppSessionOpener = Future<AppSession> Function();

/// Root widget of the desktop shell.
///
/// The database is opened once, asynchronously. The first frame is therefore
/// the neutral loading shell; as soon as the session is ready, a database with
/// at least one applied dataset renders [HomeShell] immediately from local
/// data. Only a database with no dataset at all shows the first-run gate, and
/// no update request happens before the user presses Start.
///
/// For an existing install the background update controller is started after
/// the first local frame. It never blocks that frame: a slow manifest, an
/// offline host or a failed download is reported in the shell footer.
class AppRoot extends StatefulWidget {
  const AppRoot({
    super.key,
    required this.openSession,
    this.deepLinks,
    this.progressFilePicker,
  });

  final AppSessionOpener openSession;

  /// Deep links waiting for the session (launch argument or a second launch).
  final DeepLinkInbox? deepLinks;

  /// File-dialog seam for profile export/import.
  ///
  /// Production omits it and the Profiles screen opens the platform dialog.
  /// The end-to-end widget test supplies a directory-backed picker because a
  /// native dialog cannot be driven headlessly.
  final ProgressFilePicker? progressFilePicker;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late Future<AppSession> _sessionFuture;
  AppSession? _session;
  bool _firstRunComplete = false;
  bool _deepLinkFrameScheduled = false;
  bool _updatesStarted = false;

  @override
  void initState() {
    super.initState();
    _sessionFuture = _open();
    widget.deepLinks?.addListener(_scheduleDeepLink);
  }

  @override
  void didUpdateWidget(AppRoot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deepLinks != widget.deepLinks) {
      oldWidget.deepLinks?.removeListener(_scheduleDeepLink);
      widget.deepLinks?.addListener(_scheduleDeepLink);
    }
  }

  Future<AppSession> _open() async {
    final session = await widget.openSession();
    if (!mounted) {
      // The widget was disposed while opening; release the handles.
      unawaited(session.close());
    } else {
      _session = session;
    }
    return session;
  }

  void _reload() {
    setState(() {
      _firstRunComplete = false;
      _updatesStarted = false;
      _sessionFuture = _open();
    });
  }

  /// Starts the background update check after the local frame is visible.
  ///
  /// This is deliberately not awaited and never part of the initial build:
  /// when local data exists the shell renders first, and a slow or failed
  /// manifest request is reported in the footer instead of replacing the
  /// window with a splash.
  void _ensureUpdatesStarted(AppSessionReady session) {
    if (_updatesStarted) {
      return;
    }
    final updates = session.updates;
    if (updates == null) {
      return;
    }
    _updatesStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        updates.start().catchError((Object error, StackTrace stackTrace) {
          // The controller persists failures for the status strip; a failure
          // here (for example a closed database) must not reach the zone
          // handler and take the shell down.
        }),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    widget.deepLinks?.removeListener(_scheduleDeepLink);
    final session = _session;
    if (session != null) {
      unawaited(session.close());
    }
    super.dispose();
  }

  /// Pushes one pending item deep link after the current frame.
  ///
  /// Waiting for the frame is required on the launch path: the link can arrive
  /// before the first session build, and `Navigator.push` cannot run during a
  /// build. Deep links wait for the first-run gate to finish so the item detail
  /// can pop back to a populated catalog.
  void _scheduleDeepLink() {
    if (_deepLinkFrameScheduled) {
      return;
    }
    _deepLinkFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deepLinkFrameScheduled = false;
      _openNextDeepLink();
    });
    // A deep link can arrive when nothing else is animating; make sure the
    // frame that runs the callback is actually scheduled.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _openNextDeepLink() {
    if (!mounted) {
      return;
    }
    final inbox = widget.deepLinks;
    final session = _session;
    if (inbox == null || session is! AppSessionReady) {
      return;
    }
    if (!session.hasAppliedDatasets && !_firstRunComplete) {
      return;
    }
    final catalog = session.catalog;
    if (catalog == null) {
      return;
    }
    final link = inbox.take();
    if (link == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ItemDetailScreen(repository: catalog, itemId: link.itemId),
      ),
    );
    if (inbox.hasPending) {
      _scheduleDeepLink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppSession>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StartupError(error: snapshot.error!, onRetry: _reload);
        }
        if (!snapshot.hasData) {
          return const _StartupLoading();
        }

        final session = snapshot.data!;
        return switch (session) {
          AppSessionRecovery recovery => _RecoveryScreen(recovery: recovery),
          AppSessionReady ready => _buildReady(ready),
        };
      },
    );
  }

  Widget _buildReady(AppSessionReady session) {
    if (!session.hasAppliedDatasets && !_firstRunComplete) {
      return FirstRunScreen(
        sync: session.sync,
        mode: GameMode.regular,
        onReady: (_) {
          if (!mounted) {
            return;
          }
          setState(() => _firstRunComplete = true);
          _scheduleDeepLink();
        },
      );
    }
    _ensureUpdatesStarted(session);
    if (widget.deepLinks?.hasPending ?? false) {
      _scheduleDeepLink();
    }
    return HomeShell(
      catalog: session.catalog,
      quests: session.quests,
      activeProfileId: session.activeProfileId,
      profileServices: session.profileServices,
      updates: session.updates,
      dataBundle: session.dataBundle,
      progressFilePicker: widget.progressFilePicker,
      upstreamCheck: _upstreamCheck(session),
      imageCache: session.imageCache,
    );
  }

  /// Deduplicates simultaneous upstream checks.
  ///
  /// The catalog and quests tabs are both built eagerly, and each attaches the
  /// check when it mounts. Sharing one in-flight future keeps that to a single
  /// manifest request, while a retry after completion starts a fresh check.
  Future<UpstreamStatus>? _upstreamInFlight;

  UpstreamCheck _upstreamCheck(AppSessionReady session) {
    return () {
      final running = _upstreamInFlight;
      if (running != null) {
        return running;
      }
      final future = _checkUpstream(session);
      _upstreamInFlight = future;
      return future.whenComplete(() {
        if (identical(_upstreamInFlight, future)) {
          _upstreamInFlight = null;
        }
      });
    };
  }

  Future<UpstreamStatus> _checkUpstream(AppSessionReady session) async {
    final checkedAt = DateTime.now().toUtc();
    final dataUpdatedAt = session.dataBundle?.newestAppliedAt;
    try {
      final preparation = await session.sync.prepare(GameMode.regular);
      if (preparation.datasetCount > 0) {
        return UpstreamStatus.updateAvailable(
          checkedAt: checkedAt,
          dataUpdatedAt: dataUpdatedAt,
        );
      }
      return UpstreamStatus.current(
        checkedAt: checkedAt,
        dataUpdatedAt: dataUpdatedAt,
      );
    } on Object catch (error) {
      return UpstreamStatus.fromError(
        error,
        checkedAt: checkedAt,
        dataUpdatedAt: dataUpdatedAt,
      );
    }
  }
}

/// The neutral first frame while the database opens.
class _StartupLoading extends StatelessWidget {
  const _StartupLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Opening Tarkov Companion…'),
          ],
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tarkov Companion')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  'The app could not start',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stable keys for the recovery screen.
abstract final class RecoveryKeys {
  static const Key screen = Key('recovery-screen');
  static const Key exportProgress = Key('recovery-export-progress');
  static const Key exportDiagnostics = Key('recovery-export-diagnostics');
  static const Key progressPath = Key('recovery-progress-path');
  static const Key progressChecksum = Key('recovery-progress-checksum');
  static const Key progressCounts = Key('recovery-progress-counts');
  static const Key diagnosticsPath = Key('recovery-diagnostics-path');
  static const Key error = Key('recovery-error');
}

class _RecoveryScreen extends StatefulWidget {
  const _RecoveryScreen({required this.recovery});

  final AppSessionRecovery recovery;

  @override
  State<_RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<_RecoveryScreen> {
  bool _exportingProgress = false;
  bool _exportingDiagnostics = false;
  RecoveryProgressFile? _progress;
  RecoveryDiagnosticsCopy? _diagnostics;
  String? _diagnosticsMessage;
  String? _error;

  bool get _busy => _exportingProgress || _exportingDiagnostics;

  Future<void> _exportProgress() async {
    setState(() {
      _exportingProgress = true;
      _error = null;
    });
    try {
      final exporter = RecoveryProgressExporter(
        widget.recovery.recoveryDatabase,
      );
      final result = await exporter.writeTo(
        appVersion: widget.recovery.appVersion,
        directory: widget.recovery.exportDirectory,
      );
      if (!mounted) return;
      setState(() => _progress = result);
    } on NoRecoveryProfilesError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No progress was exported. ${error.reasons.join(' ')}';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = 'The progress export failed: $error');
    } finally {
      if (mounted) setState(() => _exportingProgress = false);
    }
  }

  Future<void> _exportDiagnostics() async {
    setState(() {
      _exportingDiagnostics = true;
      _error = null;
    });
    try {
      final result = await exportRecoveryDiagnostics(
        directory: widget.recovery.exportDirectory,
        logsDirectory: widget.recovery.logsDirectory,
        backup: widget.recovery.backup,
      );
      if (!mounted) return;
      setState(() {
        _diagnostics = result;
        _diagnosticsMessage = result.isEmpty
            ? 'No backup or log files were available to copy.'
            : 'Copied ${result.copiedFileCount} diagnostics '
                  '${result.copiedFileCount == 1 ? 'file' : 'files'}.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = 'The diagnostics export failed: $error');
    } finally {
      if (mounted) setState(() => _exportingDiagnostics = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final recovery = widget.recovery;
    final progress = _progress;
    final diagnostics = _diagnostics;
    final error = _error;
    final diagnosticsMessage = _diagnosticsMessage;

    return Scaffold(
      key: RecoveryKeys.screen,
      appBar: AppBar(title: const Text('Tarkov Companion')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(tokens.spaceXl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      size: 32,
                      color: tokens.danger,
                    ),
                    SizedBox(width: tokens.spaceMd),
                    Text('Local database recovery', style: tokens.h1Style),
                  ],
                ),
                SizedBox(height: tokens.spaceMd),
                Text(recovery.message, style: tokens.bodyStyle),
                SizedBox(height: tokens.spaceLg),
                AppPanel(
                  label: 'Read-only state',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _RecoveryInfoRow(
                        label: 'Detected schema version',
                        value: '${recovery.detectedVersion}',
                      ),
                      _RecoveryInfoRow(
                        label: 'Failure',
                        value: '${recovery.failure}',
                      ),
                      SizedBox(height: tokens.spaceSm),
                      Text(
                        'The database file was left untouched. The app keeps '
                        'one read-only SQLite handle open until it closes, and '
                        'no write action is offered. Exports read the existing '
                        'rows through that handle.',
                        style: tokens.bodyStyle.copyWith(color: tokens.muted),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: tokens.spaceLg),
                AppPanel(
                  label: 'Export',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: tokens.spaceMd,
                        runSpacing: tokens.spaceSm,
                        children: [
                          AppButton(
                            key: RecoveryKeys.exportProgress,
                            label: 'Export progress',
                            onPressed: _busy ? null : _exportProgress,
                          ),
                          AppButton(
                            key: RecoveryKeys.exportDiagnostics,
                            label: 'Export diagnostics',
                            variant: AppButtonVariant.secondary,
                            onPressed: _busy ? null : _exportDiagnostics,
                          ),
                        ],
                      ),
                      if (error != null) ...[
                        SizedBox(height: tokens.spaceMd),
                        Text(
                          error,
                          key: RecoveryKeys.error,
                          style: tokens.bodyStyle.copyWith(
                            color: tokens.danger,
                          ),
                        ),
                      ],
                      if (diagnosticsMessage != null) ...[
                        SizedBox(height: tokens.spaceMd),
                        Text(diagnosticsMessage, style: tokens.bodyStyle),
                      ],
                      if (diagnostics != null) ...[
                        SizedBox(height: tokens.spaceXs),
                        Text(
                          diagnostics.directory.path,
                          key: RecoveryKeys.diagnosticsPath,
                          style: tokens.dataStyle.copyWith(color: tokens.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                if (progress != null) ...[
                  SizedBox(height: tokens.spaceLg),
                  AppPanel(
                    label: 'Progress export',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          progress.file.path,
                          key: RecoveryKeys.progressPath,
                          style: tokens.dataStyle,
                        ),
                        SizedBox(height: tokens.spaceSm),
                        Text(
                          '${progress.export.document.profiles.length} '
                          '${progress.export.document.profiles.length == 1 ? 'profile' : 'profiles'} · '
                          '${progress.export.document.questCount} quest '
                          '${progress.export.document.questCount == 1 ? 'state' : 'states'} · '
                          '${progress.export.document.objectiveCount} objective '
                          '${progress.export.document.objectiveCount == 1 ? 'count' : 'counts'}',
                          key: RecoveryKeys.progressCounts,
                          style: tokens.bodyStyle,
                        ),
                        SizedBox(height: tokens.spaceXs),
                        Text(
                          'Checksum ${_shortChecksum(progress.export.checksum)}',
                          key: RecoveryKeys.progressChecksum,
                          style: tokens.dataStyle.copyWith(color: tokens.value),
                        ),
                        SizedBox(height: tokens.spaceSm),
                        Text(
                          progress.diagnostics.isExact
                              ? 'Every readable row was exported exactly.'
                              : 'Skipped ${progress.diagnostics.skippedRows} '
                                    'unreadable row(s); clamped '
                                    '${progress.diagnostics.normalizedRows} '
                                    'out-of-range value(s).',
                          style: tokens.bodyStyle.copyWith(
                            color: progress.diagnostics.isExact
                                ? tokens.muted
                                : tokens.danger,
                          ),
                        ),
                        SizedBox(height: tokens.spaceSm),
                        Text(
                          'Copy the path above to open the export folder.',
                          style: tokens.bodyStyle.copyWith(color: tokens.muted),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: tokens.spaceLg),
                Text(
                  'Writes are refused by SQLite, and the recovery handle stays '
                  'open until the app closes.',
                  style: tokens.bodyStyle.copyWith(color: tokens.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _shortChecksum(String checksum) {
    const prefix = 'sha256:';
    final digits = checksum.startsWith(prefix)
        ? checksum.substring(prefix.length)
        : checksum;
    final short = digits.length <= 12 ? digits : digits.substring(0, 12);
    return 'sha256:$short…';
  }
}

class _RecoveryInfoRow extends StatelessWidget {
  const _RecoveryInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 180, child: AppSectionLabel(label)),
          SizedBox(width: tokens.spaceMd),
          Expanded(child: Text(value, style: tokens.dataStyle)),
        ],
      ),
    );
  }
}
