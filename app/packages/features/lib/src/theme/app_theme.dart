import 'package:material_ui/material_ui.dart';

import 'app_tokens.dart';

/// Builds the phosphor-green dark theme shared by every client screen.
///
/// The theme is intentionally not installed in `main.dart` yet: screens migrate
/// in T8.13 (Items) and T8.14 (Quests). Tests and the component gallery use this
/// function directly.
ThemeData buildAppTheme() {
  const tokens = AppTokens.phosphor();
  final scheme = _colorScheme(tokens);
  final textTheme = _textTheme(tokens);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.background,
    canvasColor: tokens.background,
    fontFamily: tokens.uiFontFamily,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    iconTheme: IconThemeData(color: tokens.muted, size: tokens.h2Size),
    // Detail routes repeat the entity name in the body header, so the bar is a
    // compact breadcrumb: surface fill, hairline rule, mono label type.
    appBarTheme: AppBarThemeData(
      backgroundColor: tokens.surface,
      foregroundColor: tokens.muted,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: tokens.surface,
      toolbarHeight: 44,
      shape: Border(bottom: BorderSide(color: tokens.border)),
      iconTheme: IconThemeData(color: tokens.muted, size: tokens.h2Size),
      actionsIconTheme: IconThemeData(color: tokens.muted, size: tokens.h2Size),
      titleTextStyle: tokens.labelStyle.copyWith(
        fontSize: tokens.dataSize,
        letterSpacing: 0.06,
        color: tokens.muted,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: tokens.border,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: _inputDecorationTheme(tokens),
    filledButtonTheme: FilledButtonThemeData(
      style: _buttonStyle(
        tokens,
        background: tokens.accent,
        foreground: tokens.onAccent,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _buttonStyle(
        tokens,
        background: tokens.surfaceRaised,
        foreground: tokens.accent,
        border: tokens.accent,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: _buttonStyle(tokens, foreground: tokens.muted),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: tokens.accent,
      selectionColor: tokens.accentDeep,
      selectionHandleColor: tokens.accent,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: tokens.surfaceHigh,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      textStyle: tokens.bodyStyle.copyWith(color: tokens.text),
    ),
    extensions: const <ThemeExtension<dynamic>>[tokens],
  );
}

ColorScheme _colorScheme(AppTokens tokens) {
  return ColorScheme.dark(
    primary: tokens.accent,
    onPrimary: tokens.onAccent,
    secondary: tokens.info,
    onSecondary: tokens.onAccent,
    error: tokens.danger,
    onError: tokens.onAccent,
    surface: tokens.surface,
    onSurface: tokens.text,
  ).copyWith(
    primaryContainer: tokens.accentDeep,
    onPrimaryContainer: tokens.accent,
    primaryFixed: tokens.accent,
    primaryFixedDim: tokens.accent,
    onPrimaryFixed: tokens.onAccent,
    onPrimaryFixedVariant: tokens.accentDeep,
    secondaryContainer: tokens.surfaceHigh,
    onSecondaryContainer: tokens.text,
    secondaryFixed: tokens.info,
    secondaryFixedDim: tokens.info,
    onSecondaryFixed: tokens.onAccent,
    onSecondaryFixedVariant: tokens.accentDeep,
    tertiary: tokens.value,
    onTertiary: tokens.onAccent,
    tertiaryContainer: tokens.surfaceRaised,
    onTertiaryContainer: tokens.value,
    tertiaryFixed: tokens.value,
    tertiaryFixedDim: tokens.value,
    onTertiaryFixed: tokens.onAccent,
    onTertiaryFixedVariant: tokens.accentDeep,
    errorContainer: tokens.surfaceHigh,
    onErrorContainer: tokens.danger,
    surfaceDim: tokens.background,
    surfaceBright: tokens.surfaceHigh,
    surfaceContainerLowest: tokens.background,
    surfaceContainerLow: tokens.surface,
    surfaceContainer: tokens.surfaceRaised,
    surfaceContainerHigh: tokens.surfaceHigh,
    surfaceContainerHighest: tokens.surfaceHigh,
    onSurfaceVariant: tokens.muted,
    outline: tokens.border,
    outlineVariant: tokens.borderSoft,
    shadow: tokens.background,
    scrim: tokens.background,
    inverseSurface: tokens.text,
    onInverseSurface: tokens.background,
    inversePrimary: tokens.accentDeep,
    surfaceTint: tokens.accent,
  );
}

TextTheme _textTheme(AppTokens tokens) {
  return TextTheme(
    displayLarge: tokens.displayStyle,
    displayMedium: tokens.displayStyle.copyWith(fontSize: tokens.h1Size),
    displaySmall: tokens.h1Style,
    headlineLarge: tokens.h1Style,
    headlineMedium: tokens.h1Style,
    headlineSmall: tokens.h2Style,
    titleLarge: tokens.h1Style,
    titleMedium: tokens.h2Style,
    titleSmall: tokens.h2Style.copyWith(
      fontSize: tokens.bodySize,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: tokens.bodyStyle,
    bodyMedium: tokens.bodyStyle,
    bodySmall: tokens.bodyStyle.copyWith(color: tokens.muted),
    labelLarge: tokens.labelStyle,
    labelMedium: tokens.labelStyle,
    labelSmall: tokens.labelStyle,
  );
}

InputDecorationThemeData _inputDecorationTheme(AppTokens tokens) {
  final radius = BorderRadius.circular(tokens.radiusSm);
  BorderSide side(Color color) => BorderSide(color: color);
  OutlineInputBorder outline(Color color) =>
      OutlineInputBorder(borderRadius: radius, borderSide: side(color));

  return InputDecorationThemeData(
    filled: true,
    fillColor: tokens.surfaceRaised,
    isDense: true,
    contentPadding: EdgeInsets.symmetric(
      horizontal: tokens.spaceMd,
      vertical: tokens.spaceSm,
    ),
    hintStyle: tokens.bodyStyle.copyWith(color: tokens.dim),
    labelStyle: tokens.labelStyle.copyWith(color: tokens.muted),
    floatingLabelStyle: tokens.labelStyle.copyWith(color: tokens.accent),
    helperStyle: tokens.bodyStyle.copyWith(color: tokens.muted),
    errorStyle: tokens.bodyStyle.copyWith(color: tokens.danger),
    prefixIconColor: tokens.muted,
    suffixIconColor: tokens.muted,
    border: outline(tokens.border),
    enabledBorder: outline(tokens.border),
    focusedBorder: outline(tokens.accent),
    disabledBorder: outline(tokens.borderSoft),
    errorBorder: outline(tokens.danger),
    focusedErrorBorder: outline(tokens.danger),
  );
}

ButtonStyle _buttonStyle(
  AppTokens tokens, {
  Color? background,
  required Color foreground,
  Color? border,
}) {
  final radius = BorderRadius.circular(tokens.radiusSm);
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 32)),
    padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: tokens.spaceLg),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    backgroundColor: WidgetStatePropertyAll<Color?>(background),
    foregroundColor: WidgetStatePropertyAll<Color>(foreground),
    overlayColor: WidgetStatePropertyAll<Color>(
      foreground.withValues(alpha: 0.08),
    ),
    side: WidgetStatePropertyAll<BorderSide?>(
      border == null ? null : BorderSide(color: border),
    ),
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: radius),
    ),
    textStyle: WidgetStatePropertyAll<TextStyle?>(
      tokens.bodyStyle.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}
