import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

void main() {
  const tokens = AppTokens.phosphor();

  group('WCAG contrast', () {
    test('primary text on both page surfaces passes AA', () {
      expect(
        _contrast(tokens.text, tokens.surface),
        greaterThanOrEqualTo(4.5),
        reason: 'text on surface',
      );
      expect(
        _contrast(tokens.text, tokens.background),
        greaterThanOrEqualTo(4.5),
        reason: 'text on background',
      );
    });

    test('the accent is legible over the page', () {
      expect(
        _contrast(tokens.accent, tokens.background),
        greaterThanOrEqualTo(4.5),
        reason: 'accent on background',
      );
    });

    test('text drawn on the accent fill passes AA', () {
      expect(
        _contrast(tokens.onAccent, tokens.accent),
        greaterThanOrEqualTo(4.5),
        reason: 'onAccent on accent',
      );
    });

    test('muted secondary text stays readable on a panel', () {
      expect(
        _contrast(tokens.muted, tokens.surface),
        greaterThanOrEqualTo(4.5),
        reason: 'muted on surface',
      );
    });

    test('semantic state colours stay readable on a panel', () {
      for (final (name, color) in <(String, Color)>[
        ('success', tokens.success),
        ('danger', tokens.danger),
        ('info', tokens.info),
        ('value', tokens.value),
      ]) {
        expect(
          _contrast(color, tokens.surface),
          greaterThanOrEqualTo(4.5),
          reason: '$name on surface',
        );
      }
    });
  });

  group('scales', () {
    test('spacing follows the 4 px grid', () {
      expect(AppTokens.spacingScale, <double>[4, 8, 12, 16, 24, 32, 48]);
      expect(tokens.spacing, AppTokens.spacingScale);
      expect(<double>[
        tokens.spaceXs,
        tokens.spaceSm,
        tokens.spaceMd,
        tokens.spaceLg,
        tokens.spaceXl,
        tokens.space2xl,
        tokens.space3xl,
      ], AppTokens.spacingScale);
    });

    test('radii are 2, 4 and a pill sentinel', () {
      expect(AppTokens.radiusScale, <double>[2, 4, 999]);
      expect(tokens.radii, AppTokens.radiusScale);
      expect(tokens.radiusSm, 2);
      expect(tokens.radiusMd, 4);
      expect(tokens.radiusPill, greaterThanOrEqualTo(999));
    });

    test('the type scale is the approved set', () {
      expect(tokens.displaySize, 34);
      expect(tokens.h1Size, 22);
      expect(tokens.h2Size, 16);
      expect(tokens.bodySize, 12);
      expect(tokens.labelSize, 8);
      expect(tokens.dataSize, 11);
      expect(AppTokens.typeScale, <double>[34, 22, 16, 12, 8, 11]);
    });

    test('font families are named once', () {
      expect(tokens.uiFontFamily, 'Fira Sans Condensed');
      expect(tokens.dataFontFamily, 'DejaVu Sans Mono');
      expect(tokens.displayStyle.fontFamily, tokens.uiFontFamily);
      expect(tokens.bodyStyle.fontFamily, tokens.uiFontFamily);
      expect(tokens.labelStyle.fontFamily, tokens.dataFontFamily);
      expect(tokens.dataStyle.fontFamily, tokens.dataFontFamily);
    });
  });

  group('ThemeExtension', () {
    test('copyWith replaces one field and keeps the rest', () {
      final changed = tokens.copyWith(accent: tokens.info, spaceLg: 20);

      expect(changed.accent, tokens.info);
      expect(changed.spaceLg, 20);
      expect(changed.background, tokens.background);
      expect(changed.dataFontFamily, tokens.dataFontFamily);
    });

    test('lerp blends colours and sizes', () {
      final other = tokens.copyWith(
        background: tokens.text,
        spaceLg: 32,
        uiFontFamily: 'Other UI',
      );

      final halfway = tokens.lerp(other, 0.5);
      expect(halfway.spaceLg, 24);
      expect(
        halfway.background,
        Color.lerp(tokens.background, tokens.text, 0.5),
      );
      expect(halfway.uiFontFamily, 'Other UI');

      expect(tokens.lerp(other, 0).background, tokens.background);
      expect(tokens.lerp(null, 0.5), same(tokens));
    });
  });
}

double _contrast(Color a, Color b) {
  final first = _luminance(a);
  final second = _luminance(b);
  final lighter = math.max(first, second);
  final darker = math.min(first, second);
  return (lighter + 0.05) / (darker + 0.05);
}

double _luminance(Color color) {
  double channel(double value) {
    if (value <= 0.04045) {
      return value / 12.92;
    }
    return math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}
