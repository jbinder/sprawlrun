import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../models/stats.dart';
import '../services/stats_service.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/format.dart';
import '../widgets/backdrop.dart';
import '../widgets/history_widgets.dart';
import '../widgets/panels.dart';
import 'period_detail_screen.dart';

/// The whole log at a glance: distance per month since the first run, then
/// every month as a dot calendar. Months and lit days open in detail.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final units = state.profile.units;
    final today = StatsService.dayStart(DateTime.now());
    // Oldest first for the bars, newest first for the blocks below them.
    final months = StatsService.monthlyHistory(state.runLog, now: today);
    final scale = DotScale.of(months.expand((m) => m.perDay));
    final lifetime = state.lifetime;

    return Scaffold(
      body: GridBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, color: Cy.inkDim),
                  ),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  // Header panel, then one block per month.
                  itemCount: months.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('LONG-TERM', style: CyType.label(size: 10)),
                          const SizedBox(height: 8),
                          Text(
                            'HISTORY',
                            style: CyType.display(size: 26, color: Cy.ink, shadows: textGlow(Cy.cyan, blur: 14)),
                          ),
                          const SizedBox(height: 8),
                          if (lifetime.firstRunAt != null)
                            Text(
                              'SINCE ${Fmt.date(lifetime.firstRunAt!)} ${lifetime.firstRunAt!.year} · '
                              '${lifetime.distinctDays} ACTIVE DAYS · ${lifetime.totalRuns} RUNS',
                              style: CyType.mono(size: 10, color: Cy.inkDim),
                            ),
                          const SizedBox(height: 18),
                          _MonthlyDistanceCard(months: months, units: units),
                          const SizedBox(height: 22),
                          SectionHeader('BY MONTH', accent: Cy.green, trailing: const _Legend()),
                        ],
                      );
                    }
                    final month = months[months.length - i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _MonthBlock(month: month, units: units, scale: scale, today: today),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthlyDistanceCard extends StatelessWidget {
  const _MonthlyDistanceCard({required this.months, required this.units});

  final List<PeriodStats> months;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    PeriodStats? best;
    for (final m in months) {
      if (best == null || m.distanceMeters > best.distanceMeters) best = m;
    }
    return NeonPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 3, height: 12, color: Cy.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'DISTANCE BY MONTH',
                  overflow: TextOverflow.ellipsis,
                  style: CyType.label(size: 11, color: Cy.cyan),
                ),
              ),
            ],
          ),
          if (best != null && best.distanceMeters > 0) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 11),
              child: Text(
                'BEST ${best.label} · ${Fmt.distanceWithUnit(best.distanceMeters, units)}',
                overflow: TextOverflow.ellipsis,
                style: CyType.mono(size: 10, color: Cy.inkDim),
              ),
            ),
          ],
          const SizedBox(height: 16),
          MonthBars(months: months, onMonthTap: (m) => _openMonth(context, m)),
        ],
      ),
    );
  }
}

/// Header line with the month's totals, then its dot calendar.
class _MonthBlock extends StatelessWidget {
  const _MonthBlock({required this.month, required this.units, required this.scale, required this.today});

  final PeriodStats month;
  final UnitSystem units;
  final DotScale scale;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final active = month.runs > 0;
    return NeonPanel(
      cut: 10,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      onTap: () => _openMonth(context, month),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(month.label, style: CyType.display(size: 12, color: active ? Cy.ink : Cy.inkDim)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  active
                      ? '${month.runs} RUN${month.runs == 1 ? '' : 'S'} · '
                            '${Fmt.distanceWithUnit(month.distanceMeters, units)} · '
                            '${Fmt.shortDuration(month.seconds)}'
                      : 'NO RUNS',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: CyType.mono(size: 10, color: active ? Cy.inkDim : Cy.ghost),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 14, color: Cy.ghost),
            ],
          ),
          const SizedBox(height: 10),
          // Dots, not a wall calendar: the grid stops growing at a comfortable
          // tap size and sits centred in whatever width is left.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 7 * 30),
              child: Column(
                children: [
                  const WeekdayHeader(),
                  const SizedBox(height: 4),
                  MonthDots(
                    days: month.perDay,
                    scale: scale,
                    today: today,
                    onDayTap: (day) => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PeriodDetailScreen(
                          label: '${Fmt.weekday(day.day)} ${Fmt.date(day.day)} ${day.day.year}',
                          from: day.day,
                          to: StatsService.addDays(day.day, 1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('LESS', style: CyType.label(size: 8)),
        const SizedBox(width: 5),
        for (var level = 0; level <= 4; level++)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: SizedBox(width: 9, child: ActivityDot(level: level)),
          ),
        const SizedBox(width: 2),
        Text('MORE', style: CyType.label(size: 8)),
      ],
    );
  }
}

void _openMonth(BuildContext context, PeriodStats month) {
  final start = month.perDay.first.day;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          PeriodDetailScreen(label: month.label, from: start, to: StatsService.addMonths(start, 1), accent: Cy.magenta),
    ),
  );
}
