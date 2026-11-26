import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

/// Stable keys for the first-run states and actions.
abstract final class FirstRunKeys {
  static const Key loading = Key('first-run-loading');
  static const Key estimate = Key('first-run-estimate');
  static const Key downloading = Key('first-run-downloading');
  static const Key cancelling = Key('first-run-cancelling');
  static const Key error = Key('first-run-error');
  static const Key ready = Key('first-run-ready');

  static const Key overallProgress = Key('first-run-overall-progress');
  static const Key datasetProgress = Key('first-run-dataset-progress');

  static const Key startButton = Key('first-run-start');
  static const Key cancelButton = Key('first-run-cancel');
  static const Key retryButton = Key('first-run-retry');
}

/// The visible state of the first-run gate.
enum FirstRunStage {
  preparing,
  estimate,
  downloading,
  cancelling,
  failed,
  ready,
}

/// The first-run data gate.
///
/// The screen never downloads on its own: [SyncService.prepare] fetches the
/// manifest and returns an estimate, the user presses Start, and only then is
/// [SyncService.run] called. Cancel is always available during a download, and
/// Retry re-runs `prepare`, so datasets already recorded as applied are skipped
/// instead of downloaded again.
class FirstRunScreen extends StatefulWidget {
  const FirstRunScreen({
    super.key,
    required this.sync,
    this.mode = GameMode.regular,
    this.onReady,
  });

  final SyncService sync;
  final GameMode mode;

  /// Called after the last dataset was applied (or when nothing needed
  /// downloading). The app shell uses it to replace the gate with the home
  /// screen.
  final ValueChanged<SyncRunResult>? onReady;

  @override
  State<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends State<FirstRunScreen> {
  FirstRunStage _stage = FirstRunStage.preparing;
  SyncPreparation? _preparation;
  SyncProgress? _progress;
  SyncException? _error;
  DownloadCancellationToken? _cancellation;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    setState(() {
      _stage = FirstRunStage.preparing;
      _progress = null;
      _error = null;
      _cancellation = null;
    });

    try {
      final preparation = await widget.sync.prepare(widget.mode);
      if (!mounted) {
        return;
      }

      if (preparation.isComplete) {
        setState(() {
          _preparation = preparation;
          _stage = FirstRunStage.ready;
        });
        widget.onReady?.call(
          SyncRunResult(
            mode: preparation.mode,
            applied: const [],
            skipped: preparation.applied,
            bytesDownloaded: 0,
            completedAt: preparation.checkedAt,
          ),
        );
        return;
      }

      setState(() {
        _preparation = preparation;
        _stage = FirstRunStage.estimate;
      });
    } on SyncException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _stage = FirstRunStage.failed;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = SyncDownloadException(
          mode: widget.mode,
          message: 'The first-run data check failed unexpectedly: $error',
          cause: error,
        );
        _stage = FirstRunStage.failed;
      });
    }
  }

  Future<void> _start() async {
    final preparation = _preparation;
    if (preparation == null) {
      await _prepare();
      return;
    }

    final cancellation = DownloadCancellationToken();
    setState(() {
      _stage = FirstRunStage.downloading;
      _progress = null;
      _error = null;
      _cancellation = cancellation;
    });

    try {
      final result = await widget.sync.run(
        widget.mode,
        preparation: preparation,
        cancellation: cancellation,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() => _progress = progress);
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _stage = FirstRunStage.ready;
        _cancellation = null;
      });
      widget.onReady?.call(result);
    } on SyncException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _cancellation = null;
        _stage = FirstRunStage.failed;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = SyncDownloadException(
          mode: widget.mode,
          message: 'The data download failed unexpectedly: $error',
          cause: error,
        );
        _cancellation = null;
        _stage = FirstRunStage.failed;
      });
    }
  }

  void _cancel() {
    if (_stage != FirstRunStage.downloading) {
      return;
    }
    setState(() => _stage = FirstRunStage.cancelling);
    _cancellation?.cancel();
  }

  void _retry() {
    // A fresh prepare is what makes Retry resume: datasetState tells the
    // coordinator which datasets already made it in.
    _prepare();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tarkov Companion')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _buildBody(context),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return switch (_stage) {
      FirstRunStage.preparing => _buildLoading(),
      FirstRunStage.estimate => _buildEstimate(context),
      FirstRunStage.downloading => _buildDownloading(context),
      FirstRunStage.cancelling => _buildCancelling(),
      FirstRunStage.failed => _buildError(context),
      FirstRunStage.ready => _buildReady(),
    };
  }

  Widget _buildLoading() {
    return Column(
      key: FirstRunKeys.loading,
      mainAxisSize: MainAxisSize.min,
      children: const [
        CircularProgressIndicator(),
        SizedBox(height: 20),
        Text('Checking for game data…'),
        SizedBox(height: 8),
        Text(
          'This asks the data server what needs to be downloaded. It only '
          'takes a moment.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildEstimate(BuildContext context) {
    final preparation = _preparation;
    if (preparation == null) {
      return _buildLoading();
    }
    final size = _formatBytes(preparation.totalBytes);
    final count = preparation.datasetCount;

    return Column(
      key: FirstRunKeys.estimate,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Download game data to get started',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          'Tarkov Companion keeps a complete copy of the item, quest, and map '
          'data on this device, so it works offline and answers instantly. '
          'The first download is about $size across $count '
          '${count == 1 ? 'dataset' : 'datasets'}.',
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Needed for this device',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final dataset in preparation.pending)
                  _DatasetLine(
                    label: _datasetLabel(dataset.dataset),
                    bytes: dataset.compressedBytes,
                  ),
                const Divider(height: 24),
                _DatasetLine(label: 'Total', bytes: preparation.totalBytes),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'You can cancel at any time. A cancelled or failed download resumes '
          'from the datasets that already finished; nothing is half-applied.',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: FirstRunKeys.startButton,
          onPressed: _start,
          icon: const Icon(Icons.download),
          label: const Text('Start download'),
        ),
      ],
    );
  }

  Widget _buildDownloading(BuildContext context) {
    final preparation = _preparation;
    final progress = _progress;
    final total = preparation?.totalBytes ?? 0;
    final overallBytes = progress?.overallBytes ?? 0;
    final dataset = progress?.dataset;
    final phase = progress?.phase;

    return Column(
      key: FirstRunKeys.downloading,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Downloading game data',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Keep the app open. You can cancel and resume later without losing '
          'the datasets that are already installed.',
        ),
        const SizedBox(height: 24),
        LinearProgressIndicator(
          key: FirstRunKeys.overallProgress,
          value: progress?.fraction,
        ),
        const SizedBox(height: 8),
        Text('${_formatBytes(overallBytes)} of ${_formatBytes(total)}'),
        const SizedBox(height: 24),
        if (progress != null && dataset != null && phase != null) ...[
          Text(
            phase == SyncPhase.ingesting
                ? 'Installing ${_datasetLabel(dataset)}'
                : 'Downloading ${_datasetLabel(dataset)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text('Dataset ${progress.datasetNumber} of ${progress.datasetCount}'),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            key: FirstRunKeys.datasetProgress,
            value: progress.datasetFraction,
          ),
          if (phase == SyncPhase.ingesting)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${progress.recordsProcessed} of ${progress.recordsTotal} '
                'records installed',
              ),
            ),
        ] else
          const Text('Preparing the first download…'),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          key: FirstRunKeys.cancelButton,
          onPressed: _cancel,
          icon: const Icon(Icons.close),
          label: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildCancelling() {
    return Column(
      key: FirstRunKeys.cancelling,
      mainAxisSize: MainAxisSize.min,
      children: const [
        CircularProgressIndicator(),
        SizedBox(height: 20),
        Text('Cancelling…'),
        SizedBox(height: 8),
        Text(
          'The current download is being stopped. No partial data is kept; '
          'datasets that already finished stay installed.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    final error = _error;
    final cancelled = error?.failure == SyncFailure.cancelled;
    final preparation = _preparation;

    return Column(
      key: FirstRunKeys.error,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          cancelled ? Icons.pause_circle_outline : Icons.cloud_off,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 12),
        Text(
          cancelled ? 'Download cancelled' : 'Could not get the game data',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          cancelled
              ? 'Browsing needs game data. Nothing partial was kept, and any '
                    'datasets that finished are still installed.'
              : error?.message ?? 'The data download did not finish.',
        ),
        if (preparation != null && preparation.pending.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '${_formatBytes(preparation.totalBytes)} across '
            '${preparation.datasetCount} '
            '${preparation.datasetCount == 1 ? 'dataset' : 'datasets'} are '
            'still needed.',
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          key: FirstRunKeys.retryButton,
          onPressed: _retry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }

  Widget _buildReady() {
    return const Column(
      key: FirstRunKeys.ready,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline, size: 56),
        SizedBox(height: 16),
        Text('Game data is ready'),
        SizedBox(height: 8),
        Text('Opening Tarkov Companion…', textAlign: TextAlign.center),
      ],
    );
  }
}

class _DatasetLine extends StatelessWidget {
  const _DatasetLine({required this.label, required this.bytes});

  final String label;
  final int bytes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text(_formatBytes(bytes))],
      ),
    );
  }
}

String _datasetLabel(DatasetKind dataset) {
  return switch (dataset) {
    DatasetKind.items => 'Items',
    DatasetKind.tasks => 'Quests and tasks',
    DatasetKind.traders => 'Traders',
    DatasetKind.hideout => 'Hideout',
    DatasetKind.crafts => 'Crafts',
    DatasetKind.barters => 'Barters',
    DatasetKind.maps => 'Maps',
  };
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
