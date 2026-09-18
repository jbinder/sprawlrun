import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/achievement.dart';
import '../models/mission.dart';
import '../models/profile.dart';
import '../models/run_record.dart';
import '../models/run_outcome.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/format.dart';
import '../widgets/backdrop.dart';
import '../widgets/glitch_text.dart';
import '../widgets/panels.dart';
import '../widgets/route_trace.dart';
import '../widgets/unlock_reveal.dart';

/// Post-run debrief: what happened, what it earned, and what it opened up.
///
/// Anything the run unlocked is shown first as a full-screen sequence, one card
/// at a time, before the numbers. The list further down repeats it for the
/// record; the sequence is the moment.
class RunSummaryScreen extends StatefulWidget {
  const RunSummaryScreen({
    super.key,
    required this.report,
    required this.mission,
  });

  final RunOutcomeReport report;
  final Mission? mission;

  @override
  State<RunSummaryScreen> createState() => _RunSummaryScreenState();
}

class _RunSummaryScreenState extends State<RunSummaryScreen> {
  late bool _revealing = widget.report.hasUnlocks;

  RunOutcomeReport get report => widget.report;
  Mission? get mission => widget.mission;

  /// Wall order: what the campaign opened, then the story, then the medals.
  List<Unlock> get _unlocks => [
    if (report.missionUnlocked != null) Unlock.mission(report.missionUnlocked!),
    for (final entry in report.codexRecovered) Unlock.codex(entry),
    for (final def in report.newAchievements) Unlock.achievement(def),
  ];

  @override
  Widget build(BuildContext context) {
    final record = report.record;
    final units = context.select<AppState, UnitSystem>((s) => s.profile.units);
    final success = record.isSuccess;
    final accent = success ? Cy.green : Cy.magenta;
    final campaignFinished =
        success &&
        mission?.epilogue != null &&
        context.read<AppState>().currentMission == null;
    final nextPack = campaignFinished
        ? context.read<AppState>().nextOpenPack
        : null;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            GridBackdrop(
              accent: accent,
              child: SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
                        children: [
                          Text(
                            mission == null
                                ? 'RUN LOGGED'
                                : 'OPERATION ${mission!.order.toString().padLeft(2, '0')}',
                            style: CyType.label(size: 10, color: Cy.inkDim),
                          ),
                          const SizedBox(height: 8),
                          GlitchText(
                            success ? 'SUCCESS' : 'FAILED',
                            alwaysOn: !success,
                            style: CyType.display(
                              size: 34,
                              color: accent,
                              shadows: textGlow(accent, blur: 20),
                            ),
                          ),
                          if (mission != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${mission!.codename} — ${mission!.title}',
                              style: CyType.body(size: 16, color: Cy.inkDim),
                            ),
                          ],
                          const SizedBox(height: 20),

                          _SummaryGrid(record: record, units: units),
                          const SizedBox(height: 16),

                          if (record.trace.length > 1) ...[
                            const SectionHeader('ROUTE'),
                            RouteTrace(trace: record.trace, accent: accent),
                            const SizedBox(height: 16),
                          ],

                          if (record.chasesTotal > 0) ...[
                            const SectionHeader('PURSUITS', accent: Cy.magenta),
                            NeonPanel(
                              child: Row(
                                children: [
                                  Icon(
                                    record.chasesEvaded == record.chasesTotal
                                        ? Icons.verified_outlined
                                        : Icons.report_gmailerrorred_outlined,
                                    color:
                                        record.chasesEvaded ==
                                            record.chasesTotal
                                        ? Cy.green
                                        : Cy.amber,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      record.chasesEvaded == record.chasesTotal
                                          ? 'Clean run. Every pursuit shaken.'
                                          : 'Evaded ${record.chasesEvaded} of ${record.chasesTotal}.',
                                      style: CyType.body(size: 15),
                                    ),
                                  ),
                                  Text(
                                    '${record.chasesEvaded}/${record.chasesTotal}',
                                    style: CyType.readout(20, Cy.magenta),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (success && mission != null) ...[
                            const SectionHeader('DEBRIEF', accent: Cy.amber),
                            NeonPanel(
                              accent: Cy.rule,
                              child: Text(
                                mission!.debrief,
                                style: CyType.body(
                                  size: 16,
                                  height: 1.5,
                                  color: Cy.ink,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (campaignFinished) ...[
                            const SectionHeader('EPILOGUE', accent: Cy.green),
                            NeonPanel(
                              accent: Cy.green,
                              lit: true,
                              child: Text(
                                mission!.epilogue!,
                                style: CyType.body(
                                  size: 16,
                                  height: 1.55,
                                  color: Cy.ink,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // The story is over; offer the next one while the
                            // runner is still standing here, rather than leaving
                            // them to find it on the ops screen.
                            if (nextPack != null) ...[
                              const SectionHeader(
                                'NEXT CAMPAIGN',
                                accent: Cy.magenta,
                              ),
                              NeonPanel(
                                accent: Cy.magenta,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      nextPack.title,
                                      style: CyType.display(
                                        size: 16,
                                        color: Cy.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      nextPack.tagline,
                                      style: CyType.body(
                                        size: 15,
                                        color: Cy.inkDim,
                                        height: 1.35,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    CyberButton(
                                      label: 'Switch to ${nextPack.title}',
                                      icon: Icons.swap_horiz_rounded,
                                      dense: true,
                                      onPressed: () {
                                        context.read<AppState>().selectPack(
                                          nextPack.id,
                                        );
                                        Navigator.of(
                                          context,
                                        ).popUntil((route) => route.isFirst);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ],

                          if (!success && mission != null) ...[
                            NeonPanel(
                              accent: Cy.amber,
                              child: Row(
                                children: [
                                  const Icon(Icons.replay, color: Cy.amber),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'The operation stays open. Everything you covered still counts toward '
                                      'your totals and your streak.',
                                      style: CyType.body(
                                        size: 15,
                                        color: Cy.inkDim,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (report.missionUnlocked != null) ...[
                            NeonPanel(
                              accent: Cy.magenta,
                              lit: true,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.lock_open_outlined,
                                    color: Cy.magenta,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'NEW OPERATION UNLOCKED',
                                          style: CyType.label(
                                            size: 10,
                                            color: Cy.magenta,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          report.missionUnlocked!,
                                          style: CyType.display(
                                            size: 16,
                                            color: Cy.ink,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (report.codexLost.isNotEmpty) ...[
                            const SectionHeader('INTEL LOST', accent: Cy.amber),
                            NeonPanel(
                              accent: Cy.amber,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Intercepted but not decrypted. Complete the operation to recover:',
                                    style: CyType.body(
                                      size: 14,
                                      color: Cy.inkDim,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  for (final entry in report.codexLost)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.lock_outline,
                                            size: 15,
                                            color: Cy.amber,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              entry.title,
                                              style: CyType.body(
                                                size: 15,
                                                weight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          CyberTag(
                                            entry.category,
                                            color: Cy.amber,
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (report.codexRecovered.isNotEmpty) ...[
                            const SectionHeader('RECOVERED', accent: Cy.cyan),
                            for (final entry in report.codexRecovered)
                              _UnlockRow(
                                accent: Cy.cyan,
                                icon: Icons.memory_outlined,
                                title: entry.title,
                                subtitle: entry.category,
                              ),
                            const SizedBox(height: 8),
                          ],

                          if (report.newAchievements.isNotEmpty) ...[
                            const SectionHeader('UNLOCKED', accent: Cy.amber),
                            for (final def in report.newAchievements)
                              _UnlockRow(
                                accent: Unlock.achievement(def).accent,
                                icon: def.category.icon,
                                title: def.title,
                                subtitle:
                                    '${def.tier.label} — ${def.description}',
                              ),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                      child: CyberButton(
                        label: 'Return to ops',
                        icon: Icons.grid_view_rounded,
                        onPressed: () => Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_revealing)
              UnlockReveal(
                unlocks: _unlocks,
                onShow: (_) => context.read<AppState>().narrator.sfx('unlock'),
                onDone: () => setState(() => _revealing = false),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.record, required this.units});

  final RunRecord record;
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
                  label: 'Distance',
                  value: Fmt.distance(record.distanceMeters, units),
                  unit: Fmt.distanceUnit(units),
                  accent: Cy.cyan,
                ),
              ),
              Expanded(
                child: StatTile(
                  label: 'Time',
                  value: Fmt.clock(record.elapsedSeconds),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Avg pace',
                  value: Fmt.pace(record.paceSecondsPerKm, units),
                  unit: Fmt.paceUnit(units),
                  size: 22,
                ),
              ),
              Expanded(
                child: StatTile(
                  label: 'Calories',
                  value: Fmt.calories(record.calories),
                  unit: 'kcal',
                  accent: Cy.amber,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Target',
                  value: record.goal.toString(),
                  size: 18,
                  accent: Cy.inkDim,
                ),
              ),
              Expanded(
                child: StatTile(
                  label: 'Transmissions',
                  value: '${record.beatsHeard}',
                  size: 18,
                  accent: Cy.inkDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: Cy.rule),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.schedule, size: 13, color: Cy.ghost),
              const SizedBox(width: 8),
              Text(
                Fmt.dateTime(record.startedAt),
                style: CyType.mono(size: 11, color: Cy.ghost),
              ),
              const Spacer(),
              Text(
                'MOVING ${Fmt.shortDuration(record.movingSeconds)}',
                style: CyType.mono(size: 11, color: Cy.ghost),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One earned thing in the debrief list — the reveal already had its moment,
/// this is the record.
class _UnlockRow extends StatelessWidget {
  const _UnlockRow({
    required this.accent,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NeonPanel(
        accent: accent,
        cut: 8,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: CyType.body(size: 15, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: CyType.body(
                      size: 12,
                      color: Cy.inkDim,
                      weight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
