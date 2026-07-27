import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/mission.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/services/geo.dart';
import 'package:sprawl_run/services/location_service.dart';
import 'package:sprawl_run/services/run_engine.dart';

import 'support/fakes.dart';

/// Drives a whole run in fake time.
///
/// [metersPerSecond] can vary per second so a test can slow down or sprint;
/// returning 0 simulates standing still.
class Harness {
  Harness(this.fake, {Mission? mission, RunGoal? goal, Profile profile = const Profile()})
    : start = DateTime(2026, 7, 22, 19, 0) {
    location = FakeLocation();
    narrator = FakeNarrator();
    engine = RunEngine(narrator: narrator, location: location, clock: now);
    _mission = mission;
    _goal = goal ?? const RunGoal(GoalType.time, 600);
    _profile = profile;
  }

  final FakeAsync fake;
  final DateTime start;
  late final FakeLocation location;
  late final FakeNarrator narrator;
  late final RunEngine engine;
  late final Mission? _mission;
  late final RunGoal _goal;
  late final Profile _profile;

  DateTime now() => start.add(fake.elapsed);

  void begin() {
    engine.start(mission: _mission, goal: _goal, profile: _profile);
    fake.flushMicrotasks();
  }

  /// Advances [seconds] of run time, emitting one fix per second — including
  /// while stationary, which is what a real GPS does.
  void runFor(int seconds, double Function(int second) metersPerSecond) {
    for (var i = 0; i < seconds; i++) {
      fake.elapse(const Duration(seconds: 1));
      location.step(now(), metersPerSecond(i));
      fake.flushMicrotasks();
    }
  }

  void steady(int seconds, double mps) => runFor(seconds, (_) => mps);

  /// Advances time without any GPS activity at all.
  void runBlind(int seconds) {
    fake.elapse(Duration(seconds: seconds));
    fake.flushMicrotasks();
  }

  RunRecord finish() {
    RunRecord? record;
    engine.finish().then((r) => record = r);
    fake.elapse(const Duration(milliseconds: 50));
    return record!;
  }
}

Mission missionWith(List<StoryBeat> beats) => Mission(
  id: 'test',
  packId: 'test',
  order: 1,
  codename: 'TEST OP',
  title: 'Test Operation',
  location: 'Nowhere',
  brief: '',
  objective: '',
  debrief: '',
  suggestedGoal: const RunGoal(GoalType.time, 600),
  beats: beats,
);

StoryBeat beat(String id, {double? fraction, double? seconds, ChaseSpec? chase, String? codex}) => StoryBeat(
  id: id,
  trigger: BeatTrigger(fraction: fraction, seconds: seconds),
  lines: [StoryLine(speaker: 'KESTREL', text: 'line for $id')],
  chase: chase,
  unlocksCodex: codex,
);

void main() {
  group('distance tracking', () {
    test('accumulates plausible movement', () {
      fakeAsync((fake) {
        final h = Harness(fake, goal: RunGoal.seconds(120))..begin();
        h.steady(60, 3.0);
        // 60 fixes of 3 m each; the first establishes the origin.
        expect(h.engine.distanceMeters, closeTo(177, 3));
        expect(h.engine.elapsedSeconds, closeTo(60, 1));
      });
    });

    test('rejects fixes with unusable accuracy', () {
      fakeAsync((fake) {
        final h = Harness(fake)..begin();
        h.location.accuracy = 90;
        h.steady(30, 3.0);
        expect(h.engine.distanceMeters, 0, reason: 'every fix was too imprecise to trust');
      });
    });

    test('rejects teleports that no runner could produce', () {
      fakeAsync((fake) {
        final h = Harness(fake)..begin();
        h.steady(10, 3.0);
        final before = h.engine.distanceMeters;
        fake.elapse(const Duration(seconds: 1));
        h.location.step(h.now(), 900); // 900 m in one second
        fake.flushMicrotasks();
        expect(h.engine.distanceMeters, before);
      });
    });

    // Jitter of +/-0.9 m produces 1.8 m between consecutive fixes, under the
    // 2 m noise floor. Larger oscillation at 1 Hz is indistinguishable from
    // real movement without a second sensor, and is not claimed to be handled.
    test('treats jitter around a fixed point as standing still', () {
      fakeAsync((fake) {
        final h = Harness(fake)..begin();
        for (var i = 0; i < 60; i++) {
          fake.elapse(const Duration(seconds: 1));
          h.location.jitter(h.now(), 0.9);
          fake.flushMicrotasks();
        }
        expect(h.engine.distanceMeters, 0);
      });
    });

    test('accumulates genuinely slow movement instead of discarding it', () {
      fakeAsync((fake) {
        // 0.8 m/s is below the per-fix noise floor, but it is real movement:
        // holding the reference point until it clears the floor keeps it.
        final h = Harness(fake, goal: RunGoal.seconds(300))..begin();
        h.steady(120, 0.8);
        expect(h.engine.distanceMeters, closeTo(96, 6));
      });
    });
  });

  group('goal completion', () {
    test('a time goal completes on elapsed time and can be exceeded', () {
      fakeAsync((fake) {
        final h = Harness(fake, goal: RunGoal.seconds(60))..begin();
        h.steady(59, 3.0);
        expect(h.engine.goalReached, isFalse);
        h.steady(5, 3.0);
        expect(h.engine.goalReached, isTrue);
        expect(h.engine.progress, 1.0);

        // Running on past the target keeps recording.
        final atGoal = h.engine.distanceMeters;
        h.steady(30, 3.0);
        expect(h.engine.distanceMeters, greaterThan(atGoal));
      });
    });

    test('a distance goal completes on distance, not time', () {
      fakeAsync((fake) {
        final h = Harness(fake, goal: RunGoal.metres(300))..begin();
        h.steady(60, 3.0); // ~177 m
        expect(h.engine.goalReached, isFalse);
        h.steady(60, 3.0); // ~354 m
        expect(h.engine.goalReached, isTrue);
      });
    });

    test('finishing after the goal records a success', () {
      fakeAsync((fake) {
        final h = Harness(fake, goal: RunGoal.seconds(60))..begin();
        h.steady(65, 3.0);
        final record = h.finish();
        expect(record.outcome, RunOutcome.success);
        expect(record.distanceMeters, greaterThan(150));
      });
    });

    test('stopping short records a failure but keeps the distance', () {
      fakeAsync((fake) {
        final h = Harness(fake, goal: RunGoal.seconds(600))..begin();
        h.steady(200, 3.0);
        final record = h.finish();
        expect(record.outcome, RunOutcome.failed);
        expect(record.distanceMeters, greaterThan(500));
      });
    });

    test('a run that never really started is discarded', () {
      fakeAsync((fake) {
        final h = Harness(fake, goal: RunGoal.seconds(600))..begin();
        h.steady(20, 0.0);
        expect(h.finish().outcome, RunOutcome.discarded);
      });
    });
  });

  group('pausing', () {
    test('a manual pause stops the clock', () {
      fakeAsync((fake) {
        final h = Harness(fake, goal: RunGoal.seconds(600))..begin();
        h.steady(30, 3.0);
        h.engine.pause();
        final frozen = h.engine.elapsedSeconds;
        fake.elapse(const Duration(seconds: 60));
        expect(h.engine.elapsedSeconds, frozen);
        h.engine.resume();
        h.steady(10, 3.0);
        expect(h.engine.elapsedSeconds, closeTo(frozen + 10, 1));
      });
    });

    test('auto-pause engages when the runner stops and lifts when they move', () {
      fakeAsync((fake) {
        final h = Harness(fake, goal: RunGoal.seconds(3600))..begin();
        h.steady(30, 3.0);
        expect(h.engine.phase, RunPhase.running);

        h.steady(40, 0.0); // stand still past the auto-pause threshold
        expect(h.engine.phase, RunPhase.autoPaused);
        final frozen = h.engine.elapsedSeconds;

        fake.elapse(const Duration(seconds: 20));
        expect(h.engine.elapsedSeconds, frozen, reason: 'the clock is stopped while auto-paused');

        h.steady(6, 3.0);
        expect(h.engine.phase, RunPhase.running);
      });
    });

    test('auto-pause can be switched off', () {
      fakeAsync((fake) {
        final h = Harness(
          fake,
          goal: RunGoal.seconds(3600),
          profile: const Profile(autoPause: false),
        )..begin();
        h.steady(30, 3.0);
        h.steady(60, 0.0);
        expect(h.engine.phase, RunPhase.running);
      });
    });
  });

  group('story beats', () {
    test('the opening beat fires immediately', () {
      fakeAsync((fake) {
        final h = Harness(
          fake,
          mission: missionWith([beat('b0', fraction: 0.0)]),
          goal: RunGoal.seconds(600),
        )..begin();
        fake.flushMicrotasks();
        expect(h.narrator.beats, hasLength(1));
        expect(h.engine.beatsHeard, 1);
      });
    });

    test('beats fire in order as goal progress advances', () {
      fakeAsync((fake) {
        final h = Harness(
          fake,
          mission: missionWith([
            beat('b0', fraction: 0.0),
            beat('b1', fraction: 0.25),
            beat('b2', fraction: 0.5),
            beat('b3', fraction: 1.0),
          ]),
          goal: RunGoal.seconds(600),
        )..begin();

        h.steady(160, 3.0);
        expect(h.narrator.spokenText, ['line for b0', 'line for b1']);

        h.steady(160, 3.0);
        expect(h.narrator.spokenText.last, 'line for b2');

        h.steady(300, 3.0);
        expect(h.narrator.spokenText.last, 'line for b3');
      });
    });

    test('two beats due at once are spaced out, never stacked', () {
      fakeAsync((fake) {
        final h = Harness(
          fake,
          // Both are due the instant the run starts.
          mission: missionWith([beat('b0', fraction: 0.0), beat('b1', fraction: 0.0)]),
          goal: RunGoal.seconds(600),
        )..begin();

        h.steady(10, 3.0);
        expect(h.narrator.beats, hasLength(1), reason: 'the second beat waits out the minimum gap');

        h.steady(60, 3.0);
        expect(h.narrator.beats, hasLength(2));
      });
    });

    test('an absolute time trigger fires on the clock regardless of progress', () {
      fakeAsync((fake) {
        final h = Harness(
          fake,
          mission: missionWith([beat('b0', seconds: 120)]),
          goal: RunGoal.seconds(3600),
        )..begin();

        h.steady(110, 3.0);
        expect(h.narrator.beats, isEmpty);
        h.steady(20, 3.0);
        expect(h.narrator.beats, hasLength(1));
      });
    });

    test('codex entries unlock when their beat plays', () {
      fakeAsync((fake) {
        final h = Harness(
          fake,
          mission: missionWith([beat('b0', fraction: 0.0, codex: 'cdx_test')]),
          goal: RunGoal.seconds(600),
        )..begin();
        fake.flushMicrotasks();
        expect(h.engine.codexUnlocked, ['cdx_test']);
      });
    });
  });

  group('chases', () {
    ChaseSpec chase({double paceFactor = 1.2, int seconds = 60}) => ChaseSpec(
      duration: Duration(seconds: seconds),
      paceFactor: paceFactor,
      pursuer: 'TEST DRONE',
      escapedLines: const [StoryLine(speaker: 'SIX', text: 'escaped')],
      caughtLines: const [StoryLine(speaker: 'SIX', text: 'caught')],
    );

    test('speeding up during the window escapes', () {
      fakeAsync((fake) {
        final h = Harness(
          fake,
          mission: missionWith([beat('b0', fraction: 0.2, chase: chase())]),
          goal: RunGoal.seconds(1200),
        )..begin();

        h.steady(250, 3.0); // establish a 3 m/s baseline, then the beat fires
        expect(h.engine.activeChase, isNotNull);

        h.steady(70, 4.2); // 40% faster than baseline, well over the 1.2 factor
        expect(h.engine.activeChase, isNull);
        expect(h.engine.chasesEvaded, 1);
        expect(h.engine.chasesTotal, 1);
        expect(h.narrator.spokenText, contains('escaped'));
        expect(h.narrator.sfxPlayed, contains('chase_clear'));
      });
    });

    test('holding the same pace is not enough', () {
      fakeAsync((fake) {
        final h = Harness(
          fake,
          mission: missionWith([beat('b0', fraction: 0.2, chase: chase())]),
          goal: RunGoal.seconds(1200),
        )..begin();

        h.steady(250, 3.0);
        expect(h.engine.activeChase, isNotNull);

        h.steady(70, 3.0);
        expect(h.engine.chasesEvaded, 0);
        expect(h.engine.chasesTotal, 1);
        expect(h.narrator.spokenText, contains('caught'));
        expect(h.narrator.sfxPlayed, contains('chase_failed'));
      });
    });

    test('the target scales to the runner, not to an absolute speed', () {
      // A slow runner and a fast runner should face a chase of equal difficulty.
      double requiredFor(double baselineMps) {
        late double required;
        fakeAsync((fake) {
          final h = Harness(
            fake,
            mission: missionWith([beat('b0', fraction: 0.2, chase: chase(paceFactor: 1.2))]),
            goal: RunGoal.seconds(1200),
          )..begin();
          h.steady(250, baselineMps);
          required = h.engine.activeChase!.requiredMeters;
        });
        return required;
      }

      final slow = requiredFor(2.2);
      final fast = requiredFor(4.0);
      expect(fast, greaterThan(slow));
      // Both are 60 s at 1.2x their own pace.
      expect(slow, closeTo(2.2 * 1.2 * 60, 12));
      expect(fast, closeTo(4.0 * 1.2 * 60, 20));
    });

    test('chases can be switched off entirely', () {
      fakeAsync((fake) {
        final h = Harness(
          fake,
          mission: missionWith([beat('b0', fraction: 0.2, chase: chase())]),
          goal: RunGoal.seconds(1200),
          profile: const Profile(chasesEnabled: false),
        )..begin();

        h.steady(300, 3.0);
        expect(h.engine.activeChase, isNull);
        expect(h.engine.chasesTotal, 0);
      });
    });

    test('no story beat interrupts an active chase', () {
      fakeAsync((fake) {
        final h = Harness(
          fake,
          mission: missionWith([
            beat('b0', fraction: 0.0, chase: chase(seconds: 120)),
            beat('b1', fraction: 0.05),
          ]),
          goal: RunGoal.seconds(1200),
        )..begin();

        h.steady(90, 3.0);
        expect(h.engine.activeChase, isNotNull);
        expect(h.narrator.spokenText, isNot(contains('line for b1')));
      });
    });
  });

  group('degraded conditions', () {
    test('a run still starts with no location permission', () {
      fakeAsync((fake) {
        final h = Harness(fake, goal: RunGoal.seconds(600));
        h.location.readiness = LocationReadiness.denied;
        h.begin();

        h.runBlind(120);
        expect(h.engine.phase, RunPhase.running, reason: 'no fixes means auto-pause cannot be trusted');
        expect(h.engine.elapsedSeconds, closeTo(120, 1));
        expect(h.engine.distanceMeters, 0);
      });
    });

    test('a time-goal mission completes without a single fix', () {
      fakeAsync((fake) {
        final h = Harness(fake, goal: RunGoal.seconds(60));
        h.location.readiness = LocationReadiness.serviceDisabled;
        h.begin();

        h.runBlind(65);
        expect(h.engine.goalReached, isTrue);
      });
    });

    test('an out-of-order fix does not corrupt the distance', () {
      fakeAsync((fake) {
        final h = Harness(fake)..begin();
        h.steady(20, 3.0);
        final before = h.engine.distanceMeters;
        // A fix stamped in the past — some devices do this after a cold start.
        h.location.emitRaw(
          GeoFix(lat: h.location.lat + 0.001, lon: h.location.lon, timestamp: h.now().subtract(const Duration(seconds: 30))),
        );
        fake.flushMicrotasks();
        expect(h.engine.distanceMeters, before);
      });
    });
  });

  test('the finished record carries the whole run', () {
    fakeAsync((fake) {
      final h = Harness(
        fake,
        mission: missionWith([beat('b0', fraction: 0.0), beat('b1', fraction: 0.5)]),
        goal: RunGoal.seconds(120),
        profile: const Profile(weightKg: 70),
      )..begin();

      h.steady(130, 3.0);
      final record = h.finish();

      expect(record.missionCodename, 'TEST OP');
      expect(record.missionOrder, 1);
      expect(record.beatsHeard, 2);
      expect(record.calories, greaterThan(0));
      expect(record.trace, isNotEmpty);
      expect(record.movingSeconds, lessThanOrEqualTo(record.elapsedSeconds));
      expect(h.narrator.stopped, isTrue);
      expect(h.location.stopped, isTrue);
    });
  });
}
