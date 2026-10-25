import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/models/stride.dart';
import 'package:sprawl_run/services/location_service.dart';
import 'package:sprawl_run/services/run_engine.dart';
import 'package:sprawl_run/services/stats_service.dart';

import 'support/fakes.dart';

/// Distance from steps: only where the GPS has none to give, marked as an
/// estimate, and at a stride learned from the runner's own runs.
void main() {
  const counting = Profile(countSteps: true, autoPause: false, heightCm: 180);
  final start = DateTime(2026, 10, 25, 18);

  ({RunEngine engine, FakeSteps steps, FakeLocation gps, DateTime Function() now}) begin(
    FakeAsync fake, {
    LocationReadiness readiness = LocationReadiness.gpsDisabled,
    RunGoal goal = const RunGoal(GoalType.time, 3600),
    Stride? stride,
  }) {
    final steps = FakeSteps();
    final gps = FakeLocation(readiness: readiness);
    DateTime now() => start.add(fake.elapsed);
    final engine = RunEngine(narrator: FakeNarrator(), location: gps, stepSource: steps, clock: now);
    engine.start(goal: goal, profile: counting, stride: stride);
    fake.flushMicrotasks();
    steps.take(0); // the counter's first reading only sets where counting starts
    fake.flushMicrotasks();
    return (engine: engine, steps: steps, gps: gps, now: now);
  }

  /// [seconds] of [perSecond] steps a second, with a fix moving [gpsMeters]
  /// each second when given.
  void go(
    FakeAsync fake,
    ({RunEngine engine, FakeSteps steps, FakeLocation gps, DateTime Function() now}) run,
    int seconds, {
    int perSecond = 3,
    double? gpsMeters,
  }) {
    for (var i = 0; i < seconds; i++) {
      fake.elapse(const Duration(seconds: 1));
      run.steps.take(perSecond);
      if (gpsMeters != null) run.gps.step(run.now(), gpsMeters);
      fake.flushMicrotasks();
    }
  }

  RunRecord finish(FakeAsync fake, RunEngine engine) {
    RunRecord? record;
    engine.finish().then((r) => record = r);
    fake.elapse(const Duration(milliseconds: 50));
    return record!;
  }

  test('with no GPS at all, a treadmill run still covers its distance, from steps', () {
    fakeAsync((fake) {
      final run = begin(fake, goal: const RunGoal(GoalType.distance, 1000));
      expect(run.engine.tooShortToLog, isTrue, reason: 'ending now would save nothing');
      go(fake, run, 300); // 180 steps a minute: running
      expect(run.engine.tooShortToLog, isFalse);
      expect(run.engine.distanceEstimated, isTrue);
      expect(run.engine.goalReached, isTrue, reason: 'a distance target is reachable on a treadmill');

      final record = finish(fake, run.engine);
      // 900 steps at 0.65 × 1.80 m, give or take the first readings, which
      // come before there is a cadence to tell the gait by.
      expect(record.distanceMeters, closeTo(900 * 0.65 * 1.8, 10));
      expect(record.estimatedMeters, record.distanceMeters);
      expect(record.distanceEstimated, isTrue);
      expect(record.trace, isEmpty);
      expect(record.strides, isNull, reason: 'nothing measured, so nothing to learn');
    });
  });

  test('walking is counted at a walking stride', () {
    fakeAsync((fake) {
      final run = begin(fake);
      go(fake, run, 300, perSecond: 2); // 120 a minute
      expect(finish(fake, run.engine).distanceMeters, closeTo(600 * 0.415 * 1.8, 10));
    });
  });

  test('with GPS, steps add nothing and teach the stride', () {
    fakeAsync((fake) {
      final run = begin(fake, readiness: LocationReadiness.ready);
      go(fake, run, 120, gpsMeters: 3);
      final record = finish(fake, run.engine);
      expect(record.estimatedMeters, lessThan(record.distanceMeters * 0.1), reason: 'only before the first fix');
      expect(record.distanceEstimated, isFalse);
      final s = record.strides!;
      expect(s.runSteps, greaterThan(300));
      expect(s.runMeters / s.runSteps, closeTo(1.0, 0.05), reason: '3 m and 3 steps a second');
    });
  });

  test('a GPS gap is bridged by steps, and not counted twice when the fixes return', () {
    fakeAsync((fake) {
      final run = begin(
        fake,
        readiness: LocationReadiness.ready,
        stride: const Stride(walk: 0.7, run: 1.0),
      );
      go(fake, run, 60, gpsMeters: 3);
      final before = run.engine.distanceMeters;

      go(fake, run, 60); // a tunnel: steps, no fixes
      expect(run.engine.distanceMeters - before, closeTo(180, 5));

      // Out of the tunnel 180 m further on. The straight line from the last
      // fix would be the same 180 m again.
      run.gps.lat += 180 / 111320.0;
      go(fake, run, 60, gpsMeters: 3);
      final record = finish(fake, run.engine);
      expect(record.distanceMeters, closeTo(540, 12));
      // The tunnel, plus the steps before the first fix and in the second
      // the fixes came back.
      expect(record.estimatedMeters, closeTo(185, 3));
      expect(record.distanceEstimated, isTrue, reason: 'a third from steps');
      expect(record.strides!.runSteps, lessThan(400), reason: 'the tunnel taught nothing');
    });
  });

  group('the stride', () {
    RunRecord measured(int day, StrideSample s) => run(at: DateTime(2026, 10, day), steps: 1, strides: s);

    test('starts from height, or a typical one when none is given', () {
      final tall = Stride.of(const [], heightCm: 190);
      expect(tall.run, closeTo(1.235, 0.001));
      expect(tall.walk, closeTo(0.7885, 0.001));
      expect(Stride.of(const []).run, closeTo(1.105, 0.001));
    });

    test('is learned from the runner\'s own runs, per gait', () {
      final s = Stride.of([
        measured(2, const StrideSample(runSteps: 3000, runMeters: 3300)),
        measured(1, const StrideSample(walkSteps: 2000, walkMeters: 1500)),
      ], heightCm: 180);
      expect(s.run, closeTo(1.1, 0.001));
      expect(s.walk, closeTo(0.75, 0.001));
      expect(s.at(170), s.run);
      expect(s.at(110), s.walk);
    });

    test('a measured gait corrects the other one too', () {
      final s = Stride.of([measured(1, const StrideSample(runSteps: 3000, runMeters: 3900))], heightCm: 170);
      expect(s.run, closeTo(1.3, 0.001));
      expect(s.walk, closeTo(1.3 * Stride.walkPerHeight / Stride.runPerHeight, 0.001));
    });

    test('too few steps, or steps no human takes, are not learned from', () {
      final prior = Stride.of(const [], heightCm: 180);
      expect(Stride.of([measured(1, const StrideSample(runSteps: 500, runMeters: 600))], heightCm: 180).run, prior.run);
      expect(
        Stride.of([measured(1, const StrideSample(runSteps: 5000, runMeters: 20000))], heightCm: 180).run,
        prior.run,
        reason: '4 m a step is a bike, not a stride',
      );
    });
  });

  test('an estimated run is no pace record, but counts for the totals', () {
    final at = DateTime(2026, 10, 20, 7);
    final measured = run(at: at, meters: 5000, seconds: 1800);
    final treadmill = run(at: at.add(const Duration(days: 1)), meters: 5000, seconds: 1200, estimatedMeters: 5000);
    final stats = StatsService.lifetime([treadmill, measured], const StreakGoal());
    expect(stats.bestPaceSecondsPerKm, closeTo(360, 0.1));
    expect(stats.totalDistanceMeters, 10000);
  });

  test('a record keeps its estimate and stride through JSON, and an old one has neither', () {
    final record = run(
      at: start,
      steps: 4000,
      estimatedMeters: 1200,
      strides: const StrideSample(walkSteps: 100, walkMeters: 75, runSteps: 3000, runMeters: 3300),
    );
    final back = RunRecord.fromJson(record.toJson());
    expect(back.estimatedMeters, 1200);
    expect(back.strides!.runMeters, 3300);
    expect(back.strides!.walkSteps, 100);

    final old = RunRecord.fromJson(record.toJson()..remove('estimatedMeters')..remove('strides'));
    expect(old.estimatedMeters, 0);
    expect(old.strides, isNull);
    expect(old.distanceEstimated, isFalse);
  });
}
