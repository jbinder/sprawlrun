import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/services/location_service.dart';
import 'package:sprawl_run/services/run_engine.dart';
import 'package:sprawl_run/services/step_source.dart';
import 'package:sprawl_run/state/app_state.dart';

import 'support/fakes.dart';

/// Steps: counted only when the runner asked for it, only while the run is
/// going, and enough on their own to tell moving from standing when the GPS
/// has nothing to say.
void main() {
  const counting = Profile(countSteps: true, autoPause: false);
  final start = DateTime(2026, 10, 24, 18);

  /// A run in fake time with no GPS fixes at all — the case steps are for.
  ({RunEngine engine, FakeSteps steps, DateTime Function() now}) begin(FakeAsync fake, Profile profile) {
    final steps = FakeSteps();
    DateTime now() => start.add(fake.elapsed);
    final engine = RunEngine(
      narrator: FakeNarrator(),
      location: FakeLocation(readiness: LocationReadiness.gpsDisabled),
      stepSource: steps,
      clock: now,
    );
    engine.start(goal: const RunGoal(GoalType.time, 3600), profile: profile);
    fake.flushMicrotasks();
    return (engine: engine, steps: steps, now: now);
  }

  /// [seconds] of walking at [perSecond] steps a second, one reading each.
  void walk(FakeAsync fake, FakeSteps steps, int seconds, {int perSecond = 2}) {
    for (var i = 0; i < seconds; i++) {
      fake.elapse(const Duration(seconds: 1));
      steps.take(perSecond);
      fake.flushMicrotasks();
    }
  }

  RunRecord finish(FakeAsync fake, RunEngine engine) {
    RunRecord? record;
    engine.finish().then((r) => record = r);
    fake.elapse(const Duration(milliseconds: 50));
    return record!;
  }

  test('off unless the runner turned it on: nothing listens, nothing is claimed', () {
    fakeAsync((fake) {
      final run = begin(fake, const Profile(autoPause: false));
      walk(fake, run.steps, 30);
      expect(run.steps.listened, isFalse);
      expect(finish(fake, run.engine).steps, isNull);
    });
  });

  test('steps are counted from where the counter stood when the run began', () {
    fakeAsync((fake) {
      final run = begin(fake, counting);
      run.steps.total = 41000;
      run.steps.take(0); // the counter's first reading, since the last reboot
      fake.flushMicrotasks();
      walk(fake, run.steps, 90);
      final record = finish(fake, run.engine);
      expect(record.steps, 180);
      expect(record.cadence, closeTo(120, 3), reason: 'two steps a second');
    });
  });

  test('without GPS, steps are what makes the time moving time', () {
    fakeAsync((fake) {
      final run = begin(fake, counting);
      run.steps.take(0);
      walk(fake, run.steps, 120);
      fake.elapse(const Duration(seconds: 60)); // standing, no steps
      fake.flushMicrotasks();
      final record = finish(fake, run.engine);
      expect(record.movingSeconds, inInclusiveRange(118, 125), reason: 'the walk, plus the few seconds a step stays fresh');
      expect(record.elapsedSeconds, greaterThan(175));
    });
  });

  test('steps taken while paused by hand are not the run\'s', () {
    fakeAsync((fake) {
      final run = begin(fake, counting);
      run.steps.take(0);
      walk(fake, run.steps, 10);
      run.engine.pause();
      walk(fake, run.steps, 30);
      run.engine.resume();
      walk(fake, run.steps, 10);
      expect(finish(fake, run.engine).steps, 40);
    });
  });

  test('a counter that cannot count leaves the run without steps, not with zero', () {
    fakeAsync((fake) {
      final run = begin(fake, counting);
      expect(run.engine.steps, 0, reason: 'counting from the start');
      run.steps.fail();
      fake.flushMicrotasks();
      expect(run.engine.steps, isNull);
      expect(finish(fake, run.engine).steps, isNull);
    });
  });

  test('walking off again ends an auto-pause', () {
    fakeAsync((fake) {
      final run = begin(fake, counting);
      run.steps.take(0);
      run.engine.phase = RunPhase.autoPaused;
      walk(fake, run.steps, 3);
      expect(run.engine.phase, RunPhase.running);
    });
  });

  test('a record keeps its steps through JSON, and an old one has none', () {
    final record = RunRecord(
      id: '1',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 30)),
      elapsedSeconds: 1800,
      movingSeconds: 1800,
      distanceMeters: 5000,
      calories: 300,
      goal: const RunGoal(GoalType.time, 1800),
      outcome: RunOutcome.success,
      steps: 5100,
    );
    expect(RunRecord.fromJson(record.toJson()).steps, 5100);
    expect(RunRecord.fromJson(record.toJson()..remove('steps')).steps, isNull);
    expect(record.cadence, 170);
  });

  group('the setting', () {
    late Directory root;
    late _Setup setup;

    Future<AppState> load({Profile profile = const Profile()}) async {
      final profiles = ProfileRepository(root);
      await profiles.save(profile);
      final state = AppState(
        profiles: profiles,
        runs: RunRepository(Directory('${root.path}/runs')),
        missions: MissionRepository(externalDir: Directory('${root.path}/packs'), bundle: _DiskBundle()),
        narrator: FakeNarrator(),
        stepSetup: setup.asStepSetup(),
      );
      await state.load();
      return state;
    }

    setUp(() {
      root = tempRoot('steps');
      setup = _Setup();
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('is only offered on a phone with a step counter', () async {
      expect((await load()).stepCounterAvailable, isTrue);
      setup.available = false;
      expect((await load()).stepCounterAvailable, isFalse);
    });

    test('stays off when the permission is refused', () async {
      setup.grant = false;
      final state = await load();
      expect(await state.setCountSteps(true), isFalse);
      expect(state.profile.countSteps, isFalse);

      setup.grant = true;
      expect(await state.setCountSteps(true), isTrue);
      expect(state.profile.countSteps, isTrue);
    });

    test('is turned back off where the permission is gone, as after a restore onto another phone', () async {
      setup.granted = false;
      final state = await load(profile: const Profile(countSteps: true));
      expect(state.profile.countSteps, isFalse);
      expect((await ProfileRepository(root).load()).countSteps, isFalse, reason: 'and saved that way');
    });
  });
}

class _Setup {
  bool available = true;
  bool granted = true;
  bool grant = true;

  StepSetup asStepSetup() => StepSetup(
    available: () async => available,
    granted: () async => granted,
    request: () async => granted = grant,
  );
}

class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.view(File(key).readAsBytesSync().buffer);

  @override
  Future<String> loadString(String key, {bool cache = true}) async => File(key).readAsStringSync();
}
