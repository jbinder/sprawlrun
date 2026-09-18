import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/mission.dart';
import '../models/profile.dart';
import '../models/run_record.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/format.dart';
import '../widgets/backdrop.dart';
import '../widgets/glitch_text.dart';
import '../widgets/mission_widgets.dart';
import '../widgets/panels.dart';
import 'mission_brief_screen.dart';
import 'run_detail_screen.dart';

/// A cleared operation, seen afterwards: what it came to, what it yielded, and
/// every attempt on it — each one openable to read its story back.
///
/// The briefing still exists behind "Run it again"; this is what a completed
/// mission opens onto instead, so the campaign reads as a record and not as a
/// list of things still to start.
class MissionDebriefScreen extends StatelessWidget {
  const MissionDebriefScreen({super.key, required this.mission});

  final Mission mission;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final units = state.profile.units;
    const accent = Cy.green;

    final attempts = state.runLog.where((r) => r.missionId == mission.id).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final cleared = attempts.where((r) => r.isSuccess).firstOrNull;
    final campaignFinished = mission.epilogue != null && state.currentMission == null;

    return Scaffold(
      body: GridBackdrop(
        accent: accent,
        child: SafeArea(
          child: Column(
            children: [
              OpsBar(mission: mission, label: 'DEBRIEFING'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                  children: [
                    Text(mission.location.toUpperCase(), style: CyType.label(size: 10, color: accent)),
                    const SizedBox(height: 8),
                    GlitchText(
                      mission.codename,
                      style: CyType.display(size: 30, color: Cy.ink, shadows: textGlow(accent, blur: 18)),
                    ),
                    const SizedBox(height: 6),
                    Text(mission.title, style: CyType.body(size: 17, color: Cy.inkDim)),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Expanded(
                          child: InfoCell(
                            label: 'Cleared',
                            value: cleared == null ? '—' : Fmt.date(cleared.startedAt),
                            icon: Icons.check_circle_outline,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InfoCell(
                            label: 'Attempts',
                            value: '${state.profile.missionAttempts[mission.id] ?? attempts.length}',
                            icon: Icons.replay,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InfoCell(
                            label: 'Best',
                            value: cleared == null ? '—' : Fmt.distance(_bestMeters(attempts), units),
                            icon: Icons.route_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    const SectionHeader('DEBRIEF', accent: Cy.amber),
                    NeonPanel(
                      accent: Cy.rule,
                      child: Text(mission.debrief, style: CyType.body(size: 16, height: 1.5, color: Cy.ink)),
                    ),
                    const SizedBox(height: 18),

                    if (campaignFinished) ...[
                      const SectionHeader('EPILOGUE', accent: Cy.green),
                      NeonPanel(
                        accent: Cy.green,
                        lit: true,
                        child: Text(mission.epilogue!, style: CyType.body(size: 16, height: 1.55, color: Cy.ink)),
                      ),
                      const SizedBox(height: 18),
                    ],

                    if (mission.codex.isNotEmpty) ...[
                      IntelSection(mission: mission, recovered: state.profile.unlockedCodex),
                      const SizedBox(height: 18),
                    ],

                    if (attempts.isNotEmpty) ...[
                      const SectionHeader('RUNS'),
                      for (final run in attempts.reversed) _AttemptRow(run: run, units: units),
                      const SizedBox(height: 18),
                    ],

                    CyberButton(
                      label: 'Run it again',
                      icon: Icons.play_arrow_rounded,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => MissionBriefScreen(mission: mission)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static double _bestMeters(List<RunRecord> attempts) =>
      attempts.map((r) => r.distanceMeters).fold(0.0, (a, b) => a > b ? a : b);
}

/// One attempt on the operation. Tapping opens the run, story and all.
class _AttemptRow extends StatelessWidget {
  const _AttemptRow({required this.run, required this.units});

  final RunRecord run;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    final accent = run.isSuccess ? Cy.green : Cy.amber;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NeonPanel(
        accent: accent,
        cut: 8,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => RunDetailScreen(run: run)),
        ),
        child: Row(
          children: [
            Icon(run.isSuccess ? Icons.verified_outlined : Icons.close, size: 18, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Fmt.dateTime(run.startedAt), style: CyType.body(size: 14, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${Fmt.distanceWithUnit(run.distanceMeters, units)} · ${Fmt.clock(run.elapsedSeconds)}'
                    '${run.story.isEmpty ? '' : ' · story'}',
                    style: CyType.body(size: 12, color: Cy.inkDim, weight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            CyberTag(run.isSuccess ? 'CLEARED' : 'FAILED', color: accent),
          ],
        ),
      ),
    );
  }
}
