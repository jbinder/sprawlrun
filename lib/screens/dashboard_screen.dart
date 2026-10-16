import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/active_run_store.dart';
import '../data/mission_repository.dart';
import '../models/achievement.dart';
import '../models/mission.dart';
import '../models/profile.dart';
import '../models/stats.dart';
import '../services/backup_nudge.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../theme/season.dart';
import '../util/clock.dart';
import '../util/format.dart';
import '../widgets/backdrop.dart';
import '../widgets/backup_controls.dart';
import '../widgets/glitch_text.dart';
import '../widgets/panels.dart';
import '../widgets/progress.dart';
import 'mission_brief_screen.dart';
import 'mission_debrief_screen.dart';
import 'missions_screen.dart';
import 'run_summary_screen.dart';
import '../l10n/l10n.dart';

/// The home screen: who you are, how the week is going, and the one mission
/// you are allowed to play next.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final chain = state.chain;
    final current = state.currentMission;
    final pack = state.activePack;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      children: [
        _Greeting(callsign: state.profile.callsign, season: state.season),
        // Room for the pumpkin perched on the card, clear of the greeting.
        SizedBox(height: state.seasonalPack == null ? 16 : 30),
        if (state.seasonalPack case final event?) ...[
          PumpkinPerch(
            right: 54,
            size: 26,
            child: _SeasonCard(
              season: state.season!,
              pack: event,
              playing: pack?.id == event.id,
              finished: state.packProgress.any((p) => p.pack.id == event.id && p.isDone),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (state.interruptedRun case final saved?) ...[
          _InterruptedRunCard(saved: saved),
          const SizedBox(height: 16),
        ],
        PumpkinPerch(left: 40, size: 21, child: _StreakCard(streak: state.streak)),
        const SizedBox(height: 16),
        _WeekStrip(week: state.week, units: state.profile.units),
        const SizedBox(height: 22),

        if (state.backupNudge case final nudge?) ...[
          _BackupNudgeCard(nudge: nudge),
          const SizedBox(height: 22),
        ],

        if (current != null) ...[
          SectionHeader(L.of(context).nextOperation, accent: Cy.magenta),
          _NextOpCard(progress: current),
          const SizedBox(height: 22),
        ] else if (chain.isNotEmpty) ...[
          SectionHeader(L.of(context).campaignComplete, accent: Cy.green),
          _CampaignCompleteCard(pack: pack!, next: state.nextOpenPack),
          const SizedBox(height: 22),
        ],

        SectionHeader(
          pack?.title ?? L.of(context).missionChain,
          trailing: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MissionsScreen()),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${state.missionsCompleted}/${state.missionsTotal}',
                    style: CyType.mono(size: 11, color: Cy.inkDim),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    L.of(context).allPacks,
                    style: CyType.label(size: 10, color: Cy.cyan),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: Cy.cyan),
                ],
              ),
            ),
          ),
        ),
        if (pack != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              pack.tagline,
              style: CyType.body(size: 13, color: Cy.inkDim),
            ),
          ),
        ],
        if (chain.isEmpty)
          EmptyState(
            title: L.of(context).noPacksTitle,
            body: L.of(context).noPacksBundledFailed,
            icon: Icons.sync_problem_outlined,
          )
        else
          for (final entry in chain) ...[
            _MissionRow(progress: entry),
            const SizedBox(height: 8),
          ],

        const SizedBox(height: 14),
        CyberButton(
          label: L.of(context).freeRunButton,
          icon: Icons.directions_run,
          style: CyberButtonStyle.ghost,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const MissionBriefScreen(mission: null),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _NextUnlocks(stats: state.lifetime),
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.callsign, this.season});

  final String callsign;
  final Season? season;

  /// Flavour that tracks the clock — the Sprawl is a night city, and the app
  /// should sound like it knows what time it is.
  String get _line {
    final hour = appNow().hour;
    if (season == Season.samhain) return _samhainLine(hour);
    if (hour < 5) return l10n.greetingLineNight;
    if (hour < 8) return l10n.greetingLineDawn;
    if (hour < 12) return l10n.greetingLineMorning;
    if (hour < 17) return l10n.greetingLineAfternoon;
    if (hour < 21) return l10n.greetingLineEvening;
    return l10n.greetingLineLate;
  }

  /// The same clock, the week the dead accounts walk.
  static String _samhainLine(int hour) {
    if (hour < 5) return l10n.samhainLineNight;
    if (hour < 8) return l10n.samhainLineDawn;
    if (hour < 12) return l10n.samhainLineMorning;
    if (hour < 17) return l10n.samhainLineAfternoon;
    if (hour < 21) return l10n.samhainLineEvening;
    return l10n.samhainLineLate;
  }

  String get _salutation {
    final hour = appNow().hour;
    if (season == Season.samhain && hour >= 18) return l10n.salutationSamhain;
    if (hour < 5) return l10n.salutationNight;
    if (hour < 12) return l10n.salutationMorning;
    if (hour < 18) return l10n.salutationAfternoon;
    return l10n.salutationEvening;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              L.of(context).salutation(_salutation),
              style: CyType.label(size: 11, color: Cy.inkDim),
            ),
            Flexible(
              child: GlitchText(
                callsign.toUpperCase(),
                maxLines: 1,
                style: CyType.display(
                  size: 13,
                  color: Cy.cyan,
                  shadows: textGlow(Cy.cyan, blur: 10),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _line,
          style: CyType.body(size: 15, color: Cy.inkDim, height: 1.35),
        ),
      ],
    );
  }
}

/// The season's event, at the top of the dashboard while it lasts: what is
/// happening, until when, and one tap to play it.
class _SeasonCard extends StatelessWidget {
  const _SeasonCard({required this.season, required this.pack, required this.playing, required this.finished});

  final Season season;
  final MissionPack pack;

  /// Whether the event pack is already the one on the ops screen.
  final bool playing;

  /// Whether every operation in it is cleared, so there is nothing to carry
  /// over when the season closes.
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final until = season.until;
    final last = DateTime(appNow().year, until.month, until.day);
    return NeonPanel(
      accent: Cy.magenta,
      lit: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.nights_stay_outlined, size: 16, color: Cy.magenta),
              const SizedBox(width: 8),
              Expanded(
                child: GlitchText(
                  season.title,
                  maxLines: 1,
                  style: CyType.display(size: 13, color: Cy.ink, shadows: textGlow(Cy.magenta, blur: 12)),
                ),
              ),
              Text(
                L.of(context).seasonUntil(Fmt.date(last)),
                style: CyType.label(size: 10, color: Cy.magenta),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(pack.tagline, style: CyType.body(size: 15, color: Cy.inkDim, height: 1.35)),
          // Progress is kept across years, but nothing else tells the runner
          // so; without this the card simply vanishes mid-story.
          if (!finished && season.daysLeft(appNow()) <= 3) ...[
            const SizedBox(height: 8),
            Text(
              L.of(context).seasonLastDays,
              style: CyType.body(size: 13, color: Cy.amber, height: 1.35),
            ),
          ],
          if (!playing) ...[
            const SizedBox(height: 12),
            CyberButton(
              label: L.of(context).openPack(pack.title),
              icon: Icons.nights_stay_outlined,
              dense: true,
              onPressed: () => context.read<AppState>().selectPack(pack.id),
            ),
          ],
        ],
      ),
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
                        Text(
                          '${streak.weeks}',
                          style: CyType.readout(32, accent),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          L.of(context).weekStreak,
                          style: CyType.label(size: 10, color: Cy.inkDim),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      met
                          ? L.of(context).streakTargetMet
                          : L.of(context).streakToGo(
                              (streak.target - streak.currentValue).toStringAsFixed(streak.unitLabel == 'KM' ? 1 : 0),
                              L.of(context).streakUnit(streak.unitLabel),
                              Fmt.countdown(streak.weekEndsIn),
                            ),
                      style: CyType.body(size: 13, color: Cy.inkDim),
                    ),
                  ],
                ),
              ),
              if (streak.longestWeeks > streak.weeks)
                CyberTag(L.of(context).streakBest(streak.longestWeeks), color: Cy.ghost),
            ],
          ),
          const SizedBox(height: 14),
          ThinBar(progress: streak.progress, color: accent, height: 4),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${streak.currentValue.toStringAsFixed(streak.unitLabel == 'KM' ? 1 : 0)} / ${streak.target.toStringAsFixed(streak.unitLabel == 'KM' ? 1 : 0)} ${L.of(context).streakUnit(streak.unitLabel)}',
                style: CyType.mono(size: 11, color: Cy.inkDim),
              ),
              Text(L.of(context).thisWeek, style: CyType.label(size: 9)),
            ],
          ),
          if (streak.recentWeeks.isNotEmpty) ...[
            const SizedBox(height: 14),
            StreakStrip(weeks: streak.recentWeeks),
            const SizedBox(height: 5),
            Text(L.of(context).lastWeeks(12), style: CyType.label(size: 9)),
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
              label: L.of(context).statDistance7d,
              value: Fmt.distance(week.distanceMeters, units),
              unit: Fmt.distanceUnit(units),
              accent: Cy.cyan,
              size: 22,
            ),
          ),
          Expanded(
            child: StatTile(
              label: L.of(context).statTime7d,
              value: Fmt.shortDuration(week.seconds),
              accent: Cy.ink,
              size: 22,
            ),
          ),
          Expanded(
            child: StatTile(
              label: L.of(context).statOps7d,
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
        MaterialPageRoute<void>(
          builder: (_) => MissionBriefScreen(mission: mission),
        ),
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
                  L.of(context).opNumber(mission.order.toString().padLeft(2, '0')),
                  style: CyType.mono(
                    size: 12,
                    color: Cy.magenta,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                if (progress.attempts > 0)
                  CyberTag(L.of(context).attemptNumber(progress.attempts + 1), color: Cy.amber),
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
                  style: CyType.display(
                    size: 22,
                    color: Cy.ink,
                    shadows: textGlow(Cy.magenta, blur: 14),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  mission.title,
                  style: CyType.body(size: 16, color: Cy.inkDim),
                ),
                const SizedBox(height: 2),
                Text(
                  mission.location.toUpperCase(),
                  style: CyType.label(size: 9, color: Cy.ghost),
                ),
                const SizedBox(height: 14),
                Text(
                  mission.objective,
                  style: CyType.body(size: 15, height: 1.4),
                ),
                const SizedBox(height: 16),
                // Wrap rather than Row: the chips carry variable-length text
                // and must not overflow on a narrow screen or at a large
                // system font scale.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Chip(
                      icon: Icons.flag_outlined,
                      text: mission.suggestedGoal.toString(),
                    ),
                    _Chip(
                      icon: Icons.record_voice_over_outlined,
                      text: L.of(context).transmissionCount(mission.beats.length),
                    ),
                    _Chip(
                      icon: Icons.radar,
                      text: L.of(context).pursuitCount(mission.chaseBeats.length),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      L.of(context).openBriefing,
                      style: CyType.display(size: 12, color: Cy.magenta),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Cy.magenta,
                    ),
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
      decoration: BoxDecoration(
        color: Cy.panelHi,
        border: Border.all(color: Cy.rule),
      ),
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
  const _CampaignCompleteCard({required this.pack, required this.next});

  final MissionPack pack;

  /// The pack to offer, if anything is still open elsewhere.
  final MissionPack? next;

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      accent: Cy.green,
      lit: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L.of(context).allOperationsCleared,
            style: CyType.display(size: 14, color: Cy.green),
          ),
          const SizedBox(height: 8),
          Text(
            next == null
                ? L.of(context).campaignFinishedAll(pack.title)
                : L.of(context).campaignFinishedNext(pack.title, next!.title, next!.tagline),
            style: CyType.body(size: 15, color: Cy.inkDim, height: 1.35),
          ),
          if (next != null) ...[
            const SizedBox(height: 14),
            CyberButton(
              label: L.of(context).switchToPack(next!.title),
              icon: Icons.swap_horiz_rounded,
              dense: true,
              onPressed: () => context.read<AppState>().selectPack(next!.id),
            ),
          ],
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
      // A cleared operation opens onto its debriefing; the briefing is still
      // there behind "Run it again".
      onTap: locked
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => done
                    ? MissionDebriefScreen(mission: mission)
                    : MissionBriefScreen(mission: mission),
              ),
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
                      style: CyType.mono(
                        size: 11,
                        color: locked ? Cy.ghost : Cy.inkDim,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        // A locked mission's codename is redacted so the story
                        // is not spoiled by the list itself.
                        locked ? '█████████' : mission.codename,
                        overflow: TextOverflow.ellipsis,
                        style: CyType.display(
                          size: 13,
                          color: locked ? Cy.ghost : Cy.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  locked
                      ? L.of(context).classified
                      : mission.title,
                  overflow: TextOverflow.ellipsis,
                  style: CyType.body(
                    size: 13,
                    color: locked ? Cy.ghost : Cy.inkDim,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (done)
            CyberTag(L.of(context).tagCleared, color: Cy.green)
          else if (!locked)
            CyberTag(L.of(context).activeTag, color: Cy.magenta, filled: true)
          else
            CyberTag(L.of(context).tagLocked, color: Cy.ghost),
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
    final next = context
        .read<AppState>()
        .achievementWall
        .where((v) => !v.earned && v.progress > 0)
        .take(3)
        .toList();
    if (next.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(L.of(context).closestUnlocks, accent: Cy.amber),
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
                      Icon(
                        view.def.category.icon,
                        size: 14,
                        color: view.def.tier.color,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          view.def.title,
                          style: CyType.body(size: 14, weight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        view.def.progressLabel(stats),
                        style: CyType.mono(size: 10, color: Cy.inkDim),
                      ),
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

/// Asks the runner to export, once the log holds enough that losing it would
/// hurt.
///
/// Amber and plain-spoken rather than in-world: this is the app's own business,
/// and the failure it guards against is real — any uninstall takes the private
/// data directory with it, and there is no copy anywhere else.
class _BackupNudgeCard extends StatefulWidget {
  const _BackupNudgeCard({required this.nudge});

  final BackupNudge nudge;

  @override
  State<_BackupNudgeCard> createState() => _BackupNudgeCardState();
}

class _BackupNudgeCardState extends State<_BackupNudgeCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final runs = widget.nudge.runsAtRisk;

    return NeonPanel(
      accent: Cy.amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Cy.amber, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(L.of(context).archiveDrift, style: CyType.label(size: 11, color: Cy.amber)),
              ),
              InkWell(
                onTap: _busy ? null : () => state.snoozeBackupNudge(),
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: Cy.inkDim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            L.of(context).archiveDriftBody(runs),
            style: CyType.body(size: 13, color: Cy.ghost, height: 1.4),
          ),
          const SizedBox(height: 14),
          CyberButton(
            label: _busy ? L.of(context).working : L.of(context).exportNow,
            icon: Icons.file_upload_outlined,
            style: CyberButtonStyle.ghost,
            dense: true,
            onPressed: _busy ? null : () => _export(state, runs),
          ),
        ],
      ),
    );
  }

  Future<void> _export(AppState state, int runs) async {
    setState(() => _busy = true);
    try {
      final message = await exportBackup(state, runs);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L.of(context).exportFailed('$e'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// A run the app died in the middle of, offered back. Swiping the app away no
/// longer ends a run, but the process can still be killed — and before this, a
/// run that never reached its finish was simply gone.
class _InterruptedRunCard extends StatefulWidget {
  const _InterruptedRunCard({required this.saved});

  final ActiveRunSnapshot saved;

  @override
  State<_InterruptedRunCard> createState() => _InterruptedRunCardState();
}

class _InterruptedRunCardState extends State<_InterruptedRunCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final run = widget.saved.record;
    final what = run.missionCodename ?? L.of(context).freeRunName;

    return NeonPanel(
      accent: Cy.amber,
      lit: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.restore, color: Cy.amber, size: 18),
              const SizedBox(width: 10),
              Text(L.of(context).runInterrupted, style: CyType.label(size: 11, color: Cy.amber)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$what · ${Fmt.distanceWithUnit(run.distanceMeters, state.profile.units)} · '
            '${Fmt.clock(run.elapsedSeconds)}',
            style: CyType.body(size: 16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            L.of(context).runInterruptedBody(Fmt.dateTime(run.endedAt)),
            style: CyType.body(size: 13, color: Cy.ghost, height: 1.4),
          ),
          const SizedBox(height: 14),
          CyberButton(
            label: _busy ? L.of(context).working : L.of(context).keepRun,
            icon: Icons.save_outlined,
            dense: true,
            onPressed: _busy ? null : () => _keep(state),
          ),
          const SizedBox(height: 8),
          CyberButton(
            label: L.of(context).discard,
            style: CyberButtonStyle.ghost,
            dense: true,
            onPressed: _busy ? null : () => _discard(state),
          ),
        ],
      ),
    );
  }

  Future<void> _keep(AppState state) async {
    setState(() => _busy = true);
    try {
      final id = widget.saved.record.missionId;
      final mission = id == null ? null : state.missionById(id);
      final report = await state.keepInterruptedRun();
      if (!mounted || report == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => RunSummaryScreen(report: report, mission: mission)),
      );
    } on Object catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L.of(context).keepRunFailed('$e'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard(AppState state) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: NeonPanel(
          accent: Cy.red,
          lit: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L.of(context).discardRunTitle, style: CyType.display(size: 16, color: Cy.red)),
              const SizedBox(height: 10),
              Text(
                L.of(context).discardRunBody,
                style: CyType.body(size: 14, color: Cy.ink, height: 1.4),
              ),
              const SizedBox(height: 18),
              CyberButton(
                label: L.of(context).discard,
                style: CyberButtonStyle.danger,
                dense: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 10),
              CyberButton(
                label: L.of(context).cancel,
                style: CyberButtonStyle.ghost,
                dense: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
    if (sure == true) await state.discardInterruptedRun();
  }
}
