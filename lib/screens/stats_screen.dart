import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../models/run_record.dart';
import '../models/stats.dart';
import '../services/stats_service.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/format.dart';
import '../widgets/history_widgets.dart';
import '../widgets/panels.dart';
import '../widgets/period_card.dart';
import '../widgets/run_row.dart';
import 'history_screen.dart';
import 'period_detail_screen.dart';

/// Week, month, lifetime, and the run log.
///
/// The week and month cards page through the calendar: swipe or use the
/// chevrons to look at any earlier week or month back to the first run. The
/// long-term picture lives one tap further, on [HistoryScreen].
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final units = state.profile.units;

    if (state.runLog.isEmpty) {
      return const EmptyState(
        title: 'No telemetry yet',
        body:
            'Run one operation and this fills up: distance, time, calories and cleared missions '
            'for this week and this month, and a history you can page back through.',
        icon: Icons.query_stats_outlined,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      children: [
        const _PeriodPager(unit: _PeriodUnit.week, accent: Cy.cyan),
        const SizedBox(height: 16),
        const _PeriodPager(unit: _PeriodUnit.month, accent: Cy.magenta),
        const SizedBox(height: 22),

        const SectionHeader('HISTORY', accent: Cy.green),
        const _HistoryTeaser(),
        const SizedBox(height: 22),

        const SectionHeader('LIFETIME', accent: Cy.amber),
        _LifetimeCard(stats: state.lifetime, units: units),
        const SizedBox(height: 22),

        SectionHeader(
          'RUN LOG',
          trailing: Text('${state.runLog.length} entries', style: CyType.mono(size: 10, color: Cy.ghost)),
        ),
        _RunLog(runs: state.runLog, units: units),
      ],
    );
  }
}

/// The most recent runs in full, then everything older folded into one
/// collapsible group per month — so a year of running is a dozen lines, not
/// a wall.
class _RunLog extends StatefulWidget {
  const _RunLog({required this.runs, required this.units});

  /// Newest first, as the repository returns it.
  final List<RunRecord> runs;
  final UnitSystem units;

  /// How many of the newest runs are always shown.
  static const int recent = 10;

  @override
  State<_RunLog> createState() => _RunLogState();
}

class _RunLogState extends State<_RunLog> {
  final Set<DateTime> _open = {};

  @override
  Widget build(BuildContext context) {
    final recent = widget.runs.take(_RunLog.recent);
    final older = widget.runs.skip(_RunLog.recent);

    // Group by calendar month, preserving newest-first order.
    final groups = <DateTime, List<RunRecord>>{};
    for (final run in older) {
      groups.putIfAbsent(StatsService.monthStart(run.startedAt), () => []).add(run);
    }

    return Column(
      children: [
        for (final run in recent) ...[RunRow(run: run, units: widget.units), const SizedBox(height: 8)],
        for (final entry in groups.entries) ...[
          _MonthGroup(
            month: entry.key,
            runs: entry.value,
            units: widget.units,
            open: _open.contains(entry.key),
            onToggle: () => setState(() {
              if (!_open.remove(entry.key)) _open.add(entry.key);
            }),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _MonthGroup extends StatelessWidget {
  const _MonthGroup({
    required this.month,
    required this.runs,
    required this.units,
    required this.open,
    required this.onToggle,
  });

  final DateTime month;
  final List<RunRecord> runs;
  final UnitSystem units;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final meters = runs.fold(0.0, (s, r) => s + r.distanceMeters);
    return Column(
      children: [
        NeonPanel(
          cut: 8,
          fill: open ? Cy.panelHi : Cy.panel,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          onTap: onToggle,
          child: Row(
            children: [
              Container(width: 3, height: 22, color: open ? Cy.cyan : Cy.ghost),
              const SizedBox(width: 12),
              Text(Fmt.monthYear(month), style: CyType.display(size: 12, color: open ? Cy.ink : Cy.inkDim)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${runs.length} run${runs.length == 1 ? '' : 's'} · ${Fmt.distanceWithUnit(meters, units)}',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: CyType.mono(size: 10, color: Cy.ghost),
                ),
              ),
              const SizedBox(width: 6),
              Icon(open ? Icons.expand_less : Icons.expand_more, size: 16, color: Cy.inkDim),
            ],
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 10),
            child: Column(
              children: [
                for (final run in runs) ...[RunRow(run: run, units: units), const SizedBox(height: 8)],
              ],
            ),
          ),
      ],
    );
  }
}

enum _PeriodUnit { week, month }

/// A [PeriodCard] that steps through calendar weeks or months.
///
/// Only the offset from the current period is state, so a run logged while
/// the screen is open — or a day rolling over — still shows the right window.
class _PeriodPager extends StatefulWidget {
  const _PeriodPager({required this.unit, required this.accent});

  final _PeriodUnit unit;
  final Color accent;

  @override
  State<_PeriodPager> createState() => _PeriodPagerState();
}

class _PeriodPagerState extends State<_PeriodPager> {
  /// 0 is the current period, 1 the one before it, and so on.
  int _back = 0;

  bool get _isWeek => widget.unit == _PeriodUnit.week;

  DateTime _startOf(DateTime d) => _isWeek ? StatsService.weekStart(d) : StatsService.monthStart(d);

  DateTime _shift(DateTime start, int n) =>
      _isWeek ? StatsService.addDays(start, 7 * n) : StatsService.addMonths(start, n);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final now = DateTime.now();
    final current = _startOf(now);
    final start = _shift(current, -_back);
    final end = _shift(start, 1);

    // Nothing to page to before the first run's period.
    final first = state.lifetime.firstRunAt;
    final oldest = first == null ? current : _startOf(first);
    final canGoOlder = start.isAfter(oldest);

    final label = switch (_back) {
      0 => _isWeek ? 'THIS WEEK' : 'THIS MONTH',
      1 => _isWeek ? 'LAST WEEK' : 'LAST MONTH',
      _ => '$_back ${_isWeek ? 'WEEKS' : 'MONTHS'} AGO',
    };
    final subtitle = _isWeek ? Fmt.dateRange(start, StatsService.addDays(end, -1)) : Fmt.monthYear(start);
    final stats = StatsService.period(state.runLog, label: label, from: start, to: end);

    return PeriodCard(
      stats: stats,
      units: state.profile.units,
      accent: widget.accent,
      subtitle: subtitle,
      compactBars: !_isWeek,
      pager: PeriodPager(
        onOlder: canGoOlder ? () => setState(() => _back++) : null,
        onNewer: _back > 0 ? () => setState(() => _back--) : null,
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              PeriodDetailScreen(label: label, subtitle: subtitle, from: start, to: end, accent: widget.accent),
        ),
      ),
    );
  }
}

/// The last sixteen weeks as a dot strip; tapping opens the full history.
class _HistoryTeaser extends StatelessWidget {
  const _HistoryTeaser();

  static const _weeks = 16;

  @override
  Widget build(BuildContext context) {
    final runLog = context.select<AppState, List<RunRecord>>((s) => s.runLog);
    final today = StatsService.dayStart(DateTime.now());
    final thisWeek = StatsService.weekStart(today);
    final window = StatsService.period(
      runLog,
      label: '',
      from: StatsService.addDays(thisWeek, -7 * (_weeks - 1)),
      to: StatsService.addDays(thisWeek, 7),
    );
    final activeDays = window.perDay.where((d) => d.runs > 0).length;

    return NeonPanel(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HistoryScreen())),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 3, height: 12, color: Cy.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'LAST $_weeks WEEKS',
                  overflow: TextOverflow.ellipsis,
                  style: CyType.label(size: 11, color: Cy.green),
                ),
              ),
              const SizedBox(width: 8),
              Text('$activeDays ACTIVE DAYS', style: CyType.mono(size: 10, color: Cy.ghost)),
            ],
          ),
          const SizedBox(height: 14),
          WeekColumns(days: window.perDay, scale: DotScale.of(window.perDay), today: today, accent: Cy.green),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('FULL HISTORY', style: CyType.mono(size: 10, color: Cy.inkDim, letterSpacing: 1.4)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 14, color: Cy.inkDim),
            ],
          ),
        ],
      ),
    );
  }
}

class _LifetimeCard extends StatelessWidget {
  const _LifetimeCard({required this.stats, required this.units});

  final LifetimeStats stats;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Total distance',
                  value: Fmt.distance(stats.totalDistanceMeters, units),
                  unit: Fmt.distanceUnit(units),
                  accent: Cy.cyan,
                  size: 24,
                ),
              ),
              Expanded(
                child: StatTile(label: 'Total time', value: Fmt.shortDuration(stats.totalSeconds), size: 24),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: StatTile(label: 'Runs', value: '${stats.totalRuns}', size: 20),
              ),
              Expanded(
                child: StatTile(label: 'Missions', value: '${stats.missionsCompleted}', accent: Cy.green, size: 20),
              ),
              Expanded(
                child: StatTile(
                  label: 'Evaded',
                  value: '${stats.chasesEvaded}/${stats.chasesTotal}',
                  accent: Cy.magenta,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Longest run',
                  value: Fmt.distance(stats.longestRunMeters, units),
                  unit: Fmt.distanceUnit(units),
                  size: 20,
                ),
              ),
              Expanded(
                child: StatTile(
                  label: 'Best pace',
                  value: Fmt.pace(stats.bestPaceSecondsPerKm, units),
                  unit: Fmt.paceUnit(units),
                  size: 20,
                ),
              ),
              Expanded(
                child: StatTile(label: 'Calories', value: Fmt.grouped(stats.totalCalories), accent: Cy.amber, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: Cy.rule),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.local_fire_department_outlined, size: 13, color: Cy.ghost),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'BEST STREAK ${stats.longestStreakWeeks}W',
                  overflow: TextOverflow.ellipsis,
                  style: CyType.mono(size: 11, color: Cy.ghost),
                ),
              ),
              const SizedBox(width: 8),
              Text('${stats.distinctDays} ACTIVE DAYS', style: CyType.mono(size: 11, color: Cy.ghost)),
            ],
          ),
        ],
      ),
    );
  }
}
