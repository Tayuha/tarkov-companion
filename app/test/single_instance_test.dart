import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tarkov_companion/src/single_instance.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tarkov-instance-');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
  });

  test(
    'the first launch becomes primary and the second forwards a message',
    () async {
      final primary = await SingleInstance.acquire(directory: directory);
      addTearDown(primary.close);
      expect(primary.isPrimary, isTrue);

      final received = primary.messages.first;
      final secondary = await SingleInstance.acquire(
        directory: directory,
        message: const InstanceMessage(itemId: 'item-42'),
      );

      expect(secondary.isPrimary, isFalse);
      expect((await received).itemId, 'item-42');
      await secondary.close();
    },
  );

  test('a second launch can request focus without an item', () async {
    final primary = await SingleInstance.acquire(directory: directory);
    addTearDown(primary.close);

    final received = primary.messages.first;
    final secondary = await SingleInstance.acquire(directory: directory);

    expect(secondary.isPrimary, isFalse);
    expect((await received).itemId, isNull);
    await secondary.close();
  });

  test('closing the primary releases the lock for the next launch', () async {
    final first = await SingleInstance.acquire(directory: directory);
    await first.close();

    final second = await SingleInstance.acquire(directory: directory);
    addTearDown(second.close);
    expect(second.isPrimary, isTrue);
  });

  test('a stale socket file from a crash is replaced', () async {
    await File('${directory.path}/instance.sock').writeAsString('stale');

    final primary = await SingleInstance.acquire(directory: directory);
    addTearDown(primary.close);
    expect(primary.isPrimary, isTrue);
    expect(
      await File('${directory.path}/instance.sock').exists(),
      isTrue,
      reason: 'the new primary binds its own socket',
    );
  });

  test('a stale lock file with a dead pid is reclaimed', () async {
    await File('${directory.path}/instance.lock').writeAsString('999999999');

    final primary = await SingleInstance.acquire(directory: directory);
    addTearDown(primary.close);
    expect(primary.isPrimary, isTrue);
  });

  test('a live lock without a listening socket fails cleanly', () async {
    final lock = File('${directory.path}/instance.lock');
    await lock.writeAsString('$pid');

    await expectLater(
      SingleInstance.acquire(
        directory: directory,
        startupTimeout: const Duration(milliseconds: 200),
      ),
      throwsA(isA<StateError>()),
    );
  });

  group('InstanceMessage', () {
    test('round-trips focus and item requests', () {
      expect(InstanceMessage.tryParse('{"type":"focus"}')?.itemId, isNull);
      expect(
        InstanceMessage.tryParse('{"type":"focus","itemId":" item-1 "}')
            ?.itemId,
        'item-1',
      );
    });

    test('ignores malformed or unrelated lines', () {
      expect(InstanceMessage.tryParse(''), isNull);
      expect(InstanceMessage.tryParse('not json'), isNull);
      expect(InstanceMessage.tryParse('{"type":"other"}'), isNull);
      expect(InstanceMessage.tryParse('{"type":"focus","itemId":4}'), isNull);
    });
  });
}
