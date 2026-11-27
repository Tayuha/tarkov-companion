import 'dart:async';

import 'deep_links.dart';
import 'single_instance.dart';
import 'window_platform.dart';

/// Applies a message from a second launch to the running instance.
///
/// Focus is best effort: even when the window manager refuses to focus the
/// existing window, an item deep link is still queued for the shell.
final class InstanceCoordinator {
  InstanceCoordinator({required this.window, required this.inbox});

  final WindowPlatform window;
  final DeepLinkInbox inbox;

  Future<void> handle(InstanceMessage message) async {
    try {
      await window.focus();
    } on Object {
      // A missing platform channel or a refusing window manager must not lose
      // the deep link carried by the same launch.
    }
    final itemId = message.itemId;
    if (itemId != null) {
      inbox.add(ItemDeepLink(itemId));
    }
  }

  /// Subscribes to [messages] until the returned subscription is cancelled.
  StreamSubscription<InstanceMessage> listen(Stream<InstanceMessage> messages) {
    return messages.listen((message) {
      unawaited(handle(message));
    });
  }
}
