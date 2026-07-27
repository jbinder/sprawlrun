import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/goal.dart';
import '../models/mission.dart';
import '../models/profile.dart';
import '../services/location_service.dart';
import '../services/run_engine.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/format.dart';
import '../widgets/backdrop.dart';
import '../widgets/glitch_text.dart';
import '../widgets/panels.dart';
import '../widgets/progress.dart';
import 'run_summary_screen.dart';

/// The live run. Everything on this screen is legible at arm's length while
/// moving, which drives the type sizes and the very small number of controls.
class RunScreen extends StatefulWidget {
  const RunScreen({super.key, required this.mission, required this.goal});

  final Mission? mission;
  final RunGoal goal;

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  StreamSubscription<RunEvent>? _events;
  String? _banner;
  Timer? _bannerTimer;
  LocationReadiness? _locationTrouble;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  Future<void> _begin() async {
    final engine = context.read<RunEngine>();
    final app = context.read<AppState>();

    if (app.profile.keepScreenOn) {
      unawaited(WakelockPlus.enable());
    }

    _events = engine.events.listen(_onEvent);
    final readiness = await engine.start(
      mission: widget.mission,
      goal: widget.goal,
      profile: app.profile,
    );
    if (mounted && readiness != LocationReadiness.ready) {
      setState(() => _locationTrouble = readiness);
    }
  }

  void _onEvent(RunEvent event) {
    if (!mounted) return;
    switch (event) {
      case BeatEvent(:final beat):
        if (beat.headline != null) _flash(beat.headline!);
      case ChaseStarted(:final chase):
        _flash('PURSUIT — ${chase.spec.pursuer}');
      case ChaseEnded(:final escaped, :final pursuer):
        _flash(escaped ? 'EVADED — $pursuer' : 'CAUGHT — $pursuer');
      case GoalReached():
        _flash('TARGET REACHED');
      case CodexUnlocked():
        _flash('CODEX ENTRY RECOVERED');
      case LocationTrouble(:final readiness):
        setState(() => _locationTrouble = readiness);
    }
  }

  void _flash(String text) {
    _bannerTimer?.cancel();
    setState(() => _banner = text);
    _bannerTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _events?.cancel();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  Future<void> _end({required bool confirmed}) async {
    if (_finishing) return;
    final engine = context.read<RunEngine>();

    if (!confirmed && !engine.goalReached) {
      final abandon = await showDialog<bool>(
        context: context,
        builder: (context) => _AbortDialog(mission: widget.mission),
      );
      if (abandon != true || !mounted) return;
    }

    _finishing = true;
    final app = context.read<AppState>();
    final codex = List<String>.from(engine.codexUnlocked);
    final record = await engine.finish();
    final report = await app.completeRun(record, mission: widget.mission, codexHeard: codex);

    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => RunSummaryScreen(report: report, mission: widget.mission),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<RunEngine>();
    final units = context.select<AppState, UnitSystem>((s) => s.profile.units);
    final chase = engine.activeChase;
    final accent = chase != null ? Cy.magenta : (engine.goalReached ? Cy.green : Cy.cyan);

    return PopScope(
      // Backing out of a live run by accident would lose it. The only ways out
      // are the explicit controls at the bottom of the screen.
      canPop: false,
      child: Scaffold(
        body: GridBackdrop(
          accent: accent,
          intensity: 0.55,
          child: SafeArea(
            child: Column(
              children: [
                _RunHeader(engine: engine, mission: widget.mission),
                if (_locationTrouble != null) _LocationWarning(readiness: _locationTrouble!),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                    child: Column(
                      children: [
                        if (_banner != null) ...[
                          _Banner(text: _banner!, accent: accent),
                          const SizedBox(height: 14),
                        ],
                        _PrimaryReadout(engine: engine, units: units, accent: accent),
                        const SizedBox(height: 18),
                        if (chase != null) ...[
                          ChaseBar(
                            pursuer: chase.spec.pursuer,
                            progress: chase.progress,
                            secondsLeft:
                                (chase.spec.duration.inSeconds -
                                        (engine.elapsedSeconds - chase.startedAtElapsed))
                                    .clamp(0, 999)
                                    .round(),
                            winning: chase.isWinning,
                          ),
                          const SizedBox(height: 16),
                        ],
                        _Telemetry(engine: engine, units: units),
                        const SizedBox(height: 16),
                        _TransmissionPanel(engine: engine),
                      ],
                    ),
                  ),
                ),
                _Controls(engine: engine, onEnd: _end),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RunHeader extends StatelessWidget {
  const _RunHeader({required this.engine, required this.mission});

  final RunEngine engine;
  final Mission? mission;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (engine.phase) {
      RunPhase.running => ('TRACKING', Cy.green),
      RunPhase.paused => ('PAUSED', Cy.amber),
      RunPhase.autoPaused => ('AUTO-PAUSED', Cy.amber),
      RunPhase.finished => ('CLOSED', Cy.ghost),
      RunPhase.idle => ('STANDBY', Cy.ghost),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mission == null ? 'FREE RUN' : 'OP ${mission!.order.toString().padLeft(2, '0')}',
                  style: CyType.label(size: 9),
                ),
                const SizedBox(height: 3),
                Text(
                  mission?.codename ?? 'UNLOGGED',
                  overflow: TextOverflow.ellipsis,
                  style: CyType.display(size: 14, color: Cy.ink),
                ),
              ],
            ),
          ),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: glow(color, blur: 8, opacity: 0.8),
            ),
          ),
          const SizedBox(width: 7),
          Text(label, style: CyType.label(size: 10, color: color)),
        ],
      ),
    );
  }
}

class _LocationWarning extends StatelessWidget {
  const _LocationWarning({required this.readiness});

  final LocationReadiness readiness;

  @override
  Widget build(BuildContext context) {
    final message = switch (readiness) {
      LocationReadiness.serviceDisabled => 'Location services are off. Distance will not be recorded.',
      LocationReadiness.denied => 'Location permission denied. Distance will not be recorded.',
      LocationReadiness.deniedForever =>
        'Location permission is permanently denied. Enable it in system settings to record distance.',
      LocationReadiness.ready => '',
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: Cy.amber.withValues(alpha: 0.1), border: Border.all(color: Cy.amber)),
      child: Row(
        children: [
          const Icon(Icons.satellite_alt_outlined, size: 15, color: Cy.amber),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '$message Time-based targets still work.',
              style: CyType.body(size: 13, color: Cy.amber),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: GlitchText(
        text,
        alwaysOn: true,
        style: CyType.display(size: 13, color: accent, letterSpacing: 2.4),
      ),
    );
  }
}

/// The ring. Shows whichever quantity the goal is measured in, big, with the
/// other one underneath.
class _PrimaryReadout extends StatelessWidget {
  const _PrimaryReadout({required this.engine, required this.units, required this.accent});

  final RunEngine engine;
  final UnitSystem units;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isTime = engine.goal.isTime;
    final primary = isTime
        ? Fmt.clock(engine.elapsedSeconds)
        : Fmt.distance(engine.distanceMeters, units);
    final primaryUnit = isTime ? '' : Fmt.distanceUnit(units);
    final secondary = isTime
        ? '${Fmt.distance(engine.distanceMeters, units)} ${Fmt.distanceUnit(units)}'
        : Fmt.clock(engine.elapsedSeconds);

    return GoalRing(
      progress: engine.progress,
      accent: accent,
      size: 250,
      overtime: engine.goalReached,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            engine.goalReached ? 'TARGET MET' : 'TARGET ${engine.goal}',
            style: CyType.label(size: 9, color: engine.goalReached ? Cy.green : Cy.inkDim),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(primary, style: CyType.readout(50, Cy.ink)),
              if (primaryUnit.isNotEmpty) ...[
                const SizedBox(width: 5),
                Text(primaryUnit, style: CyType.mono(size: 15, color: Cy.inkDim)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(secondary, style: CyType.mono(size: 15, color: Cy.inkDim)),
          const SizedBox(height: 10),
          Text(
            '${(engine.progress * 100).clamp(0, 100).round()}%',
            style: CyType.mono(size: 12, color: accent, letterSpacing: 2),
          ),
        ],
      ),
    );
  }
}

class _Telemetry extends StatelessWidget {
  const _Telemetry({required this.engine, required this.units});

  final RunEngine engine;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: StatTile(
              label: 'Pace now',
              value: Fmt.pace(engine.currentPaceSecondsPerKm, units),
              unit: Fmt.paceUnit(units),
              size: 20,
              accent: Cy.cyan,
            ),
          ),
          Expanded(
            child: StatTile(
              label: 'Avg pace',
              value: Fmt.pace(engine.paceSecondsPerKm, units),
              unit: Fmt.paceUnit(units),
              size: 20,
            ),
          ),
          Expanded(
            child: StatTile(
              label: 'Kcal',
              value: Fmt.calories(engine.calories),
              size: 20,
              accent: Cy.amber,
            ),
          ),
        ],
      ),
    );
  }
}

/// The story, on screen, for anyone running without headphones — and as a
/// transcript for anything missed while the wind was loud.
class _TransmissionPanel extends StatelessWidget {
  const _TransmissionPanel({required this.engine});

  final RunEngine engine;

  @override
  Widget build(BuildContext context) {
    final line = engine.currentLine;
    final history = engine.transcript.reversed.take(6).toList();

    if (engine.mission == null) {
      return NeonPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: [
            const Icon(Icons.music_note_outlined, size: 16, color: Cy.ghost),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Free run — nothing will interrupt your audio.',
                style: CyType.body(size: 14, color: Cy.ghost),
              ),
            ),
          ],
        ),
      );
    }

    return NeonPanel(
      accent: line != null ? Cy.speaker(line.speaker) : Cy.rule,
      lit: line != null,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                line != null ? Icons.graphic_eq : Icons.podcasts_outlined,
                size: 14,
                color: line != null ? Cy.speaker(line.speaker) : Cy.ghost,
              ),
              const SizedBox(width: 8),
              Text(
                line != null ? line.speaker.toUpperCase() : 'CHANNEL IDLE',
                style: CyType.label(size: 10, color: line != null ? Cy.speaker(line.speaker) : Cy.ghost),
              ),
              const Spacer(),
              Text('${engine.beatsHeard} RX', style: CyType.mono(size: 9, color: Cy.ghost)),
            ],
          ),
          const SizedBox(height: 10),
          if (line != null)
            TypewriterText(
              line.text,
              key: ValueKey(line.text),
              style: CyType.body(size: 16, height: 1.4, color: Cy.ink),
            )
          else if (history.isEmpty)
            Text(
              'Waiting for the first transmission. Keep moving.',
              style: CyType.body(size: 15, color: Cy.ghost),
            )
          else
            for (final past in history.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RichText(
                  text: TextSpan(
                    style: CyType.body(size: 13, color: Cy.ghost, height: 1.3),
                    children: [
                      TextSpan(
                        text: '${past.speaker.toUpperCase()}  ',
                        style: CyType.mono(size: 11, color: Cy.speaker(past.speaker).withValues(alpha: 0.7)),
                      ),
                      TextSpan(text: past.text),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.engine, required this.onEnd});

  final RunEngine engine;
  final Future<void> Function({required bool confirmed}) onEnd;

  @override
  Widget build(BuildContext context) {
    final paused = engine.phase == RunPhase.paused || engine.phase == RunPhase.autoPaused;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      decoration: const BoxDecoration(
        color: Cy.v0id,
        border: Border(top: BorderSide(color: Cy.rule)),
      ),
      child: Column(
        children: [
          if (engine.goalReached) ...[
            CyberButton(
              label: engine.mission == null ? 'Finish run' : 'Complete operation',
              icon: Icons.check_rounded,
              onPressed: () => onEnd(confirmed: true),
            ),
            const SizedBox(height: 10),
            Text(
              'Target met. You can keep running — everything past this point still counts.',
              textAlign: TextAlign.center,
              style: CyType.body(size: 13, color: Cy.green),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: CyberButton(
                  label: paused ? 'Resume' : 'Pause',
                  icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  style: CyberButtonStyle.ghost,
                  onPressed: paused ? engine.resume : engine.pause,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CyberButton(
                  label: engine.goalReached ? 'End' : 'Abort',
                  icon: Icons.stop_rounded,
                  style: CyberButtonStyle.danger,
                  onPressed: () => onEnd(confirmed: engine.goalReached),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AbortDialog extends StatelessWidget {
  const _AbortDialog({required this.mission});

  final Mission? mission;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: NeonPanel(
        accent: Cy.magenta,
        lit: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ABORT?', style: CyType.display(size: 18, color: Cy.magenta)),
            const SizedBox(height: 12),
            Text(
              mission == null
                  ? 'You have not reached your target. The run will be logged as a failure.'
                  : 'You have not reached your target. ${mission!.codename} will be logged as failed — '
                        'the distance and time still count, and you can run it again.',
              style: CyType.body(size: 15, color: Cy.inkDim, height: 1.35),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: CyberButton(
                    label: 'Keep going',
                    style: CyberButtonStyle.ghost,
                    dense: true,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: CyberButton(
                    label: 'Abort',
                    style: CyberButtonStyle.danger,
                    dense: true,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
