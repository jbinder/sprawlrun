import 'dart:math';

import 'package:flutter/material.dart';

import '../models/stats.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';

/// Shared scale for every activity dot on screen: how bright a day is drawn
/// depends on how it compares with the runner's own best day, not with a fixed
/// table that would leave a 3 km runner permanently dim.
class DotScale {
  const DotScale(this.bestDayMeters);

  /// Built from every bucket that will be drawn, so the brightest dot is
  /// always the best day in view.
  factory DotScale.of(Iterable<DayBucket> days) => DotScale(days.fold(0.0, (m, d) => max(m, d.distanceMeters)));

  final double bestDayMeters;

  /// 0 for a rest day, 1–4 for a run day by quartile of the best day.
  int level(double meters) {
    if (meters <= 0) return 0;
    // The same 1 km floor as the bar charts, so one short jog is not "full".
    final ratio = meters / max(bestDayMeters, 1000.0);
    if (ratio < 0.25) return 1;
    if (ratio < 0.5) return 2;
    if (ratio < 0.75) return 3;
    return 4;
  }
}

/// One day. A rest day is a dark notch, a future day only an outline, and a
/// run day is lit in proportion to its distance.
class ActivityDot extends StatelessWidget {
  const ActivityDot({super.key, required this.level, this.future = false, this.accent = Cy.cyan, this.today = false});

  final int level;
  final bool future;
  final Color accent;
  final bool today;

  static const _alpha = [0.0, 0.32, 0.52, 0.74, 1.0];

  @override
  Widget build(BuildContext context) {
    final lit = level > 0;
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: lit
              ? accent.withValues(alpha: _alpha[level])
              : future
              ? Colors.transparent
              : Cy.panelHi,
          border: Border.all(
            color: lit
                ? accent.withValues(alpha: min(1, _alpha[level] + 0.2))
                : today
                ? Cy.inkDim
                : Cy.rule.withValues(alpha: future ? 0.45 : 1),
            width: today ? 1.4 : 1,
          ),
          boxShadow: level == 4 ? glow(accent, blur: 6, opacity: 0.45) : null,
        ),
      ),
    );
  }
}

/// A calendar month as a 7-column grid, Monday first, one [ActivityDot] per
/// day. [days] must be the month's `perDay` buckets, oldest first.
class MonthDots extends StatelessWidget {
  const MonthDots({
    super.key,
    required this.days,
    required this.scale,
    required this.today,
    this.accent = Cy.cyan,
    this.onDayTap,
    this.gap = 4,
  });

  final List<DayBucket> days;
  final DotScale scale;
  final DateTime today;
  final Color accent;

  /// Called for days that have at least one run.
  final ValueChanged<DayBucket>? onDayTap;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    // Pad the first row so the 1st sits under its weekday.
    final lead = days.first.day.weekday - DateTime.monday;
    final cells = <DayBucket?>[...List<DayBucket?>.filled(lead, null), ...days];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return Column(
      children: [
        for (var row = 0; row < cells.length ~/ 7; row++)
          Padding(
            padding: EdgeInsets.only(bottom: row == cells.length ~/ 7 - 1 ? 0 : gap),
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: gap / 2),
                      child: _cell(cells[row * 7 + col]),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(DayBucket? bucket) {
    if (bucket == null) {
      return const AspectRatio(aspectRatio: 1, child: SizedBox.shrink());
    }
    final dot = ActivityDot(
      level: scale.level(bucket.distanceMeters),
      future: bucket.day.isAfter(today),
      today: bucket.day == today,
      accent: accent,
    );
    if (bucket.runs == 0 || onDayTap == null) return dot;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => onDayTap!(bucket), child: dot);
  }
}

/// `M T W T F S S` above a [MonthDots] grid.
class WeekdayHeader extends StatelessWidget {
  const WeekdayHeader({super.key, this.gap = 4});

  final double gap;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final l in _letters)
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gap / 2),
              child: Center(child: Text(l, style: CyType.label(size: 9))),
            ),
          ),
      ],
    );
  }
}

/// Recent weeks as columns, Monday at the top — the dense strip on the stats
/// screen that leads into the full history. [days] must start on a Monday and
/// hold whole weeks.
class WeekColumns extends StatelessWidget {
  const WeekColumns({
    super.key,
    required this.days,
    required this.scale,
    required this.today,
    this.accent = Cy.cyan,
    this.gap = 3,
  });

  final List<DayBucket> days;
  final DotScale scale;
  final DateTime today;
  final Color accent;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final weeks = days.length ~/ 7;
    return Row(
      children: [
        for (var w = 0; w < weeks; w++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gap / 2),
              child: Column(
                children: [
                  for (var d = 0; d < 7; d++)
                    Padding(
                      padding: EdgeInsets.only(bottom: d == 6 ? 0 : gap),
                      child: ActivityDot(
                        level: scale.level(days[w * 7 + d].distanceMeters),
                        future: days[w * 7 + d].day.isAfter(today),
                        today: days[w * 7 + d].day == today,
                        accent: accent,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Distance per calendar month across the whole log, oldest first, with a
/// month initial under each bar and the year where it changes.
class MonthBars extends StatelessWidget {
  const MonthBars({super.key, required this.months, this.accent = Cy.cyan, this.height = 110, this.onMonthTap});

  final List<PeriodStats> months;
  final Color accent;
  final double height;
  final ValueChanged<PeriodStats>? onMonthTap;

  static const _initials = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

  @override
  Widget build(BuildContext context) {
    if (months.isEmpty) return SizedBox(height: height);
    final maxValue = months.fold(0.0, (m, p) => max(m, p.distanceMeters));
    final scale = max(maxValue, 1000.0);
    // Past two years of bars the initials start to overlap; the years still
    // mark the axis.
    final showInitials = months.length <= 24;

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, box) {
          // A young log has two or three months; spreading them across the
          // whole width would draw slabs, so slots stop growing at [maxSlot]
          // and the timeline starts at the left like any other.
          final slot = min(box.maxWidth / months.length, maxSlot);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < months.length; i++)
                SizedBox(
                  width: slot,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onMonthTap == null ? null : () => onMonthTap!(months[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, box) {
                                final m = months[i];
                                final h = (m.distanceMeters / scale * box.maxHeight).clamp(
                                  m.distanceMeters > 0 ? 3.0 : 1.0,
                                  box.maxHeight,
                                );
                                return Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    height: h,
                                    decoration: BoxDecoration(
                                      color: m.distanceMeters > 0 ? accent : Cy.rule,
                                      boxShadow: m.distanceMeters > 0 ? glow(accent, blur: 8, opacity: 0.35) : null,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 5),
                          _axisLabel(i, showInitials),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static const double maxSlot = 44;

  Widget _axisLabel(int i, bool showInitials) {
    final start = months[i].perDay.first.day;
    final newYear = i == 0 || start.month == DateTime.january;
    final initial = showInitials ? _initials[start.month - 1] : '';
    return Column(
      children: [
        Text(initial, style: CyType.label(size: 8)),
        Text(
          newYear ? "'${(start.year % 100).toString().padLeft(2, '0')}" : '',
          style: CyType.mono(size: 8, color: newYear ? Cy.inkDim : Colors.transparent),
        ),
      ],
    );
  }
}
