// The seeded runner the screenshot tool photographs, shared with the overflow
// test so both look at the same, fully populated screens.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/l10n/l10n.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/services/run_engine.dart';
import 'package:sprawl_run/state/app_state.dart';
import 'package:sprawl_run/theme/cyber_theme.dart';
import 'package:sprawl_run/util/clock.dart';
import 'package:sprawl_run/widgets/edge_fade.dart';

import '../../test/support/fakes.dart';

/// Roughly a modern phone: 393x852 logical at 3x.
const Size phoneSize = Size(393, 852);
const double pixelRatio = 3.0;

/// A believable loop for a run with no real GPS behind it: a wobbling closed
/// circuit of [meters] over [seconds], a point every three seconds as the
/// recorder takes them, and quicker between [fastFrom] and [fastTo] — the
/// pursuit — so the speed colouring has something true to show.
List<TracePoint> sampleRoute({
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
final shotsTakenAt = DateTime(2026, 9, 27, 21, 0);

/// A runner several weeks into the campaign, so no screen is empty, on a phone
/// of [logicalSize], who picked [language] in Settings (empty: the phone's).
///
/// The language has to be the runner's, not only the screen's: `AppState`
/// localizes the story packs from it, so swapping the interface strings alone
/// shows a Spanish screen around an English briefing.
Future<AppState> seedShowcase(WidgetTester tester, {Size logicalSize = phoneSize, String language = ''}) async {
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
  debugNow = shotsTakenAt;
  addTearDown(() => debugNow = null);

  tester.view.physicalSize = logicalSize * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
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
  final base = shotsTakenAt;
  final today = DateTime(base.year, base.month, base.day, 7, 30);

  await tester.runAsync(() async {
    await profiles.save(
      Profile(
        callsign: 'MOLLY',
        weightKg: 68,
        language: language,
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

/// [home] in the app's theme, with [state] and [engine] provided, in English
/// or in whatever language [delegates] supply.
Future<void> pumpShowcase(
  WidgetTester tester,
  Widget home,
  AppState state, {
  RunEngine? engine,
  Key? key,
  List<LocalizationsDelegate<dynamic>> delegates = L.localizationsDelegates,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider(
            create: (_) => engine ?? RunEngine(narrator: FakeNarrator(), location: FakeLocation()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: delegates,
          debugShowCheckedModeBanner: false,
          theme: buildCyberTheme(),
          scrollBehavior: const CyberScrollBehavior(),
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

/// The test harness swaps in a placeholder font unless the real ones are
/// registered explicitly, which would render every screenshot as boxes.
///
/// Reads FontManifest.json rather than naming families here, so it picks up
/// MaterialIcons (for the icons) and anything added to pubspec.yaml later.
Future<void> loadFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    for (final font in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}
