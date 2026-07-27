import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sprawl_run/app.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/screens/mission_brief_screen.dart';
import 'package:sprawl_run/services/run_engine.dart';
import 'package:sprawl_run/state/app_state.dart';
import 'package:sprawl_run/theme/cyber_theme.dart';

import 'support/fakes.dart';

/// Boots the real app against throwaway storage and a silent narrator.
///
/// Nothing here is mocked except audio and GPS, so these tests exercise the
/// same widgets, theme and mission JSON that ship.
///
/// Loading happens inside [WidgetTester.runAsync] because it touches the file
/// system and the asset bundle; a widget test's fake-async zone would never
/// complete those futures.
Future<AppState> pumpApp(WidgetTester tester, {Profile? profile}) async {
  final root = tempRoot('widget');
  addTearDown(() => root.deleteSync(recursive: true));

  // A tall viewport so the whole dashboard builds at once — a lazy ListView
  // only creates the children near the visible area, and these tests are about
  // the full mission chain rather than about scrolling.
  tester.view.physicalSize = const Size(1200, 7800);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final profiles = ProfileRepository(root);
  final state = AppState(
    profiles: profiles,
    runs: RunRepository(Directory('${root.path}/runs')),
    missions: MissionRepository(externalDir: Directory('${root.path}/packs')),
    narrator: FakeNarrator(),
  );

  await tester.runAsync(() async {
    if (profile != null) await profiles.save(profile);
    await state.load();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider(
          create: (_) => RunEngine(narrator: FakeNarrator(), location: FakeLocation()),
        ),
      ],
      child: MaterialApp(theme: buildCyberTheme(), home: const HomeShell()),
    ),
  );
  // The backdrop animates forever, so settling is not an option; a couple of
  // explicit frames is enough for everything to lay out.
  await tester.pump(const Duration(milliseconds: 100));
  return state;
}

void main() {
  testWidgets('the dashboard shows the campaign with only the first op unlocked', (tester) async {
    await pumpApp(tester);

    expect(find.text('SPRAWL//RUN'), findsWidgets);
    expect(find.text('NEXT OPERATION'), findsOneWidget);
    expect(find.text('DEAD DROP'), findsWidgets);

    // Nine locked missions, each redacted rather than spoiled.
    expect(find.text('LOCKED'), findsNWidgets(9));
    expect(find.text('█████████'), findsNWidgets(9));
    expect(find.text('MEAT MARKET'), findsNothing, reason: 'a locked mission must not reveal its codename');
  });

  testWidgets('clearing missions moves the chain forward', (tester) async {
    await pumpApp(tester, profile: const Profile(completedMissions: {'sp01', 'sp02'}));

    expect(find.text('CLEARED'), findsNWidgets(2));
    expect(find.text('LOCKED'), findsNWidgets(7));
    expect(find.text('GHOST SIGNAL'), findsWidgets, reason: 'the third op is now the active one');
    expect(find.text('2/10'), findsOneWidget);
  });

  testWidgets('a locked mission cannot be opened', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('█████████').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(MissionBriefScreen), findsNothing);
  });

  testWidgets('the active mission opens its briefing and a goal can be set', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('OPEN BRIEFING'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(MissionBriefScreen), findsOneWidget);
    expect(find.text('BRIEFING'), findsOneWidget);
    expect(find.text('SET YOUR TARGET'), findsOneWidget);
    // Mission one suggests 15 minutes.
    expect(find.text('15 min'), findsWidgets);

    // Switch to a distance target; the readout follows.
    await tester.tap(find.text('DISTANCE'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('5.00 km'), findsWidgets);

    await tester.tap(find.text('3.00 km').last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('BEGIN OPERATION'), findsOneWidget);
  });

  testWidgets('the free run route needs no mission', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('FREE RUN — NO MISSION'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('FREE RUN'), findsWidgets);
    expect(find.text('START RUN'), findsOneWidget);
    expect(find.text('BRIEFING'), findsNothing);
  });

  testWidgets('empty stats and codex explain themselves instead of showing zeroes', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('STATS'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('NO TELEMETRY YET'), findsOneWidget);

    await tester.tap(find.text('CODEX'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('NOTHING RECOVERED YET'), findsOneWidget);
  });

  testWidgets('the achievement wall lists everything, all locked at the start', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('WALL'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('UNLOCKED'), findsOneWidget, reason: 'the header counter, not a single earned card');
    expect(find.text('First Kilometres'), findsWidgets);
    expect(find.text('0 / 46'), findsNothing, reason: 'the count is rendered as separate spans');
  });

  testWidgets('stats appear once there are runs to report', (tester) async {
    final state = await pumpApp(tester);
    await tester.runAsync(
      () => state.completeRun(run(at: DateTime.now(), meters: 5000, seconds: 1800, calories: 380)),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('STATS'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('LAST 7 DAYS'), findsOneWidget);
    expect(find.text('LAST 30 DAYS'), findsOneWidget);
    expect(find.text('LIFETIME'), findsOneWidget);
    expect(find.text('5.00'), findsWidgets, reason: 'distance in km');
  });

  testWidgets('the streak card reflects the runner\'s own weekly goal', (tester) async {
    final state = await pumpApp(
      tester,
      profile: const Profile(streakGoal: StreakGoal(metric: StreakMetric.kilometres, target: 20)),
    );
    await tester.runAsync(() => state.completeRun(run(at: DateTime.now(), meters: 8000, seconds: 2400)));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('8.0 / 20.0 KM'), findsOneWidget);
    expect(find.textContaining('12.0 KM to go'), findsOneWidget);
  });
}
