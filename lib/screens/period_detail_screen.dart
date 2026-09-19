import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/stats_service.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../widgets/backdrop.dart';
import '../widgets/panels.dart';
import '../widgets/period_card.dart';
import '../widgets/run_row.dart';

/// One day, week or month in full: its totals and every run inside it.
///
/// The window is `[from, to)`. Stats are recomputed from the live run log on
/// every build, so deleting a run from here updates the totals above it.
class PeriodDetailScreen extends StatelessWidget {
  const PeriodDetailScreen({
    super.key,
    required this.label,
    required this.from,
    required this.to,
    this.subtitle,
    this.accent = Cy.cyan,
  });

  final String label;
  final String? subtitle;
  final DateTime from;
  final DateTime to;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final units = state.profile.units;
    final stats = StatsService.period(state.runLog, label: label, from: from, to: to);
    final runs = state.runLog.where((r) => !r.startedAt.isBefore(from) && r.startedAt.isBefore(to)).toList();

    return Scaffold(
      body: GridBackdrop(
        accent: accent,
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
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  children: [
                    PeriodCard(
                      stats: stats,
                      units: units,
                      accent: accent,
                      subtitle: subtitle,
                      compactBars: stats.perDay.length > 7,
                    ),
                    const SizedBox(height: 22),
                    SectionHeader(
                      'RUNS',
                      trailing: Text(
                        '${runs.length} entr${runs.length == 1 ? 'y' : 'ies'}',
                        style: CyType.mono(size: 10, color: Cy.ghost),
                      ),
                    ),
                    if (runs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Nothing logged in this window.', style: CyType.body(size: 13, color: Cy.ghost)),
                      ),
                    for (final run in runs) ...[RunRow(run: run, units: units), const SizedBox(height: 8)],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
