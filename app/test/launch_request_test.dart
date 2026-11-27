import 'package:flutter_test/flutter_test.dart';
import 'package:tarkov_companion/src/launch_request.dart';

void main() {
  group('LaunchRequest.parse', () {
    test('accepts the --item-id=<id> form', () {
      final request = LaunchRequest.parse([
        '--item-id=5447a9cd4bdc2dbd208b4567',
      ]);

      expect(request.itemId, '5447a9cd4bdc2dbd208b4567');
      expect(request.hasItem, isTrue);
    });

    test('accepts the separated --item-id <id> form', () {
      expect(LaunchRequest.parse(['--item-id', 'item-1']).itemId, 'item-1');
    });

    test('accepts tarkov-companion://item/<id>', () {
      expect(
        LaunchRequest.parse(['tarkov-companion://item/item-1']).itemId,
        'item-1',
      );
      expect(
        LaunchRequest.parse(['tarkov-companion:///item/item-2']).itemId,
        'item-2',
      );
    });

    test('accepts a percent-encoded item id in a URI', () {
      expect(
        LaunchRequest.parse(['tarkov-companion://item/item%2Dwith%2Ddash'])
            .itemId,
        'item-with-dash',
      );
    });

    test('ignores unknown arguments and unrelated URIs', () {
      expect(
        LaunchRequest.parse([
          '--verbose',
          'https://example.test/item/1',
          '--item-id=',
          '--item-id',
        ]).itemId,
        isNull,
      );
    });

    test('the first well-formed item request wins', () {
      expect(
        LaunchRequest.parse(['--item-id=first', '--item-id=second']).itemId,
        'first',
      );
    });

    test('an empty launch has no item', () {
      final request = LaunchRequest.parse(const []);

      expect(request.hasItem, isFalse);
      expect(request.itemId, isNull);
    });
  });
}
