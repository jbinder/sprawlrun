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
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sprawl_run/app.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/screens/mission_brief_screen.dart';
import 'package:sprawl_run/screens/run_screen.dart';
import 'package:sprawl_run/services/run_engine.dart';
import 'package:sprawl_run/state/app_state.dart';
import 'package:sprawl_run/theme/cyber_theme.dart';

import '../../test/support/fakes.dart';

/// Roughly a modern phone: 393x852 logical at 3x.
const Size _logicalSize = Size(393, 852);
const double _pixelRatio = 3.0;

final GlobalKey _frame = GlobalKey();
final Directory _out = Directory('docs/screenshots');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _out.createSync(recursive: true);
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
    // Let the briefing finish typing itself out.
    await tester.pump(const Duration(seconds: 4));
    await _shoot(tester, 'briefing');
  });

  testWidgets('target picker', (tester) async {
    final state = await _seed(tester);
    final mission = state.currentMission!.mission;
    await _pump(tester, MissionBriefScreen(mission: mission), state);
    await tester.pump(const Duration(seconds: 4));
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
  });

  testWidgets('stats', (tester) async {
    final state = await _seed(tester);
    await _pump(tester, const HomeShell(), state);
    await tester.tap(find.text('STATS'));
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, 'stats');
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
Future<AppState> _seed(WidgetTester tester) async {
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

  await tester.runAsync(() async {
    await profiles.save(
      Profile(
        callsign: 'MOLLY',
        weightKg: 68,
        // The run HUD would otherwise call wakelock_plus, which has no
        // implementation in the test harness. It has no visual effect.
        keepScreenOn: false,
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

    // Six weeks of running, denser in recent weeks, with the story runs mixed
    // in. Anchored to today so regenerating always shows a live current week.
    final base = DateTime.now();
    final today = DateTime(base.year, base.month, base.day, 7, 30);
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
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_frame));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${_out.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
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
