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
/// The database and network are opened once, asynchronously. The first frame is
/// therefore always the neutral loading shell; the first-run gate appears only
/// after the local database confirms there is no applied dataset. No manifest
/// request happens until the user presses Start.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.openSession, this.deepLinks});

  final AppSessionOpener openSession;

  /// Deep links waiting for the session (launch argument or a second launch).
  final DeepLinkInbox? deepLinks;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late Future<AppSession> _sessionFuture;
  AppSession? _session;
  bool _firstRunComplete = false;
  bool _deepLinkFrameScheduled = false;

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
      _sessionFuture = _open();
    });
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
    if (widget.deepLinks?.hasPending ?? false) {
      _scheduleDeepLink();
    }
    return HomeShell(
      catalog: session.catalog,
      quests: session.quests,
      activeProfileId: session.activeProfileId,
    );
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

class _RecoveryScreen extends StatelessWidget {
  const _RecoveryScreen({required this.recovery});

  final AppSessionRecovery recovery;

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
                  Icons.warning_amber_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  'Local database recovery',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(recovery.message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                const Text(
                  'No data was deleted. Export and recovery actions arrive in '
                  'the release-readiness task.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
