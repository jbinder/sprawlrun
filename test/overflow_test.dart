import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/app.dart';
import 'package:sprawl_run/l10n/l10n.dart';
import 'package:sprawl_run/models/achievement.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/run_outcome.dart';
import 'package:sprawl_run/screens/history_screen.dart';
import 'package:sprawl_run/screens/mission_brief_screen.dart';
import 'package:sprawl_run/screens/mission_debrief_screen.dart';
import 'package:sprawl_run/screens/missions_screen.dart';
import 'package:sprawl_run/screens/run_detail_screen.dart';
import 'package:sprawl_run/screens/run_screen.dart';
import 'package:sprawl_run/screens/run_summary_screen.dart';
import 'package:sprawl_run/screens/settings_screen.dart';
import 'package:sprawl_run/screens/timeline_screen.dart';
import 'package:sprawl_run/services/run_engine.dart';
import 'package:sprawl_run/state/app_state.dart';
import 'package:sprawl_run/util/clock.dart';
import 'package:sprawl_run/widgets/unlock_reveal.dart';

import '../tool/screenshots/showcase.dart';
import 'support/fakes.dart';
import 'support/pseudo_locale.dart';

/// Every screen, in the pseudo-locale, on a narrow phone.
///
/// Translations run longer than English — German and Spanish by a fifth to a
/// third, short labels by much more — and a label that only just fits in
/// English is a RenderFlex overflow in the first translation that arrives.
/// The harness reports an overflow as an error, so pumping a screen is the
/// whole assertion. Real fonts, since overflow is a matter of their metrics.
///
/// Story text is the pack's and stays English here; only the interface grows.
void main() {
  /// A small, common Android width. Tall where the screen scrolls, so a lazy
  /// list builds all of itself rather than the first screenful.
  const narrow = Size(360, 780);
  const tall = Size(360, 4000);

  setUpAll(() async {
    await loadFonts();
    debugUseStrings(PseudoL());
  });
  tearDownAll(() => debugUseStrings(null));

  Future<AppState> show(WidgetTester tester, Widget home, {Size size = tall, RunEngine? engine}) async {
    final state = await seedShowcase(tester, logicalSize: size);
    await pumpShowcase(tester, home, state, engine: engine, delegates: pseudoDelegates);
    return state;
  }

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('home tabs', (tester) async {
    await show(tester, const HomeShell());
    await tab(tester, l10n.navStats);
    await tab(tester, l10n.navWall);
    await tab(tester, l10n.navCodex);
  });

  testWidgets('home, with the season card and the backup nudge', (tester) async {
    final state = await seedShowcase(tester, logicalSize: tall);
    // The last days of SAMHAIN, so the card carries its closing note too.
    debugNow = DateTime(2026, 11, 1, 20);
    await tester.runAsync(() => state.updateProfile(state.profile.copyWith(lastExportAt: DateTime(2026, 8, 1))));
    expect(state.season, isNotNull);
    expect(state.backupNudge, isNotNull);
    await pumpShowcase(tester, const HomeShell(), state, delegates: pseudoDelegates);
  });

  testWidgets('home, with a campaign finished', (tester) async {
    final state = await seedShowcase(tester, logicalSize: tall);
    final pack = state.activePack!;
    await tester.runAsync(
      () => state.updateProfile(
        state.profile.copyWith(completedMissions: {...state.profile.completedMissions, for (final m in pack.missions) m.id}),
      ),
    );
    await pumpShowcase(tester, const HomeShell(), state, delegates: pseudoDelegates);
  });

  testWidgets('briefing and target picker', (tester) async {
    final state = await seedShowcase(tester, logicalSize: tall);
    await pumpShowcase(tester, MissionBriefScreen(mission: state.currentMission!.mission), state, delegates: pseudoDelegates);
    await tester.pump(const Duration(seconds: 20)); // typed out
    await tester.tap(find.text(l10n.goalDistance));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('free run briefing', (tester) async {
    await show(tester, const MissionBriefScreen(mission: null));
  });

  testWidgets('debriefing', (tester) async {
    final state = await seedShowcase(tester, logicalSize: tall);
    await pumpShowcase(tester, MissionDebriefScreen(mission: state.missionById('sp02')!), state, delegates: pseudoDelegates);
  });

  testWidgets('run screen, mid-pursuit', (tester) async {
    final state = await seedShowcase(tester, logicalSize: narrow);
    var now = DateTime(2026, 7, 27, 21, 14);
    final location = FakeLocation();
    final engine = RunEngine(
      narrator: FakeNarrator(lineDuration: const Duration(seconds: 6)),
      location: location,
      clock: () => now,
    );
    await pumpShowcase(
      tester,
      RunScreen(mission: state.currentMission!.mission, goal: const RunGoal(GoalType.time, 1500)),
      state,
      engine: engine,
      delegates: pseudoDelegates,
    );
    for (var i = 0; i < 1500 && engine.activeChase == null; i++) {
      now = now.add(const Duration(seconds: 1));
      location.step(now, 3.2);
      await tester.pump(const Duration(seconds: 1));
    }
    expect(engine.activeChase, isNotNull, reason: 'no pursuit to look at');
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text(l10n.abort.toUpperCase()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(l10n.keepGoing.toUpperCase()));
    await tester.pump(const Duration(milliseconds: 300));
    // Past the target, where the controls change.
    for (var i = 0; i < 900 && !engine.goalReached; i++) {
      now = now.add(const Duration(seconds: 1));
      location.step(now, 3.2);
      await tester.pump(const Duration(seconds: 1));
    }
    expect(engine.goalReached, isTrue);
    // Lets the line in flight run out before the tree is torn down.
    await tester.pump(const Duration(minutes: 2));
  });

  testWidgets('run summary and its reveal', (tester) async {
    final state = await seedShowcase(tester, logicalSize: narrow);
    final mission = state.currentMission!.mission;
    final report = RunOutcomeReport(
      record: run(at: DateTime(2026, 7, 27, 21, 14), meters: 8200, seconds: 2700, missionId: mission.id),
      newAchievements: [kAchievements.firstWhere((a) => a.tier == AchTier.legend)],
      codexRecovered: mission.codex.take(1).toList(),
      missionUnlocked: 'COOLING LOOP',
    );
    await pumpShowcase(tester, RunSummaryScreen(report: report, mission: mission), state, delegates: pseudoDelegates);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.tap(find.byType(UnlockReveal));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }
  });

  testWidgets('run detail', (tester) async {
    final state = await seedShowcase(tester, logicalSize: tall);
    await pumpShowcase(tester, RunDetailScreen(run: state.runLog.first), state, delegates: pseudoDelegates);
    for (var i = 0; i < 40 && find.text(l10n.loadingTrace).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.tap(find.byTooltip(l10n.deleteRun));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('mission packs', (tester) async {
    await show(tester, const MissionsScreen());
  });

  testWidgets('history', (tester) async {
    await show(tester, const HistoryScreen());
  });

  testWidgets('the wire', (tester) async {
    await show(tester, const TimelineScreen());
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  });

  testWidgets('settings, every row showing', (tester) async {
    final state = await seedShowcase(tester, logicalSize: const Size(360, 6000));
    await tester.runAsync(
      () => state.updateProfile(
        state.profile.copyWith(
          signals: state.profile.signals.copyWith(remindersEnabled: true, ambientPerWeek: 4),
          lastExportAt: DateTime(2026, 8, 1),
        ),
      ),
    );
    await pumpShowcase(tester, const SettingsScreen(), state, delegates: pseudoDelegates);
    await tester.tap(find.text(l10n.resetProgress.toUpperCase()));
    await tester.pump(const Duration(milliseconds: 300));
  });
}
