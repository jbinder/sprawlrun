import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../models/run_record.dart';
import '../models/stats.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/format.dart';
import '../widgets/panels.dart';
import '../widgets/progress.dart';
import 'run_detail_screen.dart';

/// Week, month, lifetime, and the run log.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final units = state.profile.units;

    if (state.runLog.isEmpty) {
      return const EmptyState(
        title: 'No telemetry yet',
        body: 'Run one operation and this fills up: distance, time, calories and cleared missions '
            'for the last week and month.',
        icon: Icons.query_stats_outlined,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      children: [
        _PeriodCard(stats: state.week, units: units, accent: Cy.cyan),
        const SizedBox(height: 16),
        _PeriodCard(stats: state.month, units: units, accent: Cy.magenta, compactBars: true),
        const SizedBox(height: 22),

        const SectionHeader('LIFETIME', accent: Cy.amber),
        _LifetimeCard(stats: state.lifetime, units: units),
        const SizedBox(height: 22),

        SectionHeader(
          'RUN LOG',
          trailing: Text('${state.runLog.length} entries', style: CyType.mono(size: 10, color: Cy.ghost)),
        ),
        for (final run in state.runLog.take(40)) ...[
          _RunRow(run: run, units: units),
          const SizedBox(height: 8),
        ],
        if (state.runLog.length > 40)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Showing the 40 most recent of ${state.runLog.length}.',
              style: CyType.body(size: 13, color: Cy.ghost),
            ),
          ),
      ],
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({
    required this.stats,
    required this.units,
    required this.accent,
    this.compactBars = false,
  });

  final PeriodStats stats;
  final UnitSystem units;
  final Color accent;
  final bool compactBars;

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      accent: Cy.rule,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 3, height: 12, color: accent),
              const SizedBox(width: 8),
              Text(stats.label, style: CyType.label(size: 11, color: accent)),
              const Spacer(),
              Text(
                '${stats.runs} run${stats.runs == 1 ? '' : 's'}',
                style: CyType.mono(size: 10, color: Cy.ghost),
              ),
            ],
          ),
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
                child: StatTile(
                  label: 'Missions',
                  value: '${stats.missions}',
                  accent: Cy.green,
                  size: 20,
                ),
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
          const SizedBox(height: 18),
          DayBars(
            days: stats.perDay,
            accent: accent,
            height: compactBars ? 64 : 92,
            showLabels: !compactBars,
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
                child: StatTile(
                  label: 'Total time',
                  value: Fmt.shortDuration(stats.totalSeconds),
                  size: 24,
                ),
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
                child: StatTile(
                  label: 'Missions',
                  value: '${stats.missionsCompleted}',
                  accent: Cy.green,
                  size: 20,
                ),
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
                child: StatTile(
                  label: 'Calories',
                  value: Fmt.grouped(stats.totalCalories),
                  accent: Cy.amber,
                  size: 20,
                ),
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

class _RunRow extends StatelessWidget {
  const _RunRow({required this.run, required this.units});

  final RunRecord run;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    final accent = run.isSuccess ? Cy.green : Cy.magenta;
    return NeonPanel(
      cut: 8,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => RunDetailScreen(run: run)),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 34, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  run.missionCodename ?? 'FREE RUN',
                  overflow: TextOverflow.ellipsis,
                  style: CyType.display(size: 12, color: Cy.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  '${Fmt.dateTime(run.startedAt)} · ${Fmt.pace(run.paceSecondsPerKm, units)}${Fmt.paceUnit(units)}',
                  style: CyType.mono(size: 10, color: Cy.ghost),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Fmt.distanceWithUnit(run.distanceMeters, units), style: CyType.readout(15, Cy.ink)),
              const SizedBox(height: 3),
              Text(Fmt.clock(run.elapsedSeconds), style: CyType.mono(size: 11, color: Cy.inkDim)),
            ],
          ),
        ],
      ),
    );
  }
}
