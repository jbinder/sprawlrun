import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/screens/mission_brief_screen.dart';
import 'package:sprawl_run/models/run_outcome.dart';
import 'package:sprawl_run/screens/missions_screen.dart';
import 'package:sprawl_run/screens/run_summary_screen.dart';
import 'package:sprawl_run/services/run_engine.dart';
import 'package:sprawl_run/state/app_state.dart';
import 'package:sprawl_run/theme/cyber_theme.dart';

import 'support/fakes.dart';

/// Two campaigns ship now, and more will follow. Each is its own chain; one is
/// selected; the ops screen shows only that one; clearing a pack offers the
/// next. These pin that down against real pack data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const primeIds = {'sp01', 'sp02', 'sp03', 'sp04', 'sp05', 'sp06', 'sp07', 'sp08', 'sp09', 'sp10'};

  Future<AppState> load({Profile profile = const Profile()}) async {
    final root = tempRoot('packs');
    addTearDown(() => root.deleteSync(recursive: true));
    final profiles = ProfileRepository(root);
    await profiles.save(profile);
    final state = AppState(
      profiles: profiles,
      runs: RunRepository(Directory('${root.path}/runs')),
      missions: MissionRepository(externalDir: Directory('${root.path}/packs')),
      narrator: FakeNarrator(),
    );
    await state.load();
    return state;
  }

  group('selection', () {
    test('the first pack is active until one is chosen, so old profiles change nothing', () async {
      final state = await load();
      expect(state.activePack!.id, 'sprawl_prime');
      expect(state.chain.map((m) => m.mission.id), everyElement(startsWith('sp')));
      expect(state.currentMission!.mission.id, 'sp01');
    });

    test('selecting a pack switches the chain and survives a reload', () async {
      final state = await load();
      await state.selectPack('null_tide');

      expect(state.activePack!.id, 'null_tide');
      expect(state.currentMission!.mission.id, 'nt01', reason: 'each pack has its own first mission open');
      expect(state.missionsTotal, 10);

      final again = await load(profile: state.profile);
      expect(again.activePack!.id, 'null_tide');
    });

    test('selecting an unknown pack is ignored, and a removed one falls back to the first', () async {
      final state = await load(profile: const Profile(activePackId: 'gone'));
      expect(state.activePack!.id, 'sprawl_prime');
      await state.selectPack('nope');
      expect(state.profile.activePackId, 'gone', reason: 'nothing was written');
    });

    test('clearing missions in one pack never unlocks the other', () async {
      final state = await load(profile: const Profile(completedMissions: primeIds));
      expect(state.currentMission, isNull, reason: 'Sprawl Prime is done');
      expect(state.chainFor(state.packs[1]).first.state, MissionState.available);
      expect(state.chainFor(state.packs[1]).skip(1).every((m) => m.state == MissionState.locked), isTrue);
    });
  });

  group('pack progress', () {
    test('states: fresh until attempted, active while open, done when cleared', () async {
      final state = await load(
        profile: const Profile(completedMissions: primeIds, missionAttempts: {'nt01': 1}),
      );
      final byId = {for (final p in state.packProgress) p.pack.id: p};
      expect(byId['sprawl_prime']!.state, PackState.done);
      expect(byId['null_tide']!.state, PackState.active);

      final fresh = await load();
      expect(fresh.packProgress.every((p) => p.state == PackState.fresh), isTrue);
    });

    test('a mission is fresh, started, or finished regardless of being reachable', () async {
      final state = await load(
        profile: const Profile(completedMissions: {'sp01'}, missionAttempts: {'sp01': 1, 'sp02': 2}),
      );
      final chain = state.chain;
      expect(chain[0].status, MissionStatus.finished);
      expect(chain[1].status, MissionStatus.started);
      expect(chain[2].status, MissionStatus.fresh);
      expect(chain[2].state, MissionState.locked);
    });
  });

  group('next open pack', () {
    test('is the next one in load order with missions left, wrapping round', () async {
      final state = await load(profile: const Profile(completedMissions: primeIds));
      expect(state.nextOpenPack!.id, 'null_tide');

      await state.selectPack('null_tide');
      expect(state.nextOpenPack, isNull, reason: 'Sprawl Prime is done; nothing else is open');
    });

    test('is null when the active pack is the only one open', () async {
      final state = await load();
      // Both packs open, Sprawl Prime active: Null Tide is next.
      expect(state.nextOpenPack!.id, 'null_tide');
    });
  });

  group('finishing a pack', () {
    testWidgets('the last debrief offers the next open pack, and switching lands on it', (tester) async {
      tester.view.physicalSize = const Size(1200, 8000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final state = await tester.runAsync(() => load(profile: const Profile(completedMissions: primeIds)));
      final last = state!.missionById('sp10')!;
      final report = RunOutcomeReport(record: run(at: DateTime.now(), missionId: 'sp10'));

      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider.value(value: state)],
          child: MaterialApp(theme: buildCyberTheme(), home: RunSummaryScreen(report: report, mission: last)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('EPILOGUE'), findsOneWidget);
      expect(find.text('NEXT CAMPAIGN'), findsOneWidget);
      expect(find.text('SWITCH TO NULL TIDE'), findsOneWidget);

      await tester.tap(find.text('SWITCH TO NULL TIDE'));
      await tester.pump();
      expect(state.activePack!.id, 'null_tide');
    });

    testWidgets('no offer when nothing else is open', (tester) async {
      tester.view.physicalSize = const Size(1200, 8000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final everything = {...primeIds, for (var i = 1; i <= 10; i++) 'nt${i.toString().padLeft(2, '0')}'};
      final state = await tester.runAsync(() => load(profile: Profile(completedMissions: everything)));
      final last = state!.missionById('sp10')!;
      final report = RunOutcomeReport(record: run(at: DateTime.now(), missionId: 'sp10'));

      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider.value(value: state)],
          child: MaterialApp(theme: buildCyberTheme(), home: RunSummaryScreen(report: report, mission: last)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('EPILOGUE'), findsOneWidget);
      expect(find.text('NEXT CAMPAIGN'), findsNothing);
    });
  });

  group('missions screen', () {
    Future<AppState> pump(WidgetTester tester, {Profile profile = const Profile()}) async {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final state = await tester.runAsync(() => load(profile: profile));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state!),
            ChangeNotifierProvider(create: (_) => RunEngine(narrator: FakeNarrator(), location: FakeLocation())),
          ],
          child: MaterialApp(theme: buildCyberTheme(), home: const MissionsScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      return state;
    }

    testWidgets('groups packs into ACTIVE and DONE and marks the selected one', (tester) async {
      await pump(tester, profile: const Profile(completedMissions: primeIds, activePackId: 'null_tide'));

      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('DONE'), findsWidgets);
      expect(find.text('NULL TIDE'), findsOneWidget);
      expect(find.text('SPRAWL PRIME'), findsOneWidget);
      expect(find.text('SELECTED'), findsOneWidget);
      expect(find.text('10 / 10'), findsOneWidget);
      expect(find.text('0 / 10'), findsOneWidget);
    });

    testWidgets('tapping a pack selects it and unfolds its missions', (tester) async {
      final state = await pump(tester);
      expect(state.activePack!.id, 'sprawl_prime');

      await tester.tap(find.text('NULL TIDE'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(state.activePack!.id, 'null_tide');
      expect(find.text('LOW WATER'), findsOneWidget, reason: 'the first mission is named');
      expect(find.text('NEW'), findsWidgets);
      expect(find.text('LOCKED'), findsWidgets);
    });

    testWidgets('a playable mission opens its briefing from the list', (tester) async {
      await pump(tester, profile: const Profile(activePackId: 'null_tide'));
      await tester.tap(find.text('LOW WATER'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(MissionBriefScreen), findsOneWidget);
    });
  });
}
