// Renders the app's screens to docs/screenshots/*.png.
//
// This is a tool, not a test — it lives outside test/ so `flutter test` does
// not run it and write files as a side effect. Run it explicitly:
//
//     flutter test tool/screenshots/capture_test.dart
//
// It drives the real widgets with seeded data, so the images can never drift
// from what the app actually looks like. Fonts are loaded by hand because the
// test harness substitutes a placeholder font by default.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sprawl_run/widgets/glitch_text.dart';
import 'package:sprawl_run/app.dart';
import 'package:sprawl_run/util/clock.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/achievement.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/run_outcome.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/screens/history_screen.dart';
import 'package:sprawl_run/screens/mission_brief_screen.dart';
import 'package:sprawl_run/screens/missions_screen.dart';
import 'package:sprawl_run/screens/run_detail_screen.dart';
import 'package:sprawl_run/screens/run_screen.dart';
import 'package:sprawl_run/screens/run_summary_screen.dart';
import 'package:sprawl_run/services/run_engine.dart';
import 'package:sprawl_run/state/app_state.dart';
import 'package:sprawl_run/theme/cyber_theme.dart';
import 'package:sprawl_run/widgets/unlock_reveal.dart';

import '../../test/support/fakes.dart';

/// Roughly a modern phone: 393x852 logical at 3x.
const Size _logicalSize = Size(393, 852);
const double _pixelRatio = 3.0;

final GlobalKey _frame = GlobalKey();
final Directory _out = Directory('docs/screenshots');

/// Long enough for any [TypewriterText] to finish typing itself out.
///
/// It types at 90 characters a second and clamps its own duration to twenty
/// seconds, so nothing can still be mid-type after this. Four seconds was
/// enough until a mission brief grew past 360 characters, at which point the
/// published store screenshot showed a sentence cut off mid-word — which reads
/// as a layout bug rather than an animation.
const Duration _typedOut = Duration(seconds: 20);

/// The store listing's own copy, which F-Droid shows in this order.
///
/// Written here rather than copied by hand, because copying by hand is what
/// left the published listing on screenshots from 0.1.0 — taken before the
/// second campaign existed — while `docs/screenshots` moved on without them.
/// A shot missing from this map is documentation only.
final Directory _store = Directory('fastlane/metadata/android/en-US/images/phoneScreenshots');
const Map<String, int> _storeOrder = {
  'dashboard': 1,
  'run-hud': 2,
  'briefing': 3,
  'target': 4,
  'stats': 5,
  'history': 6,
  'achievements': 7,
  'codex': 8,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _out.createSync(recursive: true);
    _store.createSync(recursive: true);
    await _loadFonts();
  });

  testWidgets('dashboard', (tester) async {
    final state = await _seed(tester);
    await _pump(tester, const HomeShell(), state);
    await _shoot(tester, 'dashboard');
  });

  testWidgets('mission brief', (tester) async {
    final state = await _seed(tester);
    final mission = state.currentMission!.mission;
    await _pump(tester, MissionBriefScreen(mission: mission), state);
    await tester.pump(_typedOut);
    await _shoot(tester, 'briefing');
  });

  testWidgets('target picker', (tester) async {
    final state = await _seed(tester);
    final mission = state.currentMission!.mission;
    await _pump(tester, MissionBriefScreen(mission: mission), state);
    await tester.pump(_typedOut);
    // The picker sits below the briefing text.
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, 'target');
  });

  testWidgets('run HUD mid-pursuit', (tester) async {
    final state = await _seed(tester);
    final mission = state.currentMission!.mission;

    var now = DateTime(2026, 7, 27, 21, 14);
    final location = FakeLocation();
    final engine = RunEngine(
      narrator: FakeNarrator(lineDuration: const Duration(seconds: 6)),
      location: location,
      clock: () => now,
    );

    await _pump(
      tester,
      RunScreen(mission: mission, goal: const RunGoal(GoalType.time, 1500)),
      state,
      engine: engine,
    );

    // Run at a steady 3.2 m/s until a pursuit opens — that is the shot worth
    // having. This mission's chase sits at 48% of the target, so it takes
    // around twelve simulated minutes to arrive.
    for (var i = 0; i < 1500 && engine.activeChase == null; i++) {
      now = now.add(const Duration(seconds: 1));
      location.step(now, 3.2);
      await tester.pump(const Duration(seconds: 1));
    }
    // A few more seconds so the chase bar shows progress rather than zero.
    for (var i = 0; i < 12; i++) {
      now = now.add(const Duration(seconds: 1));
      location.step(now, 4.1);
      await tester.pump(const Duration(seconds: 1));
    }
    await _shoot(tester, 'run-hud');

    // The fake narrator holds a timer for the length of every line it speaks,
    // and the harness fails any test that disposes the tree with one pending.
    // The clock is frozen now, so the engine's tick advances nothing and no
    // further beats can fire — this only lets the line in flight run out.
    await tester.pump(const Duration(minutes: 2));
  });

  testWidgets('unlock reveal', (tester) async {
    final state = await _seed(tester);
    final mission = state.currentMission!.mission;
    // A LEGEND-tier card is the one worth showing: amber, the rarest band.
    final legend = kAchievements.firstWhere((a) => a.tier == AchTier.legend);
    final report = RunOutcomeReport(
      record: run(at: DateTime(2026, 7, 27, 21, 14), meters: 8200, seconds: 2700, missionId: mission.id),
      newAchievements: [legend],
      codexRecovered: mission.codex.take(1).toList(),
      missionUnlocked: 'COOLING LOOP',
    );

    await _pump(tester, RunSummaryScreen(report: report, mission: mission), state);
    // Past the mission card and the codex card, onto the achievement. Two pumps
    // per step: the first frame after an animation starts only sets its clock.
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byType(UnlockReveal));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }
    // Let the boot finish, the stamp land, and the description type out. The
    // halo is caught mid-drift, which is what it looks like in the hand.
    await tester.pump(const Duration(milliseconds: 2500));
    await _shoot(tester, 'unlock');
  });

  testWidgets('run story', (tester) async {
    final state = await _seed(tester);
    final mission = state.missionById('sp01')!;
    // A log shaped like a real playthrough: the opening two beats with their
    // recovery, a pursuit that was shaken, and the target falling at the end.
    final beats = mission.beats;
    final record = run(at: DateTime(2026, 7, 6, 19, 40), meters: 3100, seconds: 900, missionId: 'sp01').copyWith();
    final story = <StoryEvent>[
      StoryEvent(atSeconds: 2, kind: StoryEventKind.beat, ref: beats[0].id),
      if (beats[0].unlocksCodex != null) StoryEvent(atSeconds: 3, kind: StoryEventKind.codex, ref: beats[0].unlocksCodex),
      StoryEvent(atSeconds: 131, kind: StoryEventKind.beat, ref: beats[1].id),
      if (beats[1].unlocksCodex != null) StoryEvent(atSeconds: 132, kind: StoryEventKind.codex, ref: beats[1].unlocksCodex),
      const StoryEvent(atSeconds: 428, kind: StoryEventKind.chaseStarted, ref: 'NINSEI DRONE'),
      const StoryEvent(atSeconds: 518, kind: StoryEventKind.chaseEnded, ref: 'NINSEI DRONE', escaped: true),
      const StoryEvent(atSeconds: 900, kind: StoryEventKind.goal),
    ];
    final withStory = RunRecord.fromJson(record.toJson()..['story'] = story.map((e) => e.toJson()).toList())
        .copyWith(trace: _sampleRoute(seconds: 900, meters: 3100, fastFrom: 428, fastTo: 518));
    // Stored where the app keeps routes: the screen loads it from there.
    await tester.runAsync(() => state.runs.save(withStory));

    await _pump(tester, RunDetailScreen(run: withStory), state);
    // That load is real file I/O, which never completes inside the fake-async
    // zone — the shot used to be taken on LOADING TRACE. Each step of it
    // resumes inside the zone, so alternate real time with frames until the
    // route is in (CLAUDE.md, "Test traps").
    for (var i = 0; i < 40 && find.text('LOADING TRACE').evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.text('LOADING TRACE'), findsNothing, reason: 'the route never loaded');
    await tester.pump(const Duration(milliseconds: 400));
    // Scroll the story into view; the stats and route sit above it.
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump(const Duration(milliseconds: 400));
    await _shoot(tester, 'run-story');
  });

  testWidgets('mission packs', (tester) async {
    final state = await _seed(tester);
    await _pump(tester, const MissionsScreen(), state);
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, 'packs');
  });

  testWidgets('stats', (tester) async {
    final state = await _seed(tester);
    await _pump(tester, const HomeShell(), state);
    await tester.tap(find.text('STATS'));
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, 'stats');
  });

  testWidgets('history', (tester) async {
    final state = await _seed(tester);
    await _pump(tester, const HistoryScreen(), state);
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, 'history');
  });

  testWidgets('achievements', (tester) async {
    final state = await _seed(tester);
    await _pump(tester, const HomeShell(), state);
    await tester.tap(find.text('WALL'));
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, 'achievements');
  });

  testWidgets('codex', (tester) async {
    final state = await _seed(tester);
    await _pump(tester, const HomeShell(), state);
    await tester.tap(find.text('CODEX'));
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, 'codex');
  });
}

// ---------------------------------------------------------------------------

/// A runner several weeks into the campaign, so no screen is empty.
/// A believable loop for a run with no real GPS behind it: a wobbling closed
/// circuit of [meters] over [seconds], a point every three seconds as the
/// recorder takes them, and quicker between [fastFrom] and [fastTo] — the
/// pursuit — so the speed colouring has something true to show.
List<TracePoint> _sampleRoute({
  required int seconds,
  required double meters,
  required int fastFrom,
  required int fastTo,
}) {
  const lat0 = 35.6595, lon0 = 139.7005; // where the campaign's media district would be
  final mPerDegLat = 111320.0;
  final mPerDegLon = 111320.0 * math.cos(lat0 * math.pi / 180);

  double speedAt(int t) => t >= fastFrom && t <= fastTo ? 4.4 : 3.1;
  // Distance covered by second t, scaled so the loop closes at [meters].
  final raw = <double>[0];
  for (var t = 1; t <= seconds; t++) {
    raw.add(raw.last + speedAt(t));
  }
  final scale = meters / raw.last;

  // An irregular closed loop: a circle with a few harmonics, so it reads as
  // streets rather than geometry. Its perimeter is close enough to [meters].
  final radius = meters / (2 * math.pi);
  return [
    for (var t = 0; t <= seconds; t += 3)
      () {
        final a = 2 * math.pi * raw[t] * scale / meters;
        final r = radius * (1 + 0.18 * math.sin(3 * a) + 0.07 * math.cos(5 * a + 1));
        return TracePoint(
          lat: lat0 + r * math.sin(a) / mPerDegLat,
          lon: lon0 + r * 1.3 * math.cos(a) / mPerDegLon,
          elapsedSeconds: t.toDouble(),
          speedMps: speedAt(t),
        );
      }(),
  ];
}

/// When the screenshots claim to be taken. A Sunday, so the sample weeks are
/// all whole.
final _shotsTakenAt = DateTime(2026, 9, 27, 21, 0);

Future<AppState> _seed(WidgetTester tester) async {
  // The run screen asks for notification permission before it starts the run,
  // and an unanswered platform call never returns in the harness — so the HUD
  // shots showed a run stuck on STANDBY at 00:00 until this answered it.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('io.github.jbinder.sprawlrun/notifications'),
    (call) async => true,
  );

  // The app's "now", pinned: a Sunday evening, so every week in the sample
  // data is complete — on a real Monday the current week was nearly empty and
  // the streak card read "1 MIN to go" — and the hour of the run-HUD shot,
  // which is also the night city's greeting. Every shot is then the same
  // whenever and wherever the tool runs.
  debugNow = _shotsTakenAt;
  addTearDown(() => debugNow = null);

  tester.view.physicalSize = _logicalSize * _pixelRatio;
  tester.view.devicePixelRatio = _pixelRatio;
  addTearDown(tester.view.reset);

  final root = tempRoot('shots');
  addTearDown(() => root.deleteSync(recursive: true));

  final profiles = ProfileRepository(root);
  final runs = RunRepository(Directory('${root.path}/runs'));

  final state = AppState(
    profiles: profiles,
    runs: runs,
    missions: MissionRepository(externalDir: Directory('${root.path}/packs')),
    narrator: FakeNarrator(),
  );

  // Anchored to today so regenerating always shows a live current week.
  final base = _shotsTakenAt;
  final today = DateTime(base.year, base.month, base.day, 7, 30);

  await tester.runAsync(() async {
    await profiles.save(
      Profile(
        callsign: 'MOLLY',
        weightKg: 68,
        // The run HUD would otherwise call wakelock_plus, which has no
        // implementation in the test harness. It has no visual effect.
        keepScreenOn: false,
        // A showcase device is one whose runner keeps backups. Without this the
        // dashboard leads with the ARCHIVE DRIFT nudge, which is a maintenance
        // warning rather than the app, and it pushes NEXT OPERATION off-screen.
        // Dated with the runs, which are anchored to today, or every seeded run
        // counts as unsaved and the nudge comes back.
        lastExportAt: today,
        completedMissions: const {'sp01', 'sp02', 'sp03'},
        unlockedCodex: const {
          'cdx_courier', 'cdx_ninsei', 'cdx_clinic', //
          'cdx_registry', 'cdx_halcyon', 'cdx_sublevel',
        },
        missionAttempts: const {'sp01': 1, 'sp02': 2, 'sp03': 1},
        unlockedAchievements: {
          'mission_1': DateTime(2026, 7, 6),
          'mission_3': DateTime(2026, 7, 20),
          'dist_5k': DateTime(2026, 7, 6),
          'dist_25k': DateTime(2026, 7, 14),
          'time_1h': DateTime(2026, 7, 8),
          'single_5k': DateTime(2026, 7, 11),
          'runs_10': DateTime(2026, 7, 22),
          'streak_2': DateTime(2026, 7, 13),
          'chase_5': DateTime(2026, 7, 18),
          'night_5': DateTime(2026, 7, 24),
          'pace_600': DateTime(2026, 7, 19),
        },
      ),
    );

    // Six weeks of running, denser in recent weeks, with the story runs mixed in.
    var i = 0;
    for (final spec in _history) {
      await runs.save(
        run(
          at: today.subtract(Duration(days: spec.$1, hours: i % 9)),
          meters: spec.$2,
          seconds: spec.$3,
          calories: spec.$2 * 0.062,
          missionId: spec.$4,
          outcome: spec.$4 == null || spec.$5 ? RunOutcome.success : RunOutcome.failed,
          chasesTotal: spec.$4 == null ? 0 : 1,
          chasesEvaded: spec.$4 == null ? 0 : (spec.$5 ? 1 : 0),
          beatsHeard: spec.$4 == null ? 0 : 10,
        ),
      );
      i++;
    }

    await state.load();
  });

  return state;
}

/// (days ago, metres, seconds, missionId, succeeded)
const List<(int, double, double, String?, bool)> _history = [
  (0, 5240, 1720, null, true),
  (1, 8100, 2760, 'sp03', true),
  (2, 4600, 1610, null, true),
  (4, 4300, 1500, null, true),
  (5, 6200, 2050, null, true),
  (7, 5000, 1680, 'sp02', true),
  (9, 3600, 1320, null, true),
  (11, 7400, 2510, null, true),
  (12, 2900, 1100, 'sp02', false),
  (14, 5100, 1780, null, true),
  (16, 4800, 1650, null, true),
  (18, 9200, 3200, null, true),
  (19, 3300, 1220, 'sp01', true),
  (22, 5600, 1930, null, true),
  (25, 4100, 1480, null, true),
  (28, 6800, 2400, null, true),
  (31, 3900, 1400, null, true),
  (35, 5200, 1850, null, true),
  (38, 4400, 1600, null, true),
];

Future<void> _pump(WidgetTester tester, Widget home, AppState state, {RunEngine? engine}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: _frame,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider(
            create: (_) => engine ?? RunEngine(narrator: FakeNarrator(), location: FakeLocation()),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildCyberTheme(),
          // Animations off, so anything that draws itself in — the route
          // trace, for one — is captured finished rather than mid-flight.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: home,
        ),
      ),
    ),
  );
  // A handful of frames: enough for layout and the intro animations to land,
  // without waiting on the backdrop, which never settles.
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _shoot(WidgetTester tester, String name) async {
  // Forced rather than waited for: the RGB split fires on a random timer for a
  // few percent of the time, so an unforced capture loses it as often as not.
  // Only a fraction of the titles, because all of them tearing at once never
  // happens in the app. Half-way through the 320ms decay rather than at the
  // start — at full offset the text is unreadable, and the point is a colour
  // fringe that reads as deliberate. Late in the decay rather than mid, because
  // the offset is re-rolled every frame: at 220ms of 320ms even the largest
  // roll is under 1.5px, so a regenerated shot can never come out illegible.
  GlitchText.debugGlitchSome();
  await tester.pump(const Duration(milliseconds: 220));

  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_frame));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();
    File('${_out.path}/$name.png').writeAsBytesSync(bytes);
    final rank = _storeOrder[name];
    if (rank != null) File('${_store.path}/${rank}_$name.png').writeAsBytesSync(bytes);
    image.dispose();
  });
}

/// The test harness swaps in a placeholder font unless the real ones are
/// registered explicitly, which would render every screenshot as boxes.
///
/// Reads FontManifest.json rather than naming families here, so it picks up
/// MaterialIcons (for the icons) and anything added to pubspec.yaml later.
Future<void> _loadFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    for (final font in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}
