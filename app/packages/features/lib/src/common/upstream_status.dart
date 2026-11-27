import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

/// The outcome of one upstream check, independent of the network client.
///
/// A screen never performs I/O itself: it accepts an [UpstreamCheck], runs it
/// after the local query has already produced rows, and renders the result
/// with `AppStatusStrip`. The production shell can adapt the data package's
/// `SyncService.prepare` to this type; tests pass a closure that fails, so no
/// extra network stack is introduced in the feature layer.
enum UpstreamState {
  /// The upstream is reachable and the local dataset is current.
  current,

  /// The upstream is reachable and a newer dataset is available.
  updateAvailable,

  /// Local data is being shown although it is older than the freshness target.
  stale,

  /// No usable connection: DNS, connect, or a request timeout failed.
  offline,

  /// The upstream answered, but the check failed for another reason.
  failed,
}

/// One check result.
///
/// `checkedAt` is when the check ran, `dataUpdatedAt` is when the local dataset
/// was last applied. The latter drives the "saved data from 3 days ago" age in
/// the status strip.
final class UpstreamStatus {
  const UpstreamStatus._({
    required this.state,
    this.checkedAt,
    this.dataUpdatedAt,
    this.message,
    this.cause,
  });

  /// The local dataset matches the upstream.
  const UpstreamStatus.current({DateTime? checkedAt, DateTime? dataUpdatedAt})
    : this._(
        state: UpstreamState.current,
        checkedAt: checkedAt,
        dataUpdatedAt: dataUpdatedAt,
      );

  /// The upstream has a newer dataset than the one applied locally.
  const UpstreamStatus.updateAvailable({
    DateTime? checkedAt,
    DateTime? dataUpdatedAt,
  }) : this._(
         state: UpstreamState.updateAvailable,
         checkedAt: checkedAt,
         dataUpdatedAt: dataUpdatedAt,
       );

  /// The local dataset is older than the freshness target.
  const UpstreamStatus.stale({
    DateTime? checkedAt,
    DateTime? dataUpdatedAt,
    String? message,
  }) : this._(
         state: UpstreamState.stale,
         checkedAt: checkedAt,
         dataUpdatedAt: dataUpdatedAt,
         message: message,
       );

  /// The upstream could not be reached.
  const UpstreamStatus.offline({
    DateTime? checkedAt,
    DateTime? dataUpdatedAt,
    String? message,
    Object? cause,
  }) : this._(
         state: UpstreamState.offline,
         checkedAt: checkedAt,
         dataUpdatedAt: dataUpdatedAt,
         message: message,
         cause: cause,
       );

  /// The check failed for a reason other than connectivity.
  const UpstreamStatus.failed({
    required String message,
    DateTime? checkedAt,
    DateTime? dataUpdatedAt,
    Object? cause,
  }) : this._(
         state: UpstreamState.failed,
         checkedAt: checkedAt,
         dataUpdatedAt: dataUpdatedAt,
         message: message,
         cause: cause,
       );

  /// Classifies a thrown check failure without hiding its cause.
  factory UpstreamStatus.fromError(
    Object error, {
    DateTime? checkedAt,
    DateTime? dataUpdatedAt,
  }) {
    if (error is SyncException) {
      if (error.failure == SyncFailure.offline) {
        return UpstreamStatus.offline(
          checkedAt: checkedAt,
          dataUpdatedAt: dataUpdatedAt,
          message: error.message,
          cause: error,
        );
      }
      return UpstreamStatus.failed(
        checkedAt: checkedAt,
        dataUpdatedAt: dataUpdatedAt,
        message: error.message,
        cause: error,
      );
    }
    if (error is SocketException || error is HttpTimeoutException) {
      return UpstreamStatus.offline(
        checkedAt: checkedAt,
        dataUpdatedAt: dataUpdatedAt,
        message: '$error',
        cause: error,
      );
    }
    return UpstreamStatus.failed(
      checkedAt: checkedAt,
      dataUpdatedAt: dataUpdatedAt,
      message: '$error',
      cause: error,
    );
  }

  final UpstreamState state;

  /// When the check ran.
  final DateTime? checkedAt;

  /// When the applied local dataset was written.
  final DateTime? dataUpdatedAt;

  /// Optional detail; never used in place of the built-in status copy.
  final String? message;

  /// The error that produced this status, for diagnostics.
  final Object? cause;

  /// Whether the upstream is unreachable or errored.
  bool get isProblem =>
      state == UpstreamState.offline || state == UpstreamState.failed;

  /// Whether the status is worth a non-blocking strip above saved data.
  ///
  /// A current dataset and a merely available update stay quiet; the shell's
  /// update controls own those outcomes.
  bool get needsBanner =>
      state == UpstreamState.offline ||
      state == UpstreamState.failed ||
      state == UpstreamState.stale;
}

/// Whether [error] came from an upstream or sync operation rather than a
/// local read.
///
/// Detail routes use this to show the offline copy on a sync failure while a
/// corrupt local row still gets the generic error state.
bool isUpstreamError(Object error) =>
    error is SyncException ||
    error is SocketException ||
    error is HttpTimeoutException;

/// Runs one upstream check.
///
/// Production adapts `SyncService.prepare`; tests throw or return a fixed
/// [UpstreamStatus]. A thrown error is classified with
/// [UpstreamStatus.fromError].
typedef UpstreamCheck = Future<UpstreamStatus> Function();

/// Tracks the latest [UpstreamCheck] without blocking local content.
///
/// The controller is a plain [ChangeNotifier] so a screen can listen and
/// rebuild only its status strip. Overlapping checks are generation-guarded:
/// an older response never overwrites a newer retry.
final class UpstreamStatusController extends ChangeNotifier {
  UpstreamStatusController({required this.check});

  final UpstreamCheck check;

  UpstreamStatus? _status;
  bool _checking = false;
  int _generation = 0;
  bool _disposed = false;

  /// The most recent result, or `null` before the first check finishes.
  UpstreamStatus? get status => _status;

  /// Whether a check is in flight.
  bool get isChecking => _checking;

  /// Runs [check] and records the result.
  ///
  /// The returned future completes after the listeners are notified. Calling
  /// it again before the previous result arrives discards the older result.
  Future<void> refresh() async {
    final generation = ++_generation;
    _checking = true;
    notifyListeners();

    UpstreamStatus result;
    try {
      result = await check();
    } on Object catch (error) {
      result = UpstreamStatus.fromError(error, checkedAt: DateTime.now());
    }

    if (_disposed || generation != _generation) {
      return;
    }
    _status = result;
    _checking = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
