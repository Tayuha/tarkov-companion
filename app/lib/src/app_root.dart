import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import 'app_session.dart';

/// Opens a session. Injected so widget tests can start from a fake session.
typedef AppSessionOpener = Future<AppSession> Function();

/// Root widget of the desktop shell.
///
/// The database and network are opened once, asynchronously. The first frame is
/// therefore always the neutral loading shell; the first-run gate appears only
/// after the local database confirms there is no applied dataset. No manifest
/// request happens until the user presses Start.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.openSession});

  final AppSessionOpener openSession;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late Future<AppSession> _sessionFuture;
  AppSession? _session;
  bool _firstRunComplete = false;

  @override
  void initState() {
    super.initState();
    _sessionFuture = _open();
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
    final session = _session;
    if (session != null) {
      unawaited(session.close());
    }
    super.dispose();
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
        },
      );
    }
    return HomePlaceholder(
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

/// Landing screen once data is available.
///
/// The catalog and quest list are reachable when a real database is open; the
/// final navigation shell arrives in a later task.
class HomePlaceholder extends StatelessWidget {
  const HomePlaceholder({
    super.key,
    this.catalog,
    this.quests,
    this.activeProfileId,
  });

  /// Query facade for the catalog. Null in shell tests that build a session
  /// without SQLite.
  final CatalogRepository? catalog;

  /// Query facade for the quest list. Null in shell tests without SQLite.
  final QuestRepository? quests;

  /// Profile whose progress supplies quest state badges.
  final String? activeProfileId;

  @override
  Widget build(BuildContext context) {
    final catalog = this.catalog;
    final quests = this.quests;
    return Scaffold(
      appBar: AppBar(title: const Text('Tarkov Companion')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  title: 'Game data is ready',
                  subtitle:
                      'The local dataset is installed. Everything here is '
                      'served from the local database.',
                ),
                const SizedBox(height: 16),
                Text(
                  'This build opens without a network connection. The quest '
                  'list and the full navigation shell arrive in later tasks.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (catalog != null || quests != null) ...[
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (catalog != null)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CatalogScreen(
                                  repository: catalog,
                                  onItemSelected: (id) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => ItemDetailScreen(
                                          repository: catalog,
                                          itemId: id,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: const Text('Browse items'),
                        ),
                      if (quests != null)
                        FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => QuestListScreen(
                                  repository: quests,
                                  profileId: activeProfileId,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.checklist_outlined),
                          label: const Text('Quests'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
