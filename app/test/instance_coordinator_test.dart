import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tarkov_companion/src/deep_links.dart';
import 'package:tarkov_companion/src/instance_coordinator.dart';
import 'package:tarkov_companion/src/single_instance.dart';
import 'package:tarkov_companion/src/window_geometry.dart';
import 'package:tarkov_companion/src/window_platform.dart';

final class _RecordingWindow implements WindowPlatform {
  int focusCalls = 0;

  @override
  Future<void> focus() async {
    focusCalls++;
  }

  @override
  Future<void> close() async {}

  @override
  Future<WindowMetrics?> metrics() async => null;

  @override
  Future<void> setGeometry(WindowRect geometry) async {}

  @override
  Stream<WindowRect> get geometryChanges => const Stream<WindowRect>.empty();

  @override
  void setClosingHandler(
    Future<void> Function(WindowRect? geometry)? handler,
  ) {}
}

void main() {
  test(
    'a second-launch message focuses the window and queues the item',
    () async {
      final window = _RecordingWindow();
      final inbox = DeepLinkInbox();
      addTearDown(inbox.dispose);
      final coordinator = InstanceCoordinator(window: window, inbox: inbox);

      await coordinator.handle(
        const InstanceMessage(itemId: '5447a9cd4bdc2dbd208b4567'),
      );

      expect(window.focusCalls, 1);
      expect(inbox.take(), const ItemDeepLink('5447a9cd4bdc2dbd208b4567'));
      expect(inbox.hasPending, isFalse);
    },
  );

  test('a focus-only message does not queue an item', () async {
    final window = _RecordingWindow();
    final inbox = DeepLinkInbox();
    addTearDown(inbox.dispose);
    final coordinator = InstanceCoordinator(window: window, inbox: inbox);

    await coordinator.handle(const InstanceMessage());

    expect(window.focusCalls, 1);
    expect(inbox.hasPending, isFalse);
  });
}
