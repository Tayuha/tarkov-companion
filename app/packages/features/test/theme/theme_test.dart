import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

void main() {
  final theme = buildAppTheme();
  const tokens = AppTokens.phosphor();

  test('is a dark Material 3 theme', () {
    expect(theme.useMaterial3, isTrue);
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, tokens.background);
    expect(theme.canvasColor, tokens.background);
  });

  test('exposes the phosphor token extension', () {
    final extension = theme.extension<AppTokens>();

    expect(extension, isNotNull);
    expect(extension!.background, tokens.background);
    expect(extension.accent, tokens.accent);
    expect(extension.surfaceHigh, tokens.surfaceHigh);
    expect(extension.labelSize, tokens.labelSize);
  });

  test('maps the semantic colours onto the ColorScheme', () {
    expect(theme.colorScheme.primary, tokens.accent);
    expect(theme.colorScheme.onPrimary, tokens.onAccent);
    expect(theme.colorScheme.primaryContainer, tokens.accentDeep);
    expect(theme.colorScheme.surface, tokens.surface);
    expect(theme.colorScheme.onSurface, tokens.text);
    expect(theme.colorScheme.onSurfaceVariant, tokens.muted);
    expect(theme.colorScheme.outline, tokens.border);
    expect(theme.colorScheme.outlineVariant, tokens.borderSoft);
    expect(theme.colorScheme.error, tokens.danger);
  });

  test('does not keep a Material default primary', () {
    expect(theme.colorScheme.primary, tokens.accent);
    expect(theme.colorScheme.primary, isNot(ColorScheme.dark().primary));
  });

  test('uses Fira Sans Condensed for UI and DejaVu Sans Mono for data', () {
    expect(theme.textTheme.displayLarge?.fontFamily, 'Fira Sans Condensed');
    expect(theme.textTheme.headlineLarge?.fontFamily, 'Fira Sans Condensed');
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Fira Sans Condensed');
    expect(theme.textTheme.bodyMedium?.fontSize, tokens.bodySize);

    expect(theme.textTheme.labelMedium?.fontFamily, 'DejaVu Sans Mono');
    expect(theme.textTheme.labelMedium?.fontSize, tokens.labelSize);
    expect(tokens.labelStyle.fontFamily, 'DejaVu Sans Mono');
    expect(tokens.dataStyle.fontFamily, 'DejaVu Sans Mono');
    expect(tokens.dataStyle.fontSize, tokens.dataSize);
  });

  test('themes inputs, buttons and dividers from the tokens', () {
    expect(theme.inputDecorationTheme.filled, isTrue);
    expect(theme.inputDecorationTheme.fillColor, tokens.surfaceRaised);
    expect(
      theme.filledButtonTheme.style?.backgroundColor?.resolve(
        const <WidgetState>{},
      ),
      tokens.accent,
    );
    expect(
      theme.outlinedButtonTheme.style?.side?.resolve(const <WidgetState>{}),
      BorderSide(color: tokens.accent),
    );
    expect(theme.dividerTheme.color, tokens.border);
    expect(theme.dividerTheme.thickness, 1);
  });
}
