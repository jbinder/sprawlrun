import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../models/stats.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/format.dart';
import 'panels.dart';
import 'progress.dart';

/// Totals for one window of time, with a per-day bar chart underneath.
///
/// With [pager] set the header grows `‹ ›` controls and the card answers a
/// horizontal swipe, so the runner can step through earlier weeks or months.
class PeriodCard extends StatelessWidget {
  const PeriodCard({
    super.key,
    required this.stats,
    required this.units,
    required this.accent,
    this.subtitle,
    this.compactBars = false,
    this.pager,
    this.onTap,
  });

  final PeriodStats stats;
  final UnitSystem units;
  final Color accent;

  /// The absolute dates under a relative label — `15 – 21 SEP 2026` under
  /// `THIS WEEK`.
  final String? subtitle;
  final bool compactBars;
  final PeriodPager? pager;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final runs = Text('${stats.runs} run${stats.runs == 1 ? '' : 's'}', style: CyType.mono(size: 10, color: Cy.ghost));

    final card = NeonPanel(
      accent: Cy.rule,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 3, height: 12, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stats.label,
                  overflow: TextOverflow.ellipsis,
                  style: CyType.label(size: 11, color: accent),
                ),
              ),
              if (pager != null) ...[
                _Chevron(Icons.chevron_left, onPressed: pager!.onOlder, tooltip: 'Earlier'),
                _Chevron(Icons.chevron_right, onPressed: pager!.onNewer, tooltip: 'Later'),
              ] else
                runs,
            ],
          ),
          if (subtitle != null || pager != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 11),
              child: Row(
                children: [
                  if (subtitle != null)
                    Expanded(
                      child: Text(
                        subtitle!,
                        overflow: TextOverflow.ellipsis,
                        style: CyType.mono(size: 10, color: Cy.inkDim),
                      ),
                    )
                  else
                    const Spacer(),
                  if (pager != null) runs,
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Distance',
                  value: Fmt.distance(stats.distanceMeters, units),
                  unit: Fmt.distanceUnit(units),
                  accent: accent,
                  size: 24,
                ),
              ),
              Expanded(
                child: StatTile(label: 'Time', value: Fmt.shortDuration(stats.seconds), size: 24),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Calories',
                  value: Fmt.grouped(stats.calories),
                  unit: 'kcal',
                  accent: Cy.amber,
                  size: 20,
                ),
              ),
              Expanded(
                child: StatTile(label: 'Missions', value: '${stats.missions}', accent: Cy.green, size: 20),
              ),
              Expanded(
                child: StatTile(
                  label: 'Avg pace',
                  value: Fmt.pace(stats.paceSecondsPerKm, units),
                  unit: Fmt.paceUnit(units),
                  size: 20,
                ),
              ),
            ],
          ),
          // A single day has nothing to chart.
          if (stats.perDay.length > 1) ...[
            const SizedBox(height: 18),
            DayBars(days: stats.perDay, accent: accent, height: compactBars ? 64 : 92, showLabels: !compactBars),
          ],
        ],
      ),
    );

    if (pager == null) return card;
    return GestureDetector(
      // A fling left reveals the older period, mirroring how the chevrons read.
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -_flingVelocity) pager!.onOlder?.call();
        if (v > _flingVelocity) pager!.onNewer?.call();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
        child: KeyedSubtree(key: ValueKey(stats.label + (subtitle ?? '')), child: card),
      ),
    );
  }

  static const double _flingVelocity = 250;
}

/// Callbacks for stepping a [PeriodCard] through time. A null callback draws
/// its chevron disabled: there is nothing older than the first run, and
/// nothing newer than now.
class PeriodPager {
  const PeriodPager({this.onOlder, this.onNewer});

  final VoidCallback? onOlder;
  final VoidCallback? onNewer;
}

class _Chevron extends StatelessWidget {
  const _Chevron(this.icon, {required this.onPressed, required this.tooltip});

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      color: Cy.inkDim,
      disabledColor: Cy.ghost.withValues(alpha: 0.5),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    );
    if (onPressed != null) return button;
    // A disabled button lets the tap through to the card, which would open
    // the detail screen for a press that meant "go further back".
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}, child: button);
  }
}
