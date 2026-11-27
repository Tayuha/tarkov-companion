import 'package:material_ui/material_ui.dart';

import '../theme/app_primitives.dart';
import '../theme/app_tokens.dart';
import 'upstream_status.dart';

/// The intent of an [AppStatusStrip].
enum AppStatusStripKind {
  /// No usable connection; saved data is being shown.
  offline,

  /// The upstream answered with an error; saved data is being shown.
  upstreamError,

  /// Saved data is older than the freshness target.
  stale,

  /// A check is in flight; content stays visible.
  updating,
}

/// A non-blocking, tokenised status band for offline, upstream and stale data.
///
/// The strip sits in the normal layout above content. It never covers, replaces
/// or dims saved rows, and it never opens a dialog; the only action is an
/// optional retry. [AppStatusStrip.upstream] maps an [UpstreamStatus] to the
/// consistent wording and colour for each state.
class AppStatusStrip extends StatelessWidget {
  const AppStatusStrip({
    super.key,
    required this.kind,
    this.title,
    this.message,
    this.lastUpdatedAt,
    this.now,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.retryKey = const Key('app-status-retry'),
  });

  /// Builds the strip for a saved-data [status].
  ///
  /// [now] is injectable so the age readout is deterministic in tests.
  factory AppStatusStrip.upstream({
    Key? key,
    required UpstreamStatus status,
    DateTime? now,
    VoidCallback? onRetry,
    String retryLabel = 'Retry',
  }) {
    final ageAt = status.dataUpdatedAt;
    return switch (status.state) {
      UpstreamState.offline => AppStatusStrip(
        key: key,
        kind: AppStatusStripKind.offline,
        title: 'Offline',
        message:
            'Showing saved data. The update check could not reach the '
            'network; retry when a connection is available.',
        lastUpdatedAt: ageAt,
        now: now,
        onRetry: onRetry,
        retryLabel: retryLabel,
      ),
      UpstreamState.failed => AppStatusStrip(
        key: key,
        kind: AppStatusStripKind.upstreamError,
        title: 'Upstream unavailable',
        message: status.message == null
            ? 'Showing saved data. The update check failed; retry to try '
                  'again.'
            : 'Showing saved data. ${status.message}',
        lastUpdatedAt: ageAt,
        now: now,
        onRetry: onRetry,
        retryLabel: retryLabel,
      ),
      UpstreamState.stale => AppStatusStrip(
        key: key,
        kind: AppStatusStripKind.stale,
        title: 'Saved data',
        message:
            status.message ??
            'Showing saved data. The update check has not confirmed it is '
                'current.',
        lastUpdatedAt: ageAt,
        now: now,
        onRetry: onRetry,
        retryLabel: retryLabel,
      ),
      UpstreamState.current || UpstreamState.updateAvailable => AppStatusStrip(
        key: key,
        kind: AppStatusStripKind.updating,
        title: 'Up to date',
        message: 'The local dataset matches the last successful check.',
      ),
    };
  }

  final AppStatusStripKind kind;

  /// Overrides the default heading.
  final String? title;

  /// Overrides the default explanatory sentence.
  final String? message;

  /// When the shown data was saved; renders a relative age readout.
  final DateTime? lastUpdatedAt;

  /// Reference time for [lastUpdatedAt]; defaults to now.
  final DateTime? now;

  /// Retries the failed check; when `null` no action is rendered.
  final VoidCallback? onRetry;

  final String retryLabel;

  /// Key for the retry action, so a screen with two strips can target one.
  final Key retryKey;

  bool get _retryable => onRetry != null && kind != AppStatusStripKind.updating;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final colour = _colour(tokens);
    final heading = title ?? _defaultTitle();
    final body = message ?? _defaultMessage();
    final lastUpdatedAt = this.lastUpdatedAt;

    return Semantics(
      container: true,
      liveRegion: true,
      label: lastUpdatedAt == null
          ? '$heading. $body'
          : '$heading. $body Saved data ${formatStatusAge(lastUpdatedAt, now: now)}.',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spaceMd,
          vertical: tokens.spaceSm,
        ),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            colour.withValues(alpha: 0.10),
            tokens.surface,
          ),
          border: Border.all(color: colour.withValues(alpha: 0.55)),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon(), size: tokens.h2Size, color: colour),
            SizedBox(width: tokens.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    heading.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.labelStyle.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colour,
                    ),
                  ),
                  SizedBox(height: tokens.spaceXs),
                  Text(
                    body,
                    style: tokens.bodyStyle.copyWith(color: tokens.muted),
                  ),
                  if (lastUpdatedAt != null) ...[
                    SizedBox(height: tokens.spaceXs),
                    Text(
                      'Saved data ${formatStatusAge(lastUpdatedAt, now: now)}',
                      key: const Key('app-status-age'),
                      style: tokens.dataStyle.copyWith(color: tokens.dim),
                    ),
                  ],
                ],
              ),
            ),
            if (_retryable) ...[
              SizedBox(width: tokens.spaceMd),
              AppButton(
                key: retryKey,
                label: retryLabel,
                variant: AppButtonVariant.ghost,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _colour(AppTokens tokens) => switch (kind) {
    AppStatusStripKind.offline => tokens.danger,
    AppStatusStripKind.upstreamError => tokens.danger,
    AppStatusStripKind.stale => tokens.value,
    AppStatusStripKind.updating => tokens.info,
  };

  IconData _icon() => switch (kind) {
    AppStatusStripKind.offline => Icons.cloud_off_outlined,
    AppStatusStripKind.upstreamError => Icons.error_outline,
    AppStatusStripKind.stale => Icons.history,
    AppStatusStripKind.updating => Icons.sync,
  };

  String _defaultTitle() => switch (kind) {
    AppStatusStripKind.offline => 'Offline',
    AppStatusStripKind.upstreamError => 'Upstream unavailable',
    AppStatusStripKind.stale => 'Saved data',
    AppStatusStripKind.updating => 'Checking for updates',
  };

  String _defaultMessage() => switch (kind) {
    AppStatusStripKind.offline =>
      'Showing saved data. The update check could not reach the network.',
    AppStatusStripKind.upstreamError =>
      'Showing saved data. The update check failed.',
    AppStatusStripKind.stale =>
      'Showing saved data. The update check has not confirmed it is current.',
    AppStatusStripKind.updating =>
      'Showing saved data while the update check runs.',
  };
}

/// A short, deterministic relative age for status copy.
///
/// Future timestamps clamp to "just now"; the formatter never emits a negative
/// age. It is intentionally coarser than a clock: minutes, hours, then days.
String formatStatusAge(DateTime value, {DateTime? now}) {
  final reference = (now ?? DateTime.now()).toUtc();
  final then = value.toUtc();
  final difference = reference.difference(then);
  if (difference.isNegative || difference.inMinutes < 1) {
    return 'just now';
  }
  if (difference.inMinutes < 60) {
    return '${difference.inMinutes} min ago';
  }
  if (difference.inHours < 24) {
    return '${difference.inHours} h ago';
  }
  if (difference.inDays == 1) {
    return '1 day ago';
  }
  return '${difference.inDays} days ago';
}
