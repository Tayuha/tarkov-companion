import 'package:tarkov_companion_data/tarkov_companion_data.dart';

/// The desktop shell's conservative connectivity monitor.
///
/// The client has no connectivity plugin dependency yet, so it treats the host
/// as online. A real offline attempt still fails through the sync stack and is
/// reported in the status strip; this monitor never blocks a check.
final class AlwaysOnlineNetworkMonitor implements NetworkMonitor {
  const AlwaysOnlineNetworkMonitor();

  @override
  bool get isOnline => true;

  @override
  bool get isMetered => false;

  @override
  Stream<void> get changes => const Stream<void>.empty();
}

/// The desktop shell's foreground monitor.
///
/// The window is visible whenever the process is running, so automatic checks
/// are allowed. A future lifecycle-aware implementation can replace this
/// without changing [UpdateCheckController].
final class AlwaysForegroundVisibilityMonitor implements VisibilityMonitor {
  const AlwaysForegroundVisibilityMonitor();

  @override
  bool get isForeground => true;

  @override
  Stream<void> get changes => const Stream<void>.empty();
}
