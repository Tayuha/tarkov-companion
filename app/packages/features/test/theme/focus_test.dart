import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

void main() {
  const tokens = AppTokens.phosphor();

  group('focus tokens', () {
    test('the ring is the accent at the approved width', () {
      expect(tokens.focusRing, tokens.accent);
      expect(tokens.focusRingWidth, 2);
    });

    test('copyWith and lerp carry the focus fields', () {
      final changed = tokens.copyWith(focusRingWidth: 3);
      expect(changed.focusRingWidth, 3);
      expect(changed.focusRing, tokens.focusRing);

      final halfway = tokens.lerp(tokens.copyWith(focusRingWidth: 4), 0.5);
      expect(halfway.focusRingWidth, 3);
      expect(halfway.focusRing, tokens.focusRing);
    });
  });

  group('theme focus treatment', () {
    test('inputs draw a two-pixel accent focus border', () {
      final theme = buildAppTheme();
      final focused = theme.inputDecorationTheme.focusedBorder;
      expect(focused, isA<OutlineInputBorder>());
      final side = (focused! as OutlineInputBorder).borderSide;
      expect(side.color, tokens.focusRing);
      expect(side.width, tokens.focusRingWidth);
      expect(theme.focusColor.a, greaterThan(0));
    });
  });
}
