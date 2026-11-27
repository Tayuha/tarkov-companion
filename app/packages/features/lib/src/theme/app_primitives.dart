import 'package:material_ui/material_ui.dart';

import 'app_tokens.dart';

/// A quiet bordered surface.
///
/// Panels are flat: a 1 px border, a 2 px radius and no shadow or gradient.
class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.child,
    this.label,
    this.trailing,
    this.padding,
    this.background,
    this.borderColor,
  });

  final Widget child;

  /// Optional uppercase mono heading inside the panel.
  final String? label;

  /// Optional widget aligned to the right of [label].
  final Widget? trailing;

  final EdgeInsetsGeometry? padding;
  final Color? background;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final label = this.label;

    return Container(
      padding: padding ?? EdgeInsets.all(tokens.spaceLg),
      decoration: BoxDecoration(
        color: background ?? tokens.surface,
        border: Border.all(color: borderColor ?? tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) ...[
            Row(
              children: [
                Expanded(child: AppSectionLabel(label)),
                ?trailing,
              ],
            ),
            SizedBox(height: tokens.spaceMd),
          ],
          child,
        ],
      ),
    );
  }
}

/// An uppercase monospace label that introduces a section or a field.
class AppSectionLabel extends StatelessWidget {
  const AppSectionLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tokens.labelStyle.copyWith(color: color ?? tokens.muted),
    );
  }
}

/// The four button intents of the design system.
enum AppButtonVariant { primary, secondary, ghost, danger }

/// A compact, rectangular action button.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;

  /// Stretch to the width offered by the parent.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final enabled = onPressed != null;
    final palette = _palette(tokens, variant, enabled);

    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          hoverColor: palette.foreground.withValues(alpha: 0.08),
          child: Container(
            height: 32,
            width: expand ? double.infinity : null,
            padding: EdgeInsets.symmetric(horizontal: tokens.spaceLg),
            decoration: BoxDecoration(
              color: palette.background,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: Center(
              widthFactor: 1,
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.labelStyle.copyWith(
                  fontWeight: FontWeight.w600,
                  color: palette.foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  ({Color? background, Color border, Color foreground}) _palette(
    AppTokens tokens,
    AppButtonVariant variant,
    bool enabled,
  ) {
    if (!enabled) {
      return (
        background: variant == AppButtonVariant.primary
            ? tokens.surfaceHigh
            : null,
        border: tokens.borderSoft,
        foreground: tokens.dim,
      );
    }
    return switch (variant) {
      AppButtonVariant.primary => (
        background: tokens.accent,
        border: tokens.accent,
        foreground: tokens.onAccent,
      ),
      AppButtonVariant.secondary => (
        background: null,
        border: tokens.accent,
        foreground: tokens.accent,
      ),
      AppButtonVariant.ghost => (
        background: null,
        border: tokens.borderSoft,
        foreground: tokens.muted,
      ),
      AppButtonVariant.danger => (
        background: null,
        border: tokens.danger,
        foreground: tokens.danger,
      ),
    };
  }
}

/// A compact filter chip, either selected or neutral.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final foreground = selected ? tokens.accent : tokens.muted;

    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(tokens.radiusPill),
          hoverColor: foreground.withValues(alpha: 0.08),
          child: Container(
            height: 24,
            padding: EdgeInsets.symmetric(horizontal: tokens.spaceMd),
            decoration: BoxDecoration(
              color: selected ? tokens.accentDeep : null,
              border: Border.all(
                color: selected ? tokens.accent : tokens.borderSoft,
              ),
              borderRadius: BorderRadius.circular(tokens.radiusPill),
            ),
            child: Center(
              widthFactor: 1,
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.labelStyle.copyWith(
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The five player-facing quest/item states.
enum AppStatus { available, inProgress, completed, failed, locked }

/// A bordered pill that states a single status without relying on colour alone.
class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({super.key, required this.status, this.label});

  final AppStatus status;

  /// Overrides the default sentence-case label.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final color = _color(tokens);
    final text = label ?? _label();

    return Container(
      height: 24,
      padding: EdgeInsets.symmetric(horizontal: tokens.spaceMd),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.10), tokens.surface),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(tokens.radiusPill),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          text.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.labelStyle.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }

  Color _color(AppTokens tokens) => switch (status) {
    AppStatus.available => tokens.success,
    AppStatus.inProgress => tokens.info,
    AppStatus.completed => tokens.accent,
    AppStatus.failed => tokens.danger,
    AppStatus.locked => tokens.dim,
  };

  String _label() => switch (status) {
    AppStatus.available => 'Available',
    AppStatus.inProgress => 'In progress',
    AppStatus.completed => 'Completed',
    AppStatus.failed => 'Failed',
    AppStatus.locked => 'Locked',
  };
}

/// A compact label/value cell for inspector statistics.
class AppStatTile extends StatelessWidget {
  const AppStatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.subtitle,
    this.valueColor,
  });

  final String label;
  final String value;
  final String? unit;
  final String? subtitle;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final unit = this.unit;
    final subtitle = this.subtitle;

    return Container(
      padding: EdgeInsets.all(tokens.spaceMd),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border.all(color: tokens.borderSoft),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSectionLabel(label),
          SizedBox(height: tokens.spaceXs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.dataStyle.copyWith(
                    fontSize: tokens.h2Size,
                    fontWeight: FontWeight.w700,
                    color: valueColor ?? tokens.text,
                  ),
                ),
              ),
              if (unit != null) ...[
                SizedBox(width: tokens.spaceXs),
                Text(
                  unit,
                  style: tokens.dataStyle.copyWith(color: tokens.muted),
                ),
              ],
            ],
          ),
          if (subtitle != null) ...[
            SizedBox(height: tokens.spaceXs),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.bodyStyle.copyWith(color: tokens.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// A thin progress rail with an optional label and trailing readout.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    required this.value,
    this.label,
    this.trailing,
    this.color,
  });

  /// Progress in the range 0..1; values outside the range are clamped.
  final double value;
  final String? label;
  final String? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final progress = value.clamp(0.0, 1.0).toDouble();
    final label = this.label;
    final trailing = this.trailing;
    final percent = (progress * 100).round();

    return Semantics(
      label: label ?? 'Progress',
      value: '$percent%',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null || trailing != null) ...[
            Row(
              children: [
                if (label != null) Expanded(child: AppSectionLabel(label)),
                if (trailing != null)
                  Text(
                    trailing,
                    style: tokens.dataStyle.copyWith(color: tokens.muted),
                  ),
              ],
            ),
            SizedBox(height: tokens.spaceXs),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            child: Container(
              height: 3,
              color: tokens.borderSoft,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress,
                heightFactor: 1,
                child: ColoredBox(color: color ?? tokens.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact data row: name and meta on the left, value and delta on the right.
///
/// This is the sample density unit for the catalog and quest lists. Screens may
/// wrap it in a gesture detector; the row itself is presentational.
class AppDataRow extends StatelessWidget {
  const AppDataRow({
    super.key,
    required this.name,
    required this.value,
    this.meta,
    this.delta,
    this.deltaColor,
    this.selected = false,
  });

  final String name;
  final String value;
  final String? meta;
  final String? delta;
  final Color? deltaColor;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final meta = this.meta;
    final delta = this.delta;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spaceMd,
        vertical: tokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: selected ? tokens.accentDeep : null,
        border: Border(
          left: BorderSide(
            color: selected ? tokens.accent : tokens.borderSoft,
            width: 2,
          ),
          bottom: BorderSide(color: tokens.borderSoft),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.h2Style.copyWith(
                    fontSize: tokens.bodySize,
                    fontWeight: FontWeight.w600,
                    color: selected ? tokens.accent : tokens.text,
                  ),
                ),
                if (meta != null) ...[
                  SizedBox(height: tokens.radiusSm),
                  Text(
                    meta.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.labelStyle.copyWith(color: tokens.muted),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: tokens.spaceLg),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.dataStyle.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tokens.text,
                ),
              ),
              if (delta != null) ...[
                SizedBox(height: tokens.radiusSm),
                Text(
                  delta,
                  style: tokens.dataStyle.copyWith(
                    color: deltaColor ?? tokens.muted,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
