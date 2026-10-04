import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/goal.dart';
import '../models/mission.dart';
import '../models/profile.dart';
import '../models/run_record.dart';
import 'energy.dart';
import 'geo.dart';
import 'location_service.dart';
import 'split_readout.dart';
import 'narrator.dart';

enum RunPhase {
  idle,

  /// Tracking and counting.
  running,

  /// Stopped by the runner.
  paused,

  /// Stopped by the app because the runner stopped moving.
  autoPaused,

  finished,
}

/// A pursuit in progress.
class ActiveChase {
  ActiveChase({
    required this.spec,
    required this.startedAtElapsed,
    required this.startDistance,
    required this.requiredMeters,
  });

  final ChaseSpec spec;
  final double startedAtElapsed;
  final double startDistance;

  /// How far the runner must cover inside the window to escape.
  final double requiredMeters;

  double covered = 0;

  double get progress => requiredMeters <= 0 ? 1 : (covered / requiredMeters).clamp(0.0, 1.0);
  bool get isWinning => progress >= 1.0;
}

/// Transient things the HUD reacts to.
sealed class RunEvent {
  const RunEvent();
}

class BeatEvent extends RunEvent {
  const BeatEvent(this.beat);
  final StoryBeat beat;
}

class ChaseStarted extends RunEvent {
  const ChaseStarted(this.chase);
  final ActiveChase chase;
}

class ChaseEnded extends RunEvent {
  const ChaseEnded(this.escaped, this.pursuer);
  final bool escaped;
  final String pursuer;
}

class GoalReached extends RunEvent {
  const GoalReached();
}

/// A free run passed another kilometre (or mile).
class SplitReached extends RunEvent {
  const SplitReached({required this.count, required this.splitSeconds, required this.metric});

  /// How many whole units have now been covered.
  final int count;

  /// How long the last one took.
  final double splitSeconds;
  final bool metric;
}

class CodexUnlocked extends RunEvent {
  const CodexUnlocked(this.entryId);
  final String entryId;
}

/// Fixes have stopped being possible, and why.
class LocationTrouble extends RunEvent {
  const LocationTrouble(this.readiness);
  final LocationReadiness readiness;
}

/// Fixes are arriving again after a [LocationTrouble].
///
/// Its own event rather than `LocationTrouble(ready)`, which would be a
/// contradiction in terms. Emitted on the first fix of any quality, because the
/// warning is about there being no fixes at all — and that is also the moment
/// the warning stops being true, since nothing is recorded until a fix lands.
class LocationRestored extends RunEvent {
  const LocationRestored();
}

/// Drives a single run: consumes position fixes, maintains distance/time/pace,
/// fires story beats against goal progress, and adjudicates chases.
///
/// Deliberately owns no persistence and no UI. It is fed a [LocationSource]
/// and a [Narrator], so a test can run a whole 25-minute mission in
/// milliseconds against synthetic fixes.
class RunEngine extends ChangeNotifier {
  RunEngine({required this.narrator, required this.location, DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final Narrator narrator;
  final LocationSource location;
  final DateTime Function() _now;

  // -- tuning ---------------------------------------------------------------

  /// Fixes worse than this are dropped outright.
  static const double maxAcceptableAccuracy = 35;

  /// Movement below this is treated as GPS noise rather than distance.
  static const double minStepMeters = 2.0;

  /// Faster than this between two fixes means the fix is wrong, not the runner.
  static const double maxPlausibleSpeed = 12.5;

  /// Below this the runner is considered stopped.
  static const double movingThresholdMps = 0.65;

  /// How fast the speed estimate bleeds toward zero during a second with no
  /// qualifying movement.
  static const double speedDecayPerSecond = 0.45;

  /// How long the runner must be still before auto-pause engages.
  static const Duration autoPauseAfter = Duration(seconds: 25);

  /// Fixes older than this mean the GPS is effectively dead.
  static const Duration fixStaleAfter = Duration(seconds: 30);

  /// Minimum silence between two interludes, so beats never stack up.
  static const Duration minBeatGap = Duration(seconds: 45);

  /// Window used to estimate the runner's current pace when a chase opens.
  static const double chaseBaselineWindow = 180;

  // -- state ----------------------------------------------------------------

  RunPhase phase = RunPhase.idle;
  Mission? mission;
  RunGoal goal = RunGoal.defaultGoal;
  Profile profile = const Profile();

  DateTime? startedAt;
  double distanceMeters = 0;
  double movingSeconds = 0;
  double smoothedSpeed = 0;

  /// True once the target has been met. The run may continue afterwards.
  bool goalReached = false;

  ActiveChase? activeChase;
  StoryBeat? currentBeat;
  StoryLine? currentLine;

  int chasesTotal = 0;
  int chasesEvaded = 0;
  int beatsHeard = 0;

  final List<TracePoint> trace = [];
  final List<String> codexUnlocked = [];

  /// Lines already delivered this run, newest last — the HUD transcript.
  final List<StoryLine> transcript = [];

  /// Every story moment this run, in order — persisted so the run can be read
  /// back afterwards. References only; see [StoryEvent].
  final List<StoryEvent> story = [];

  void _log(StoryEventKind kind, {String? ref, bool? escaped}) {
    story.add(StoryEvent(atSeconds: elapsedSeconds, kind: kind, ref: ref, escaped: escaped));
  }

  /// Whether the runner is currently being shown a location warning. Held so
  /// the warning is raised and cleared once each, on the change rather than on
  /// every fix or every repeated complaint from the provider.
  bool _locationTroubled = false;

  final _events = StreamController<RunEvent>.broadcast();
  Stream<RunEvent> get events => _events.stream;

  Duration _accumulated = Duration.zero;
  DateTime? _segmentStart;
  GeoFix? _lastFix;
  DateTime? _lastFixAt;
  DateTime? _stillSince;
  DateTime? _lastBeatEndedAt;
  bool _beatPlaying = false;

  /// Whole kilometres (or miles) crossed, and the elapsed time of the last
  /// crossing.
  int _splitsDone = 0;
  double _lastSplitAt = 0;

  /// The same for the last one read out. Behind the two above while a
  /// readout waits for the story to finish.
  int _spokenSplits = 0;
  double _spokenSplitAt = 0;
  double _lastTracePointAt = -999;
  double _distanceAtLastTick = 0;
  int _implausibleStreak = 0;

  final Set<String> _firedBeats = {};
  final List<_PaceSample> _paceSamples = [];

  Timer? _ticker;
  StreamSubscription<GeoFix>? _fixSub;
  StreamSubscription<NarrationEvent>? _narrationSub;

  // -- derived --------------------------------------------------------------

  double get elapsedSeconds {
    final base = _accumulated.inMilliseconds / 1000.0;
    if (phase == RunPhase.running && _segmentStart != null) {
      return base + _now().difference(_segmentStart!).inMilliseconds / 1000.0;
    }
    return base;
  }

  double get progress => goal.progress(elapsedSeconds: elapsedSeconds, distanceMeters: distanceMeters);

  double get remaining => goal.remaining(elapsedSeconds: elapsedSeconds, distanceMeters: distanceMeters);

  /// Seconds per kilometre over the whole run so far.
  double get paceSecondsPerKm => distanceMeters < 20 ? 0 : elapsedSeconds / (distanceMeters / 1000.0);

  /// Seconds per kilometre right now, from the smoothed speed.
  double get currentPaceSecondsPerKm => smoothedSpeed < 0.3 ? 0 : 1000.0 / smoothedSpeed;

  double get calories =>
      Energy.kcal(distanceMeters: distanceMeters, seconds: elapsedSeconds, weightKg: profile.weightKg);

  bool get isActive => phase == RunPhase.running || phase == RunPhase.paused || phase == RunPhase.autoPaused;

  /// Beats not yet delivered — used by the brief screen to show mission length.
  int get beatsRemaining => (mission?.beats.length ?? 0) - _firedBeats.length;

  // -- lifecycle ------------------------------------------------------------

  Future<LocationReadiness> start({Mission? mission, required RunGoal goal, required Profile profile}) async {
    if (isActive) return LocationReadiness.ready;

    this.mission = mission;
    this.goal = goal;
    this.profile = profile;

    _reset();

    final readiness = await location.prepare();
    if (readiness != LocationReadiness.ready) {
      _locationTroubled = true;
      _events.add(LocationTrouble(readiness));
      // The run still starts: time-goal missions are perfectly playable with a
      // dead GPS, and refusing to start would strand the runner at the door.
    }
    // Subscribed either way. The runner can switch location on part-way through
    // a run, and the stream is the only thing that would notice; subscribing
    // only when things started well meant the warning could never clear.
    _fixSub = location.fixes().listen(_onFix, onError: _onFixError);

    _narrationSub = narrator.events.listen((e) {
      currentLine = e.line;
      if (e.line != null) transcript.add(e.line!);
      notifyListeners();
    });

    startedAt = _now();
    _segmentStart = startedAt;
    phase = RunPhase.running;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());

    await narrator.setAmbientBed(profile.ambientBed);
    notifyListeners();
    _tick(); // fire the opening beat immediately rather than a second late
    return readiness;
  }

  void pause() {
    if (phase != RunPhase.running) return;
    _closeSegment();
    phase = RunPhase.paused;
    notifyListeners();
  }

  void resume() {
    if (phase != RunPhase.paused && phase != RunPhase.autoPaused) return;
    _segmentStart = _now();
    _stillSince = null;
    phase = RunPhase.running;
    notifyListeners();
  }

  /// Ends the run and produces its permanent record.
  ///
  /// The outcome is decided here and nowhere else: goal met is a success,
  /// anything with real distance or time behind it is a failure worth logging,
  /// and a run that never really started is discarded so it cannot pollute
  /// stats or streaks.
  Future<RunRecord> finish() async {
    if (phase == RunPhase.running) _closeSegment();
    phase = RunPhase.finished;

    _ticker?.cancel();
    _detachStreams();
    await location.stop();
    await narrator.stopAll();

    final record = _record(elapsed: _accumulated.inMilliseconds / 1000.0);

    notifyListeners();
    return record;
  }

  /// The run so far, as [finish] would record it if called now — without
  /// ending anything. What the app saves while the run is going, so that a
  /// run cut off by the process dying can still be kept.
  RunRecord snapshot() => _record(elapsed: elapsedSeconds);

  /// The one place a record is assembled, so a snapshot and a finished run
  /// cannot disagree about what a run is.
  RunRecord _record({required double elapsed}) {
    final outcome = goalReached
        ? RunOutcome.success
        : (elapsed < 60 && distanceMeters < 100 ? RunOutcome.discarded : RunOutcome.failed);

    return RunRecord(
      id: '${startedAt?.microsecondsSinceEpoch ?? _now().microsecondsSinceEpoch}',
      startedAt: startedAt ?? _now(),
      endedAt: _now(),
      elapsedSeconds: elapsed,
      movingSeconds: min(movingSeconds, elapsed),
      distanceMeters: distanceMeters,
      calories: Energy.kcal(distanceMeters: distanceMeters, seconds: elapsed, weightKg: profile.weightKg),
      goal: goal,
      outcome: outcome,
      missionId: mission?.id,
      missionCodename: mission?.codename,
      missionOrder: mission?.order,
      chasesTotal: chasesTotal,
      chasesEvaded: chasesEvaded,
      beatsHeard: beatsHeard,
      story: List.unmodifiable(story),
      trace: List.unmodifiable(trace),
    );
  }

  /// Abandons an in-flight run without recording it.
  Future<void> abort() async {
    _ticker?.cancel();
    _detachStreams();
    await location.stop();
    await narrator.stopAll();
    phase = RunPhase.idle;
    _reset();
    notifyListeners();
  }

  void _reset() {
    distanceMeters = 0;
    movingSeconds = 0;
    smoothedSpeed = 0;
    goalReached = false;
    activeChase = null;
    currentBeat = null;
    currentLine = null;
    chasesTotal = 0;
    chasesEvaded = 0;
    beatsHeard = 0;
    trace.clear();
    codexUnlocked.clear();
    _locationTroubled = false;
    transcript.clear();
    story.clear();
    _accumulated = Duration.zero;
    _segmentStart = null;
    _lastFix = null;
    _lastFixAt = null;
    _stillSince = null;
    _lastBeatEndedAt = null;
    _beatPlaying = false;
    _splitsDone = 0;
    _lastSplitAt = 0;
    _spokenSplits = 0;
    _spokenSplitAt = 0;
    _lastTracePointAt = -999;
    _distanceAtLastTick = 0;
    _implausibleStreak = 0;
    _firedBeats.clear();
    _paceSamples.clear();
  }

  void _closeSegment() {
    if (_segmentStart != null) {
      _accumulated += _now().difference(_segmentStart!);
      _segmentStart = null;
    }
  }

  /// Drops both stream subscriptions without waiting on them.
  ///
  /// Cancelling a broadcast subscription is fire-and-forget by nature, and
  /// awaiting it would make ending a run depend on stream teardown for no
  /// benefit.
  void _detachStreams() {
    unawaited(_fixSub?.cancel() ?? Future<void>.value());
    _fixSub = null;
    unawaited(_narrationSub?.cancel() ?? Future<void>.value());
    _narrationSub = null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _detachStreams();
    _events.close();
    super.dispose();
  }

  // -- position -------------------------------------------------------------

  /// A fix stream that has stopped being able to produce fixes.
  ///
  /// Only [LocationUnavailable] reaches the runner: it means no distance will be
  /// recorded for the rest of the run, which they need to know now rather than
  /// in the summary. Anything else is a transient the stream recovers from, and
  /// a banner for it would only teach them to ignore banners. The run continues
  /// either way — a time goal is perfectly playable with a dead GPS.
  void _onFixError(Object e) {
    if (e is LocationUnavailable) {
      // Repeats are swallowed: the provider can report itself off more than
      // once, and the runner needs telling only when the state changes.
      if (_locationTroubled) return;
      _locationTroubled = true;
      _events.add(LocationTrouble(e.readiness));
      return;
    }
    debugPrint('fix error: $e');
  }

  void _onFix(GeoFix fix) {
    // Before the accuracy gate: a fix of any quality means the provider is
    // delivering again, and the warning says fixes are not arriving at all.
    if (_locationTroubled) {
      _locationTroubled = false;
      _events.add(const LocationRestored());
    }
    if (fix.accuracy > maxAcceptableAccuracy) return;
    _lastFixAt = _now();

    if (phase != RunPhase.running && phase != RunPhase.autoPaused) {
      _lastFix = fix;
      return;
    }

    final previous = _lastFix;
    if (previous == null) {
      _lastFix = fix;
      _addTracePoint(fix);
      return;
    }

    final dt = fix.timestamp.difference(previous.timestamp).inMilliseconds / 1000.0;
    // Devices occasionally replay an old fix after a cold start; it carries no
    // usable information and must not move the reference point.
    if (dt <= 0) return;

    final step = Geo.distance(previous.lat, previous.lon, fix.lat, fix.lon);
    final speed = step / dt;

    if (speed > maxPlausibleSpeed) {
      // A single impossible jump is a bad fix, and the reference point stays
      // put. A run of them means the device really has moved — a tunnel, a
      // train — and the reference has to catch up or distance stops forever.
      if (++_implausibleStreak >= 5) {
        _lastFix = fix;
        _implausibleStreak = 0;
      }
      return;
    }
    _implausibleStreak = 0;

    // Below the noise floor the reference is deliberately *not* advanced, so
    // genuinely slow movement accumulates until it clears the floor instead of
    // being thrown away a metre at a time. Jitter around a fixed point never
    // accumulates, because it does not drift in one direction.
    if (step < max(minStepMeters, fix.accuracy * 0.35)) return;

    _lastFix = fix;
    distanceMeters += step;
    smoothedSpeed = smoothedSpeed == 0 ? speed : smoothedSpeed * 0.6 + speed * 0.4;

    if (phase == RunPhase.autoPaused && smoothedSpeed > movingThresholdMps) resume();

    activeChase?.covered = distanceMeters - activeChase!.startDistance;
    _addTracePoint(fix);
    notifyListeners();
  }

  /// Auto-pause is only trustworthy while fixes are actually arriving. With a
  /// dead or denied GPS there is no way to tell a stopped runner from a lost
  /// signal, and freezing the clock would silently ruin a time-based mission.
  bool get _gpsIsLive {
    final at = _lastFixAt;
    return at != null && _now().difference(at) < fixStaleAfter;
  }

  void _addTracePoint(GeoFix fix) {
    final t = elapsedSeconds;
    if (t - _lastTracePointAt < 3) return;
    _lastTracePointAt = t;
    trace.add(TracePoint(lat: fix.lat, lon: fix.lon, elapsedSeconds: t, speedMps: smoothedSpeed));
  }

  // -- per-second update ----------------------------------------------------

  void _tick() {
    if (phase == RunPhase.running || phase == RunPhase.autoPaused) {
      // A second with no qualifying movement bleeds the speed estimate down,
      // so a stopped runner does not keep reading as if they were still going
      // at their last known pace.
      if (distanceMeters - _distanceAtLastTick < 0.5) {
        smoothedSpeed = max(0, smoothedSpeed - speedDecayPerSecond);
      }
      _distanceAtLastTick = distanceMeters;
    }

    if (phase == RunPhase.running) {
      final moving = smoothedSpeed >= movingThresholdMps;
      if (moving) {
        movingSeconds += 1;
        _stillSince = null;
      } else {
        _stillSince ??= _now();
        if (profile.autoPause && _gpsIsLive && _now().difference(_stillSince!) >= autoPauseAfter) {
          _closeSegment();
          phase = RunPhase.autoPaused;
        }
      }
      _paceSamples.add(_PaceSample(elapsedSeconds, distanceMeters));
      if (_paceSamples.length > 600) _paceSamples.removeAt(0);
    }

    _checkGoal();
    _updateChase();
    _maybeFireBeat();
    _maybeReadSplit();
    notifyListeners();
  }

  /// Reads out each kilometre (or mile) as the run passes it.
  ///
  /// On a mission the story comes first: a split never cuts into a beat or a
  /// pursuit, and waits for it to end. Crossings are still timed the moment
  /// they happen — only the readout waits — so a kilometre passed mid-scene is
  /// not announced slower than it was run. It goes through `speakBeat` all the
  /// same, rather than a path of its own: that is what queues it behind
  /// anything already speaking and takes and returns audio focus, which is the
  /// part that has needed fixing on real runs before.
  void _maybeReadSplit() {
    if (!profile.splitsEnabled || phase != RunPhase.running) return;
    final metric = profile.isMetric;
    final reached = (distanceMeters / (metric ? 1000.0 : 1609.344)).floor();
    if (reached > _splitsDone) {
      // The flash on screen is per crossing, so it times from the last one.
      final split = (elapsedSeconds - _lastSplitAt) / (reached - _splitsDone);
      _splitsDone = reached;
      _lastSplitAt = elapsedSeconds;
      _events.add(SplitReached(count: reached, splitSeconds: split, metric: metric));
    }

    if (_splitsDone <= _spokenSplits) return;
    // The story's turn: wait for the scene and the chase to be over.
    if (_beatPlaying || activeChase != null) return;

    // A jump in the GPS can cross two boundaries between ticks, and a long
    // scene can hold a readout past the next one. Either way: one readout for
    // where the runner now is — a backlog of stale ones queued behind each
    // other would still be talking a minute later — with the time shared out.
    final split = (_lastSplitAt - _spokenSplitAt) / (_splitsDone - _spokenSplits);
    final total = _lastSplitAt;
    final count = _splitsDone;
    _spokenSplits = _splitsDone;
    _spokenSplitAt = _lastSplitAt;
    unawaited(
      narrator.speakBeat([
        StoryLine(
          speaker: 'SYSTEM',
          text: SplitReadout.line(count: count, metric: metric, splitSeconds: split, totalSeconds: total),
        ),
      ]),
    );
  }


  void _checkGoal() {
    if (goalReached) return;
    if (!goal.isMet(elapsedSeconds: elapsedSeconds, distanceMeters: distanceMeters)) return;
    goalReached = true;
    _log(StoryEventKind.goal);
    _events.add(const GoalReached());
  }

  // -- story ----------------------------------------------------------------

  void _maybeFireBeat() {
    final m = mission;
    if (m == null || _beatPlaying || phase != RunPhase.running) return;
    if (activeChase != null) return;

    final last = _lastBeatEndedAt;
    if (last != null && _now().difference(last) < minBeatGap) return;

    StoryBeat? next;
    for (final beat in m.beats) {
      if (_firedBeats.contains(beat.id)) continue;
      if (beat.trigger.isReady(
        progress: progress,
        elapsedSeconds: elapsedSeconds,
        distanceMeters: distanceMeters,
      )) {
        next = beat;
      }
      // Beats are authored in order; stop at the first one not yet due so a
      // late beat can never overtake an earlier one.
      break;
    }
    if (next == null) return;

    _fireBeat(next);
  }

  CodexEntry? _codexEntry(String id) {
    for (final entry in mission?.codex ?? const <CodexEntry>[]) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  void _fireBeat(StoryBeat beat) {
    _firedBeats.add(beat.id);
    _beatPlaying = true;
    currentBeat = beat;
    beatsHeard++;
    _log(StoryEventKind.beat, ref: beat.id);

    var lines = beat.lines;
    // Hearing the line *intercepts* the entry; it is only *recovered* — banked
    // in the codex — when the operation succeeds. An entry already in the codex
    // is neither announced nor flashed again; hearing the line is just the
    // story. One that was intercepted on a failed attempt is announced again,
    // because the runner still does not have it.
    final codexId = beat.unlocksCodex;
    if (codexId != null && !codexUnlocked.contains(codexId) && !profile.unlockedCodex.contains(codexId)) {
      codexUnlocked.add(codexId);
      _log(StoryEventKind.codex, ref: codexId);
      _events.add(CodexUnlocked(codexId));
      // Announced inside the same transmission, after the character has
      // finished: the runner is not looking at the screen, so the voice is the
      // only channel that reliably reaches them, and one interruption of their
      // music is better than two.
      final entry = _codexEntry(codexId);
      if (entry != null) {
        lines = [
          ...lines,
          StoryLine(
            speaker: 'SYSTEM',
            text: 'Intel intercepted: ${entry.title}. Complete the operation to decrypt.',
            sfxBefore: 'unlock',
            pauseAfterMs: 120,
          ),
        ];
      }
    }
    _events.add(BeatEvent(beat));

    unawaited(
      narrator.speakBeat(lines).whenComplete(() {
        _beatPlaying = false;
        _lastBeatEndedAt = _now();
        currentBeat = null;
        final chase = beat.chase;
        if (chase != null && profile.chasesEnabled && phase == RunPhase.running) {
          _startChase(chase);
        }
        notifyListeners();
      }),
    );
  }

  // -- chases ---------------------------------------------------------------

  void _startChase(ChaseSpec spec) {
    final baseline = _baselineSpeed();
    final chase = ActiveChase(
      spec: spec,
      startedAtElapsed: elapsedSeconds,
      startDistance: distanceMeters,
      requiredMeters: baseline * spec.paceFactor * spec.duration.inSeconds,
    );
    activeChase = chase;
    chasesTotal++;
    _log(StoryEventKind.chaseStarted, ref: spec.pursuer);
    unawaited(narrator.sfx('chase_start'));
    _events.add(ChaseStarted(chase));
    notifyListeners();
  }

  void _updateChase() {
    final chase = activeChase;
    if (chase == null) return;
    chase.covered = distanceMeters - chase.startDistance;
    if (elapsedSeconds - chase.startedAtElapsed < chase.spec.duration.inSeconds) return;

    final escaped = chase.covered >= chase.requiredMeters;
    activeChase = null;
    if (escaped) chasesEvaded++;

    _log(StoryEventKind.chaseEnded, ref: chase.spec.pursuer, escaped: escaped);
    unawaited(narrator.sfx(escaped ? 'chase_clear' : 'chase_failed'));
    _events.add(ChaseEnded(escaped, chase.spec.pursuer));

    final lines = escaped ? chase.spec.escapedLines : chase.spec.caughtLines;
    if (lines.isNotEmpty) {
      _beatPlaying = true;
      unawaited(
        narrator.speakBeat(lines).whenComplete(() {
          _beatPlaying = false;
          _lastBeatEndedAt = _now();
          notifyListeners();
        }),
      );
    }
    notifyListeners();
  }

  /// The runner's own recent speed, which every chase target is scaled from.
  ///
  /// Clamped at both ends: a chase that opens in the first minute would
  /// otherwise be scaled off a near-zero baseline and be trivially winnable,
  /// and a downhill sprint just before a chase should not make the next one
  /// impossible.
  double _baselineSpeed() {
    final now = elapsedSeconds;
    _PaceSample? oldest;
    for (final s in _paceSamples) {
      if (now - s.elapsed <= chaseBaselineWindow) {
        oldest = s;
        break;
      }
    }
    var speed = 0.0;
    if (oldest != null && now - oldest.elapsed > 30) {
      speed = (distanceMeters - oldest.distance) / (now - oldest.elapsed);
    } else if (now > 0) {
      speed = distanceMeters / now;
    }
    return speed.clamp(1.9, 4.6);
  }
}

class _PaceSample {
  const _PaceSample(this.elapsed, this.distance);
  final double elapsed;
  final double distance;
}
