import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/mission_repository.dart';
import '../models/achievement.dart';
import '../models/profile.dart';
import '../models/stats.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/format.dart';
import '../widgets/glitch_text.dart';
import '../widgets/panels.dart';
import '../widgets/progress.dart';
import 'mission_brief_screen.dart';

/// The home screen: who you are, how the week is going, and the one mission
/// you are allowed to play next.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final chain = state.chain;
    final current = state.currentMission;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      children: [
        _Greeting(callsign: state.profile.callsign),
        const SizedBox(height: 16),
        _StreakCard(streak: state.streak),
        const SizedBox(height: 16),
        _WeekStrip(week: state.week, units: state.profile.units),
        const SizedBox(height: 22),

        if (current != null) ...[
          const SectionHeader('NEXT OPERATION', accent: Cy.magenta),
          _NextOpCard(progress: current),
          const SizedBox(height: 22),
        ] else if (chain.isNotEmpty) ...[
          const SectionHeader('CAMPAIGN COMPLETE', accent: Cy.green),
          const _CampaignCompleteCard(),
          const SizedBox(height: 22),
        ],

        SectionHeader(
          'MISSION CHAIN',
          trailing: Text(
            '${state.missionsCompleted}/${state.missionsTotal}',
            style: CyType.mono(size: 11, color: Cy.inkDim),
          ),
        ),
        if (chain.isEmpty)
          const EmptyState(
            title: 'No mission packs',
            body: 'The bundled campaign failed to load. Check Settings → Mission packs.',
            icon: Icons.sync_problem_outlined,
          )
        else
          for (final entry in chain) ...[
            _MissionRow(progress: entry),
            const SizedBox(height: 8),
          ],

        const SizedBox(height: 14),
        CyberButton(
          label: 'Free run — no mission',
          icon: Icons.directions_run,
          style: CyberButtonStyle.ghost,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MissionBriefScreen(mission: null)),
          ),
        ),
        const SizedBox(height: 20),
        _NextUnlocks(stats: state.lifetime),
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.callsign});

  final String callsign;

  /// Flavour that tracks the clock — the Sprawl is a night city, and the app
  /// should sound like it knows what time it is.
  String get _line {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'The city is at its quietest. Nobody is watching the streets at this hour.';
    if (hour < 8) return 'Grey light on wet concrete. Best hours to move unnoticed.';
    if (hour < 12) return 'Day shift is on the grid. Blend in.';
    if (hour < 17) return 'Heat, noise, and forty thousand people between you and anyone tracking you.';
    if (hour < 21) return 'The signs are coming on. This is when the work starts.';
    return 'Rain on the strip. Good conditions. Nobody looks up when it rains.';
  }

  String get _salutation {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'STILL AWAKE';
    if (hour < 12) return 'MORNING';
    if (hour < 18) return 'AFTERNOON';
    return 'EVENING';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('$_salutation, ', style: CyType.label(size: 11, color: Cy.inkDim)),
            Flexible(
              child: GlitchText(
                callsign.toUpperCase(),
                maxLines: 1,
                style: CyType.display(size: 13, color: Cy.cyan, shadows: textGlow(Cy.cyan, blur: 10)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(_line, style: CyType.body(size: 15, color: Cy.inkDim, height: 1.35)),
      ],
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak});

  final StreakStatus streak;

  @override
  Widget build(BuildContext context) {
    final met = streak.metThisWeek;
    final accent = met ? Cy.amber : Cy.cyanDim;
    return NeonPanel(
      accent: met ? Cy.amber : Cy.rule,
      lit: met,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.local_fire_department, color: accent, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('${streak.weeks}', style: CyType.readout(32, accent)),
                        const SizedBox(width: 6),
                        Text('WEEK STREAK', style: CyType.label(size: 10, color: Cy.inkDim)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      met
                          ? 'Target met. Streak safe.'
                          : '${(streak.target - streak.currentValue).toStringAsFixed(streak.unitLabel == 'KM' ? 1 : 0)} ${streak.unitLabel} to go · closes in ${Fmt.countdown(streak.weekEndsIn)}',
                      style: CyType.body(size: 13, color: Cy.inkDim),
                    ),
                  ],
                ),
              ),
              if (streak.longestWeeks > streak.weeks)
                CyberTag('BEST ${streak.longestWeeks}', color: Cy.ghost),
            ],
          ),
          const SizedBox(height: 14),
          ThinBar(progress: streak.progress, color: accent, height: 4),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${streak.currentValue.toStringAsFixed(streak.unitLabel == 'KM' ? 1 : 0)} / ${streak.target.toStringAsFixed(streak.unitLabel == 'KM' ? 1 : 0)} ${streak.unitLabel}',
                style: CyType.mono(size: 11, color: Cy.inkDim),
              ),
              Text('THIS WEEK', style: CyType.label(size: 9)),
            ],
          ),
          if (streak.recentWeeks.isNotEmpty) ...[
            const SizedBox(height: 14),
            StreakStrip(weeks: streak.recentWeeks),
            const SizedBox(height: 5),
            Text('LAST 12 WEEKS', style: CyType.label(size: 9)),
          ],
        ],
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.week, required this.units});

  final PeriodStats week;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: StatTile(
              label: 'Distance 7d',
              value: Fmt.distance(week.distanceMeters, units),
              unit: Fmt.distanceUnit(units),
              accent: Cy.cyan,
              size: 22,
            ),
          ),
          Expanded(
            child: StatTile(
              label: 'Time 7d',
              value: Fmt.shortDuration(week.seconds),
              accent: Cy.ink,
              size: 22,
            ),
          ),
          Expanded(
            child: StatTile(
              label: 'Ops 7d',
              value: '${week.missions}',
              accent: Cy.magenta,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _NextOpCard extends StatelessWidget {
  const _NextOpCard({required this.progress});

  final MissionProgress progress;

  @override
  Widget build(BuildContext context) {
    final mission = progress.mission;
    return NeonPanel(
      accent: Cy.magenta,
      lit: true,
      padding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => MissionBriefScreen(mission: mission)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: Cy.magenta.withValues(alpha: 0.1),
            child: Row(
              children: [
                Text(
                  'OP ${mission.order.toString().padLeft(2, '0')}',
                  style: CyType.mono(size: 12, color: Cy.magenta, letterSpacing: 2),
                ),
                const Spacer(),
                if (progress.attempts > 0) CyberTag('ATTEMPT ${progress.attempts + 1}', color: Cy.amber),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlitchText(
                  mission.codename,
                  style: CyType.display(size: 22, color: Cy.ink, shadows: textGlow(Cy.magenta, blur: 14)),
                ),
                const SizedBox(height: 6),
                Text(mission.title, style: CyType.body(size: 16, color: Cy.inkDim)),
                const SizedBox(height: 2),
                Text(mission.location.toUpperCase(), style: CyType.label(size: 9, color: Cy.ghost)),
                const SizedBox(height: 14),
                Text(mission.objective, style: CyType.body(size: 15, height: 1.4)),
                const SizedBox(height: 16),
                // Wrap rather than Row: the chips carry variable-length text
                // and must not overflow on a narrow screen or at a large
                // system font scale.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Chip(icon: Icons.flag_outlined, text: mission.suggestedGoal.toString()),
                    _Chip(icon: Icons.record_voice_over_outlined, text: '${mission.beats.length} transmissions'),
                    _Chip(
                      icon: Icons.radar,
                      text: '${mission.chaseBeats.length} pursuit${mission.chaseBeats.length == 1 ? '' : 's'}',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('OPEN BRIEFING', style: CyType.display(size: 12, color: Cy.magenta)),
                    const Icon(Icons.chevron_right, size: 18, color: Cy.magenta),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: Cy.panelHi, border: Border.all(color: Cy.rule)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Cy.inkDim),
          const SizedBox(width: 5),
          Text(text, style: CyType.mono(size: 10, color: Cy.inkDim)),
        ],
      ),
    );
  }
}

class _CampaignCompleteCard extends StatelessWidget {
  const _CampaignCompleteCard();

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      accent: Cy.green,
      lit: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ALL OPERATIONS CLEARED', style: CyType.display(size: 14, color: Cy.green)),
          const SizedBox(height: 8),
          Text(
            'Sprawl Prime is finished. Free runs still count toward streaks, distance and the wall — '
            'and new mission packs can be dropped in without an update.',
            style: CyType.body(size: 15, color: Cy.inkDim, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _MissionRow extends StatelessWidget {
  const _MissionRow({required this.progress});

  final MissionProgress progress;

  @override
  Widget build(BuildContext context) {
    final mission = progress.mission;
    final locked = progress.state == MissionState.locked;
    final done = progress.state == MissionState.completed;
    final accent = switch (progress.state) {
      MissionState.completed => Cy.green,
      MissionState.available => Cy.magenta,
      MissionState.locked => Cy.rule,
    };

    return NeonPanel(
      accent: accent,
      fill: locked ? Cy.v0id : Cy.panel,
      cut: 10,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: locked
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => MissionBriefScreen(mission: mission)),
            ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Icon(
              done
                  ? Icons.check_circle_outline
                  : locked
                  ? Icons.lock_outline
                  : Icons.play_circle_outline,
              color: locked ? Cy.ghost : accent,
              size: 22,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      mission.order.toString().padLeft(2, '0'),
                      style: CyType.mono(size: 11, color: locked ? Cy.ghost : Cy.inkDim),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        // A locked mission's codename is redacted so the story
                        // is not spoiled by the list itself.
                        locked ? '█████████' : mission.codename,
                        overflow: TextOverflow.ellipsis,
                        style: CyType.display(size: 13, color: locked ? Cy.ghost : Cy.ink),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  locked ? 'CLASSIFIED — CLEAR PRECEDING OPERATION' : mission.title,
                  overflow: TextOverflow.ellipsis,
                  style: CyType.body(size: 13, color: locked ? Cy.ghost : Cy.inkDim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (done)
            CyberTag('CLEARED', color: Cy.green)
          else if (!locked)
            CyberTag('ACTIVE', color: Cy.magenta, filled: true)
          else
            CyberTag('LOCKED', color: Cy.ghost),
        ],
      ),
    );
  }
}

class _NextUnlocks extends StatelessWidget {
  const _NextUnlocks({required this.stats});

  final LifetimeStats stats;

  @override
  Widget build(BuildContext context) {
    final next = context.read<AppState>().achievementWall.where((v) => !v.earned && v.progress > 0).take(3).toList();
    if (next.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('CLOSEST UNLOCKS', accent: Cy.amber),
        for (final view in next)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: NeonPanel(
              cut: 8,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(view.def.category.icon, size: 14, color: view.def.tier.color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(view.def.title, style: CyType.body(size: 14, weight: FontWeight.w700)),
                      ),
                      Text(view.def.progressLabel(stats), style: CyType.mono(size: 10, color: Cy.inkDim)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ThinBar(progress: view.progress, color: view.def.tier.color),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
