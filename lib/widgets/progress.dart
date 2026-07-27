import 'dart:math';

import 'package:flutter/material.dart';

import '../models/stats.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/format.dart';

/// The run HUD's centrepiece: a segmented ring showing goal completion, with
/// arbitrary content in the middle.
class GoalRing extends StatelessWidget {
  const GoalRing({
    super.key,
    required this.progress,
    required this.child,
    this.accent = Cy.cyan,
    this.trackColor = Cy.rule,
    this.size = 240,
    this.strokeWidth = 10,
    this.segments = 60,
    this.overtime = false,
  });

  final double progress;
  final Widget child;
  final Color accent;
  final Color trackColor;
  final double size;
  final double strokeWidth;

  /// The ring is drawn as discrete ticks rather than a smooth arc — it reads
  /// as instrumentation instead of a loading spinner.
  final int segments;

  /// Goal already met and the runner kept going.
  final bool overtime;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress.clamp(0.0, 1.0),
          accent: accent,
          track: trackColor,
          strokeWidth: strokeWidth,
          segments: segments,
          overtime: overtime,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.accent,
    required this.track,
    required this.strokeWidth,
    required this.segments,
    required this.overtime,
  });

  final double progress;
  final Color accent;
  final Color track;
  final double strokeWidth;
  final int segments;
  final bool overtime;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = (min(size.width, size.height) - strokeWidth) / 2;
    final filled = (segments * progress).floor();

    for (var i = 0; i < segments; i++) {
      // Start at 12 o'clock and run clockwise, with a small gap between ticks.
      final sweep = 2 * pi / segments;
      final start = -pi / 2 + i * sweep;
      final isOn = i < filled;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = isOn ? accent : track;
      if (isOn && i > filled - 4) {
        // Leading edge glows, so the eye finds "now" instantly.
        paint.maskFilter = const MaskFilter.blur(BlurStyle.solid, 3);
      }
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        start,
        sweep * 0.72,
        false,
        paint,
      );
    }

    if (overtime) {
      canvas.drawCircle(
        centre,
        radius - strokeWidth,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Cy.green.withValues(alpha: 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.accent != accent || old.overtime != overtime;
}

/// The chase HUD: who is chasing, how long is left, and whether the runner is
/// currently winning.
class ChaseBar extends StatelessWidget {
  const ChaseBar({
    super.key,
    required this.pursuer,
    required this.progress,
    required this.secondsLeft,
    required this.winning,
  });

  final String pursuer;
  final double progress;
  final int secondsLeft;
  final bool winning;

  @override
  Widget build(BuildContext context) {
    final accent = winning ? Cy.green : Cy.magenta;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        border: Border.all(color: accent, width: 1.4),
        boxShadow: glow(accent, blur: 24, opacity: 0.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(winning ? Icons.trending_up : Icons.warning_amber_rounded, size: 16, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pursuer.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: CyType.display(size: 12, color: accent, letterSpacing: 2),
                ),
              ),
              Text('${secondsLeft}s', style: CyType.readout(18, accent)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    Container(height: 6, width: box.maxWidth, color: Cy.rule),
                    Container(
                      height: 6,
                      width: box.maxWidth * progress.clamp(0.0, 1.0),
                      decoration: BoxDecoration(color: accent, boxShadow: glow(accent, blur: 10, opacity: 0.6)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            winning ? 'DISTANCE OPENING — HOLD IT' : 'GAINING ON YOU — MOVE',
            style: CyType.mono(size: 10, color: accent, letterSpacing: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Per-day distance bars for the stats screen.
class DayBars extends StatelessWidget {
  const DayBars({super.key, required this.days, this.accent = Cy.cyan, this.height = 92, this.showLabels = true});

  final List<DayBucket> days;
  final Color accent;
  final double height;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return SizedBox(height: height);
    final maxValue = days.fold(0.0, (m, d) => max(m, d.distanceMeters));
    // Every bar being full height when the runner did 300 m one day would be a
    // lie; the axis only starts scaling past a 1 km reference.
    final scale = max(maxValue, 1000.0);

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final h = (day.distanceMeters / scale * box.maxHeight).clamp(
                            day.distanceMeters > 0 ? 3.0 : 1.0,
                            box.maxHeight,
                          );
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height: h,
                                decoration: BoxDecoration(
                                  color: day.distanceMeters > 0 ? accent : Cy.rule,
                                  boxShadow: day.distanceMeters > 0
                                      ? glow(accent, blur: 8, opacity: 0.35)
                                      : null,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    if (showLabels) ...[
                      const SizedBox(height: 5),
                      Text(Fmt.weekdayInitial(day.day), style: CyType.label(size: 9)),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Thin linear progress used on achievement cards.
class ThinBar extends StatelessWidget {
  const ThinBar({super.key, required this.progress, required this.color, this.height = 3});

  final double progress;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => Stack(
        children: [
          Container(height: height, width: box.maxWidth, color: Cy.rule),
          Container(height: height, width: box.maxWidth * progress.clamp(0.0, 1.0), color: color),
        ],
      ),
    );
  }
}

/// Twelve-week streak history: one notch per week, lit where the goal was met.
class StreakStrip extends StatelessWidget {
  const StreakStrip({super.key, required this.weeks});

  final List<bool> weeks;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < weeks.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Container(
                height: 18,
                decoration: BoxDecoration(
                  color: weeks[i] ? Cy.amber.withValues(alpha: 0.85) : Cy.panelHi,
                  border: Border.all(
                    color: weeks[i] ? Cy.amber : Cy.rule,
                    width: i == weeks.length - 1 ? 1.4 : 1,
                  ),
                  boxShadow: weeks[i] ? glow(Cy.amber, blur: 8, opacity: 0.3) : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
