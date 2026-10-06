import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/mission.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/screens/run_screen.dart';
import 'package:sprawl_run/services/run_engine.dart';
import 'package:sprawl_run/state/app_state.dart';
import 'package:sprawl_run/theme/cyber_theme.dart';

import 'support/fakes.dart';

const _notifications = MethodChannel('io.github.jbinder.sprawlrun/notifications');

/// A run screen with a live run behind it, the way the app starts one.
class _Run {
  _Run(this.state, this.engine, this._clock, this.noticeCalls);

  final AppState state;
  final RunEngine engine;
  final _Clock _clock;

  /// Everything the screen told the notification, oldest first.
  final List<MethodCall> noticeCalls;

  /// The last update sent to the notification.
  Map<Object?, Object?> get lastNotice =>
      noticeCalls.lastWhere((c) => c.method == 'updateMissionNotice').arguments as Map<Object?, Object?>;

  /// A tap on one of the notification's buttons, as Android delivers it.
  Future<void> tapNotice(WidgetTester tester, String action) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      _notifications.name,
      _notifications.codec.encodeMethodCall(MethodCall('noticeAction', action)),
      (_) {},
    );
    await tester.pump();
  }

  /// Moves the run on by whole seconds, at a steady pace.
  Future<void> run(WidgetTester tester, int seconds, {double mps = 3.0}) async {
    for (var i = 0; i < seconds; i++) {
      _clock.now = _clock.now.add(const Duration(seconds: 1));
      _clock.location.step(_clock.now, mps);
      await tester.pump(const Duration(seconds: 1));
    }
  }
}

class _Clock {
  DateTime now = DateTime(2026, 10, 4, 9);
  final location = FakeLocation();
}

Future<_Run> _startRun(WidgetTester tester) async {
  final root = tempRoot('runscreen');
  addTearDown(() => root.deleteSync(recursive: true));
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  // The run asks for notification permission before it starts, and an
  // unanswered platform call never returns in the harness.
  final noticeCalls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_notifications, (call) async {
    noticeCalls.add(call);
    return true;
  });

  final profiles = ProfileRepository(root);
  final state = AppState(
    profiles: profiles,
    runs: RunRepository(Directory('${root.path}/runs')),
    missions: MissionRepository(externalDir: Directory('${root.path}/packs')),
    narrator: FakeNarrator(),
  );
  await tester.runAsync(() async {
    // wakelock_plus has no implementation in the harness.
    await profiles.save(const Profile(keepScreenOn: false));
    await state.load();
  });
  final mission = state.currentMission!.mission;

  final clock = _Clock();
  final engine = RunEngine(narrator: FakeNarrator(), location: clock.location, clock: () => clock.now);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider.value(value: engine),
      ],
      child: MaterialApp(
        theme: buildCyberTheme(),
        // The harness's placeholder font is far wider than the real one and
        // pushes the big readout a few pixels past its box. Scaled slightly
        // rather than silencing overflow errors, so a real one still fails.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(0.85)),
          child: child!,
        ),
        home: RunScreen(mission: mission, goal: const RunGoal(GoalType.time, 1500)),
      ),
    ),
  );
  for (var i = 0; i < 10 && engine.phase == RunPhase.idle; i++) {
    clock.now = clock.now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }
  expect(engine.phase, RunPhase.running);
  return _Run(state, engine, clock, noticeCalls);
}

/// Ends the run so its ticker stops, and lets the line in flight run out.
Future<void> _stop(WidgetTester tester, _Run run) async {
  await run.engine.abort();
  await tester.pump(const Duration(minutes: 2));
}

void main() {
  // The HUD panel has room for three lines and a beat can be five, so after
  // the goal's beat everything before it had scrolled out of reach. A runner
  // noticed on a real run; the whole transcript now opens from the panel.
  testWidgets('the whole run transcript opens from the panel, newest first in view', (tester) async {
    final run = await _startRun(tester);
    final engine = run.engine;

    // Six lines delivered — twice what the panel has room for.
    for (var i = 1; i <= 6; i++) {
      engine.transcript.add(StoryLine(speaker: 'KESTREL', text: 'line $i'));
    }
    await run.run(tester, 1, mps: 0);

    expect(find.text('line 1', findRichText: true), findsNothing, reason: 'the panel holds only the last three');
    // Six of ours, plus whatever the mission's opening beat has said by now.
    final all = 'ALL ${engine.transcript.length} ›';
    expect(engine.transcript.length, greaterThanOrEqualTo(6));
    expect(find.text(all), findsOneWidget);

    await tester.tap(find.text(all));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('TRANSCRIPT'), findsOneWidget);
    for (var i = 1; i <= 6; i++) {
      expect(find.textContaining('line $i', findRichText: true), findsWidgets, reason: 'line $i is reachable again');
    }

    await tester.tap(find.text('BACK TO THE RUN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('TRANSCRIPT'), findsNothing);

    await _stop(tester, run);
  });

  // The notification's buttons work without opening the app — including after
  // it has been swiped away, when the run carries on with no screen at all.
  testWidgets('Pause and Resume on the notification pause and resume the run', (tester) async {
    final run = await _startRun(tester);
    await run.run(tester, 30);
    expect(run.lastNotice['paused'], isFalse);

    await run.tapNotice(tester, 'pause');
    await run.run(tester, 1, mps: 0);
    expect(run.engine.phase, RunPhase.paused);
    expect(run.lastNotice['paused'], isTrue, reason: 'the button now offers Resume');
    expect(run.lastNotice['text'], startsWith('Paused'));
    expect(find.text('RESUME'), findsOneWidget, reason: 'the screen agrees');

    // The clock stands still while paused, and a fix does not resume a pause
    // the runner chose.
    final held = run.engine.elapsedSeconds;
    await run.run(tester, 20);
    expect(run.engine.phase, RunPhase.paused);
    expect(run.engine.elapsedSeconds, held);

    await run.tapNotice(tester, 'resume');
    await run.run(tester, 2);
    expect(run.engine.phase, RunPhase.running);
    expect(run.lastNotice['paused'], isFalse);

    await _stop(tester, run);
  });

  testWidgets('Stop on the notification asks first, short of the goal', (tester) async {
    final run = await _startRun(tester);
    await run.run(tester, 30);

    await run.tapNotice(tester, 'stop');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ABORT?'), findsOneWidget, reason: 'the same question the screen asks');
    expect(run.engine.phase, RunPhase.running, reason: 'nothing ends until the runner says so');

    await tester.tap(find.text('KEEP GOING'));
    // The first frame after a route pops only starts its animation.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ABORT?'), findsNothing);
    expect(run.engine.phase, RunPhase.running);

    await _stop(tester, run);
  });

  testWidgets('an unknown button is ignored, not thrown', (tester) async {
    final run = await _startRun(tester);
    await run.tapNotice(tester, 'self-destruct');
    expect(tester.takeException(), isNull);
    expect(run.engine.phase, RunPhase.running);
    await _stop(tester, run);
  });

  // A run used to live only in memory until finished, and a runner lost a
  // whole one by swiping the app away. The screen now keeps it on disk.
  testWidgets('the run in progress is saved as it goes, ready to be offered back', (tester) async {
    final run = await _startRun(tester);
    final store = run.state.activeRun;

    // Real file I/O never completes inside the fake-async zone (CLAUDE.md,
    // "Test traps"), so each second lets real time pass for the save to land.
    for (var i = 0; i < 40; i++) {
      await run.run(tester, 1);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    }

    final saved = await tester.runAsync(store.load);
    expect(saved, isNotNull, reason: 'saved within its first 15 seconds and kept current');
    expect(saved!.record.distanceMeters, greaterThan(60));
    expect(saved.record.missionId, run.engine.mission!.id);
    expect(run.engine.snapshot().elapsedSeconds - saved.record.elapsedSeconds, lessThan(16),
        reason: 'never more than one save interval behind');

    await _stop(tester, run);
  });
}
