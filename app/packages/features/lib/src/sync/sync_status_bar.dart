import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import '../theme/app_primitives.dart';
import '../theme/app_tokens.dart';

/// Stable keys for the update-status strip.
abstract final class SyncStatusKeys {
  static const Key bar = Key('sync-status-bar');
  static const Key label = Key('sync-status-label');
  static const Key detail = Key('sync-status-detail');
  static const Key progress = Key('sync-progress');
  static const Key checkNow = Key('sync-check-now');
  static const Key schedule = Key('sync-schedule');
  static const Key about = Key('sync-about');

  static Key scheduleOption(UpdateSchedule schedule) =>
      Key('sync-schedule-${schedule.wireValue}');
}

/// The non-modal update status and controls shown in the shell footer.
///
/// It never opens a dialog. Progress is a thin bar above the strip, failures
/// are a danger-coloured line, and `Check now` starts a manual check through
/// [UpdateCheckControl] without blocking the rest of the window.
class SyncStatusBar extends StatefulWidget {
  const SyncStatusBar({
    super.key,
    required this.control,
    this.onAbout,
    this.now,
  });

  /// The update controller owned by the app session.
  final UpdateCheckControl control;

  /// Opens the About screen. The footer supplies this from the shell.
  final VoidCallback? onAbout;

  /// Test seam for deterministic relative times.
  final DateTime Function()? now;

  @override
  State<SyncStatusBar> createState() => _SyncStatusBarState();
}

class _SyncStatusBarState extends State<SyncStatusBar> {
  late UpdateCheckStatus _status = widget.control.status;
  StreamSubscription<UpdateCheckStatus>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant SyncStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.control != widget.control) {
      _subscription?.cancel();
      _status = widget.control.status;
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = widget.control.changes.listen((status) {
      if (!mounted) {
        return;
      }
      setState(() => _status = status);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final status = _status;
    final detail = _detailText(status);

    return Container(
      key: SyncStatusKeys.bar,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.borderSoft)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spaceLg,
        vertical: tokens.spaceSm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status.isChecking)
            Padding(
              padding: EdgeInsets.only(bottom: tokens.spaceSm),
              child: AppProgressBar(
                key: SyncStatusKeys.progress,
                value: status.progress ?? 0,
                label: 'Checking for data updates',
                trailing: status.progress == null
                    ? 'Working…'
                    : '${(status.progress! * 100).round()}%',
              ),
            ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: tokens.spaceMd,
            runSpacing: tokens.spaceSm,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _icon(status),
                      size: tokens.h2Size,
                      color: _statusColor(tokens, status),
                    ),
                    SizedBox(width: tokens.spaceSm),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _label(status),
                            key: SyncStatusKeys.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.bodyStyle.copyWith(
                              color: _statusColor(tokens, status),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (detail != null)
                            Text(
                              detail,
                              key: SyncStatusKeys.detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tokens.labelStyle.copyWith(
                                color: status.errorMessage != null
                                    ? tokens.danger
                                    : tokens.muted,
                                letterSpacing: 0,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _ScheduleControl(
                schedule: status.schedule,
                enabled: !status.isChecking,
                onChanged: (schedule) {
                  unawaited(widget.control.setSchedule(schedule));
                },
              ),
              AppButton(
                key: SyncStatusKeys.checkNow,
                label: status.isChecking ? 'Checking…' : 'Check now',
                variant: AppButtonVariant.secondary,
                onPressed: status.isChecking
                    ? null
                    : () {
                        unawaited(widget.control.checkNow());
                      },
              ),
              if (widget.onAbout != null)
                AppButton(
                  key: SyncStatusKeys.about,
                  label: 'About',
                  variant: AppButtonVariant.ghost,
                  onPressed: widget.onAbout,
                ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _icon(UpdateCheckStatus status) {
    if (status.isChecking) {
      return Icons.sync;
    }
    if (!status.automaticEnabled) {
      return Icons.pause_circle_outline;
    }
    return switch (status.outcome) {
      UpdateOutcome.succeeded => Icons.cloud_done_outlined,
      UpdateOutcome.failed => Icons.cloud_off_outlined,
      UpdateOutcome.skippedOffline => Icons.wifi_off,
      UpdateOutcome.skipped => Icons.remove_circle_outline,
      null => Icons.cloud_queue,
    };
  }

  Color _statusColor(AppTokens tokens, UpdateCheckStatus status) {
    if (status.isChecking) {
      return tokens.info;
    }
    if (!status.automaticEnabled && status.outcome == null) {
      return tokens.dim;
    }
    return switch (status.outcome) {
      UpdateOutcome.succeeded => tokens.success,
      UpdateOutcome.failed => tokens.danger,
      UpdateOutcome.skippedOffline => tokens.muted,
      UpdateOutcome.skipped => tokens.muted,
      null => tokens.muted,
    };
  }

  String _label(UpdateCheckStatus status) {
    if (status.isChecking) {
      return status.progress == null
          ? 'Checking for updates…'
          : 'Downloading updates…';
    }
    if (!status.automaticEnabled && status.outcome == null) {
      return 'Automatic updates off';
    }
    return switch (status.outcome) {
      UpdateOutcome.succeeded => 'Game data is up to date',
      UpdateOutcome.failed => 'Last update check failed',
      UpdateOutcome.skippedOffline => 'Offline',
      UpdateOutcome.skipped => 'Last update check was skipped',
      null => 'Not checked yet',
    };
  }

  String? _detailText(UpdateCheckStatus status) {
    final checked = status.lastCheckAt;
    if (status.isChecking) {
      return null;
    }
    if (status.outcome == null) {
      return status.automaticEnabled
          ? 'Automatic checks are scheduled ${status.schedule.wireValue}.'
          : 'Press Check now to look for a newer data bundle.';
    }
    if (status.outcome == UpdateOutcome.failed) {
      return status.errorMessage ?? 'The last check did not complete.';
    }
    final parts = <String>[
      if (checked != null) 'Checked ${_relative(checked)}',
      if (!status.automaticEnabled) 'automatic checks off',
      if (status.automaticEnabled && status.nextCheckAt != null)
        'next ${_relativeFuture(status.nextCheckAt!)}',
    ];
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' · ');
  }

  String _relative(DateTime then) {
    final difference = _now.toUtc().difference(then.toUtc());
    if (difference.inSeconds < 60) {
      return 'just now';
    }
    if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes min ago';
    }
    if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours h ago';
    }
    final days = difference.inDays;
    return '$days ${days == 1 ? 'day' : 'days'} ago';
  }

  String _relativeFuture(DateTime then) {
    final difference = then.toUtc().difference(_now.toUtc());
    if (difference.isNegative) {
      return 'soon';
    }
    if (difference.inMinutes < 60) {
      return 'in ${difference.inMinutes} min';
    }
    if (difference.inHours < 24) {
      return 'in ${difference.inHours} h';
    }
    return 'in ${difference.inDays} d';
  }
}

class _ScheduleControl extends StatelessWidget {
  const _ScheduleControl({
    required this.schedule,
    required this.enabled,
    required this.onChanged,
  });

  final UpdateSchedule schedule;
  final bool enabled;
  final ValueChanged<UpdateSchedule> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      height: 32,
      padding: EdgeInsets.symmetric(horizontal: tokens.spaceMd),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border.all(color: tokens.borderSoft),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<UpdateSchedule>(
          key: SyncStatusKeys.schedule,
          value: schedule,
          isDense: true,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          dropdownColor: tokens.surfaceHigh,
          icon: Icon(Icons.arrow_drop_down, color: tokens.muted),
          style: tokens.labelStyle.copyWith(
            fontWeight: FontWeight.w600,
            color: tokens.text,
          ),
          onChanged: enabled
              ? (value) {
                  if (value != null) {
                    onChanged(value);
                  }
                }
              : null,
          items: [
            for (final option in UpdateSchedule.values)
              DropdownMenuItem<UpdateSchedule>(
                key: SyncStatusKeys.scheduleOption(option),
                value: option,
                child: Text(_scheduleLabel(option)),
              ),
          ],
        ),
      ),
    );
  }

  String _scheduleLabel(UpdateSchedule schedule) {
    return switch (schedule) {
      UpdateSchedule.off => 'OFF',
      UpdateSchedule.daily => 'DAILY',
      UpdateSchedule.weekly => 'WEEKLY',
    };
  }
}
