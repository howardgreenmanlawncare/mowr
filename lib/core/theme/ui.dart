import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Shared Swiss/International-Typographic primitives so screens compose from one
/// system instead of hard-coding colours, weights and spacing. Everything here
/// reads from the theme — never pass raw hex from a widget.

/// An uppercase, letter-spaced micro-label ("PROPERTY", "ACTIVE JOB"). The
/// canonical section eyebrow.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Text(text.toUpperCase(),
        style: color == null ? style : style?.copyWith(color: color));
  }
}

/// A 1px hairline rule — the primary divider in place of nested boxes.
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.height = 33, this.tight = false});
  final double height;
  final bool tight;

  @override
  Widget build(BuildContext context) =>
      Divider(height: tight ? 25 : height, thickness: 1);
}

/// A section eyebrow + optional supporting line, flush left.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(title),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: text.bodySmall),
        ],
      ],
    );
  }
}

/// A big flush-left figure over a tiny uppercase label. Used in stat rows.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scale the figure down to fit narrow tiles rather than clip/wrap, so
          // "£142.40" and "4" sit at a consistent baseline across the row.
          SizedBox(
            height: 26,
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(label.toUpperCase(),
              style: text.labelSmall?.copyWith(letterSpacing: 1.0)),
        ],
      ),
    );
  }
}

/// A row of [StatTile]s with even spacing.
class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.tiles});
  final List<StatTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

/// Concept B dashboard stats: one big hero figure with a hairline-separated
/// row of smaller supporting figures beneath. Replaces boxed stat tiles where a
/// single number dominates (home / earnings / dashboard).
class StatHero extends StatelessWidget {
  const StatHero({
    super.key,
    required this.label,
    required this.value,
    this.secondary = const [],
  });

  final String label;
  final String value;

  /// (value, label) pairs shown small beneath the hero.
  final List<(String, String)> secondary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(label),
        const SizedBox(height: 8),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.headlineMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (secondary.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.only(top: 14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                for (final s in secondary)
                  Expanded(child: MiniStat(value: s.$1, label: s.$2)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A small supporting figure: value over an uppercase micro-label. Used in the
/// [StatHero] secondary row and for equal-weight stat groups (no hero).
class MiniStat extends StatelessWidget {
  const MiniStat({super.key, required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 3),
        Text(label.toUpperCase(),
            style: text.labelSmall?.copyWith(letterSpacing: 1.0)),
      ],
    );
  }
}

/// A hairline-topped row of equal-weight [MiniStat]s (no hero) — e.g. the
/// mower's Jobs / Rating / Reviews.
class MiniStatRow extends StatelessWidget {
  const MiniStatRow({super.key, required this.stats});
  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final s in stats)
          Expanded(child: MiniStat(value: s.$1, label: s.$2)),
      ],
    );
  }
}

enum PillTone { neutral, live, soft, warning, error }

/// A status pill. Green fill ([PillTone.live]) is reserved for live/available;
/// everything else is a hairline outline or a muted tint.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.tone = PillTone.neutral, this.dot = false});
  final String label;
  final PillTone tone;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    late final Color bg, fg, border;
    switch (tone) {
      case PillTone.live:
        bg = AppColors.green; fg = Colors.white; border = AppColors.green;
      case PillTone.soft:
        bg = AppColors.greenPale; fg = AppColors.greenDark; border = AppColors.greenPale;
      case PillTone.warning:
        bg = AppColors.warningPale; fg = AppColors.warningInk; border = AppColors.warningPale;
      case PillTone.error:
        bg = AppColors.errorPale; fg = AppColors.error; border = AppColors.errorPale;
      case PillTone.neutral:
        bg = AppColors.surface; fg = AppColors.textSecondary; border = AppColors.border;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
                width: 6, height: 6,
                decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Text(label.toUpperCase(),
              style: text.labelSmall?.copyWith(
                  fontSize: 10.5, fontWeight: FontWeight.w700,
                  letterSpacing: 0.8, color: fg)),
        ],
      ),
    );
  }
}

/// A flush-left key/value line with a hairline top border (for stacked lists).
/// Value uses tabular figures so numbers align down a column.
class DataRow2 extends StatelessWidget {
  const DataRow2({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.emphasise = false,
    this.topBorder = false,
  });
  final String label;
  final String value;
  final String? sub;
  final bool emphasise;
  final bool topBorder;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final valStyle = (emphasise ? text.titleMedium : text.bodyMedium)?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()]);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: topBorder
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)))
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: emphasise ? text.titleMedium : text.bodyMedium),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub!, style: text.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(value, style: valStyle),
        ],
      ),
    );
  }
}
