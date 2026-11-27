import 'dart:collection';

import 'package:flutter/foundation.dart';

/// One request to open an item detail page by game item id.
@immutable
final class ItemDeepLink {
  const ItemDeepLink(this.itemId);

  /// The upstream Tarkov item id.
  final String itemId;

  @override
  bool operator ==(Object other) =>
      other is ItemDeepLink && other.itemId == itemId;

  @override
  int get hashCode => itemId.hashCode;

  @override
  String toString() => 'ItemDeepLink($itemId)';
}

/// A small queue of deep links waiting for the session to become ready.
///
/// The launch request adds one link before the first frame, and a second
/// process can add more through the instance socket. [AppRoot] drains the
/// queue on the next frame after data is available, so a link that arrives
/// before the local database opens is not lost.
final class DeepLinkInbox extends ChangeNotifier {
  final Queue<ItemDeepLink> _pending = Queue<ItemDeepLink>();

  /// Whether at least one link is waiting.
  bool get hasPending => _pending.isNotEmpty;

  /// Number of links waiting; exposed for diagnostics and tests.
  int get pendingCount => _pending.length;

  /// Queues [link] and notifies listeners.
  void add(ItemDeepLink link) {
    _pending.add(link);
    notifyListeners();
  }

  /// Removes and returns the oldest link, or `null` when the queue is empty.
  ItemDeepLink? take() => _pending.isEmpty ? null : _pending.removeFirst();
}
