import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';

/// The visual tokens of the Tarkov Companion client.
///
/// The design direction is phosphor green: green-black surfaces, pale-green
/// text, a mint accent for decisions and confirmed progress. Values live here
/// so no widget outside this file needs a colour literal.
///
/// Read the active tokens with [AppTokens.of] or
/// `Theme.of(context).extension<AppTokens>()`.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHigh,
    required this.border,
    required this.borderSoft,
    required this.text,
    required this.muted,
    required this.dim,
    required this.accent,
    required this.accentDeep,
    required this.success,
    required this.danger,
    required this.info,
    required this.value,
    required this.onAccent,
    required this.spaceXs,
    required this.spaceSm,
    required this.spaceMd,
    required this.spaceLg,
    required this.spaceXl,
    required this.space2xl,
    required this.space3xl,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusPill,
    required this.displaySize,
    required this.h1Size,
    required this.h2Size,
    required this.bodySize,
    required this.labelSize,
    required this.dataSize,
    required this.labelTracking,
    required this.uiFontFamily,
    required this.dataFontFamily,
  });

  /// The approved phosphor-green palette and type scale.
  const AppTokens.phosphor()
    : this(
        background: const Color(0xFF070D08),
        surface: const Color(0xFF0D1510),
        surfaceRaised: const Color(0xFF121C15),
        surfaceHigh: const Color(0xFF18251B),
        border: const Color(0xFF223529),
        borderSoft: const Color(0xFF1B2A20),
        text: const Color(0xFFDCF3E2),
        muted: const Color(0xFF8FA894),
        dim: const Color(0xFF5F7A66),
        accent: const Color(0xFF7DF7A8),
        accentDeep: const Color(0xFF17452A),
        success: const Color(0xFF5FBF7A),
        danger: const Color(0xFFD27A6A),
        info: const Color(0xFF7DDCC4),
        value: const Color(0xFFC9D99A),
        onAccent: const Color(0xFF04140A),
        spaceXs: 4,
        spaceSm: 8,
        spaceMd: 12,
        spaceLg: 16,
        spaceXl: 24,
        space2xl: 32,
        space3xl: 48,
        radiusSm: 2,
        radiusMd: 4,
        radiusPill: 999,
        displaySize: 34,
        h1Size: 22,
        h2Size: 16,
        bodySize: 12,
        labelSize: 8,
        dataSize: 11,
        labelTracking: 1.2,
        uiFontFamily: 'Fira Sans Condensed',
        dataFontFamily: 'DejaVu Sans Mono',
      );

  /// The 4 px spacing grid.
  static const List<double> spacingScale = <double>[4, 8, 12, 16, 24, 32, 48];

  /// The allowed corner radii. The pill value is a sentinel, not a pixel size.
  static const List<double> radiusScale = <double>[2, 4, 999];

  /// The type scale in logical pixels.
  static const List<double> typeScale = <double>[34, 22, 16, 12, 8, 11];

  /// Page and table background.
  final Color background;

  /// Cards and panels.
  final Color surface;

  /// Inputs, icon wells and raised segments.
  final Color surfaceRaised;

  /// The highest resting surface.
  final Color surfaceHigh;

  /// Structural rules and focus outlines.
  final Color border;

  /// Quiet separators inside a surface.
  final Color borderSoft;

  /// Primary text.
  final Color text;

  /// Secondary text and labels.
  final Color muted;

  /// Disabled and decorative text.
  final Color dim;

  /// Decision, selection and confirmed-progress accent.
  final Color accent;

  /// Selected fill behind the accent.
  final Color accentDeep;

  /// Available and successful states.
  final Color success;

  /// Failed states and negative change.
  final Color danger;

  /// In-progress states and links.
  final Color info;

  /// Prices, standing and other numeric values.
  final Color value;

  /// Text drawn on top of [accent].
  final Color onAccent;

  final double spaceXs;
  final double spaceSm;
  final double spaceMd;
  final double spaceLg;
  final double spaceXl;
  final double space2xl;
  final double space3xl;

  final double radiusSm;
  final double radiusMd;
  final double radiusPill;

  final double displaySize;
  final double h1Size;
  final double h2Size;
  final double bodySize;
  final double labelSize;
  final double dataSize;

  /// Tracking used by uppercase mono labels.
  final double labelTracking;

  final String uiFontFamily;
  final String dataFontFamily;

  /// The spacing scale as an ordered list, useful for tests and tooling.
  List<double> get spacing => spacingScale;

  /// The radius scale as an ordered list, useful for tests and tooling.
  List<double> get radii => radiusScale;

  /// Display type: short, loud page headings.
  TextStyle get displayStyle => TextStyle(
    fontFamily: uiFontFamily,
    fontSize: displaySize,
    fontWeight: FontWeight.w700,
    height: 1.05,
    color: text,
  );

  /// First-level section headings.
  TextStyle get h1Style => TextStyle(
    fontFamily: uiFontFamily,
    fontSize: h1Size,
    fontWeight: FontWeight.w600,
    height: 1.15,
    color: text,
  );

  /// Second-level headings, row titles and panel titles.
  TextStyle get h2Style => TextStyle(
    fontFamily: uiFontFamily,
    fontSize: h2Size,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: text,
  );

  /// Running copy.
  TextStyle get bodyStyle => TextStyle(
    fontFamily: uiFontFamily,
    fontSize: bodySize,
    fontWeight: FontWeight.w400,
    height: 1.35,
    color: text,
  );

  /// Uppercase mono labels.
  TextStyle get labelStyle => TextStyle(
    fontFamily: dataFontFamily,
    fontSize: labelSize,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: labelTracking,
    color: muted,
  );

  /// Monospace numbers: prices, levels, weights and deltas.
  TextStyle get dataStyle => TextStyle(
    fontFamily: dataFontFamily,
    fontSize: dataSize,
    fontWeight: FontWeight.w400,
    height: 1.2,
    color: text,
  );

  /// The active tokens, with the phosphor palette as a safe fallback.
  static AppTokens of(BuildContext context) {
    return Theme.of(context).extension<AppTokens>() ??
        const AppTokens.phosphor();
  }

  @override
  AppTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceHigh,
    Color? border,
    Color? borderSoft,
    Color? text,
    Color? muted,
    Color? dim,
    Color? accent,
    Color? accentDeep,
    Color? success,
    Color? danger,
    Color? info,
    Color? value,
    Color? onAccent,
    double? spaceXs,
    double? spaceSm,
    double? spaceMd,
    double? spaceLg,
    double? spaceXl,
    double? space2xl,
    double? space3xl,
    double? radiusSm,
    double? radiusMd,
    double? radiusPill,
    double? displaySize,
    double? h1Size,
    double? h2Size,
    double? bodySize,
    double? labelSize,
    double? dataSize,
    double? labelTracking,
    String? uiFontFamily,
    String? dataFontFamily,
  }) {
    return AppTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      border: border ?? this.border,
      borderSoft: borderSoft ?? this.borderSoft,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      dim: dim ?? this.dim,
      accent: accent ?? this.accent,
      accentDeep: accentDeep ?? this.accentDeep,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      value: value ?? this.value,
      onAccent: onAccent ?? this.onAccent,
      spaceXs: spaceXs ?? this.spaceXs,
      spaceSm: spaceSm ?? this.spaceSm,
      spaceMd: spaceMd ?? this.spaceMd,
      spaceLg: spaceLg ?? this.spaceLg,
      spaceXl: spaceXl ?? this.spaceXl,
      space2xl: space2xl ?? this.space2xl,
      space3xl: space3xl ?? this.space3xl,
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusPill: radiusPill ?? this.radiusPill,
      displaySize: displaySize ?? this.displaySize,
      h1Size: h1Size ?? this.h1Size,
      h2Size: h2Size ?? this.h2Size,
      bodySize: bodySize ?? this.bodySize,
      labelSize: labelSize ?? this.labelSize,
      dataSize: dataSize ?? this.dataSize,
      labelTracking: labelTracking ?? this.labelTracking,
      uiFontFamily: uiFontFamily ?? this.uiFontFamily,
      dataFontFamily: dataFontFamily ?? this.dataFontFamily,
    );
  }

  @override
  AppTokens lerp(covariant AppTokens? other, double t) {
    if (other == null) {
      return this;
    }
    Color blend(Color a, Color b) => Color.lerp(a, b, t)!;
    double scale(double a, double b) => lerpDouble(a, b, t)!;
    return AppTokens(
      background: blend(background, other.background),
      surface: blend(surface, other.surface),
      surfaceRaised: blend(surfaceRaised, other.surfaceRaised),
      surfaceHigh: blend(surfaceHigh, other.surfaceHigh),
      border: blend(border, other.border),
      borderSoft: blend(borderSoft, other.borderSoft),
      text: blend(text, other.text),
      muted: blend(muted, other.muted),
      dim: blend(dim, other.dim),
      accent: blend(accent, other.accent),
      accentDeep: blend(accentDeep, other.accentDeep),
      success: blend(success, other.success),
      danger: blend(danger, other.danger),
      info: blend(info, other.info),
      value: blend(value, other.value),
      onAccent: blend(onAccent, other.onAccent),
      spaceXs: scale(spaceXs, other.spaceXs),
      spaceSm: scale(spaceSm, other.spaceSm),
      spaceMd: scale(spaceMd, other.spaceMd),
      spaceLg: scale(spaceLg, other.spaceLg),
      spaceXl: scale(spaceXl, other.spaceXl),
      space2xl: scale(space2xl, other.space2xl),
      space3xl: scale(space3xl, other.space3xl),
      radiusSm: scale(radiusSm, other.radiusSm),
      radiusMd: scale(radiusMd, other.radiusMd),
      radiusPill: scale(radiusPill, other.radiusPill),
      displaySize: scale(displaySize, other.displaySize),
      h1Size: scale(h1Size, other.h1Size),
      h2Size: scale(h2Size, other.h2Size),
      bodySize: scale(bodySize, other.bodySize),
      labelSize: scale(labelSize, other.labelSize),
      dataSize: scale(dataSize, other.dataSize),
      labelTracking: scale(labelTracking, other.labelTracking),
      uiFontFamily: t < 0.5 ? uiFontFamily : other.uiFontFamily,
      dataFontFamily: t < 0.5 ? dataFontFamily : other.dataFontFamily,
    );
  }
}
