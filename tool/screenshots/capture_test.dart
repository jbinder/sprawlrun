// Renders the app's screens to docs/screenshots/*.png, and the store's
// screenshots for every shipped language.
//
// This is a tool, not a test — it lives outside test/ so `flutter test` does
// not run it and write files as a side effect. Run it explicitly:
//
//     flutter test tool/screenshots/capture_test.dart
//
// It drives the real widgets with seeded data, so the images can never drift
// from what the app actually looks like. Fonts are loaded by hand because the
// test harness substitutes a placeholder font by default.
//
// With --dart-define=PSEUDO=true it renders every screen in the pseudo-locale
// instead (test/support/pseudo.dart) and writes to build/screenshots-pseudo/,
// never to the store: a look at what a longer translation does to each screen,
// and at any text that skipped the ARB — it is the text without brackets.
// --dart-define=LOCALE=es does the same in a shipped language, into
// build/screenshots-es/.
//
// Without either, one run renders every shipped language: English into
// docs/screenshots and the en-US listing, every other language into its own
// listing only — so no language's store shots can be forgotten.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/l10n/l10n.dart';
import 'package:sprawl_run/widgets/glitch_text.dart';
import 'package:sprawl_run/app.dart';
import 'package:sprawl_run/models/achievement.dart';
import 'package:sprawl_run/models/goal.dart';
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
import 'package:sprawl_run/widgets/unlock_reveal.dart';

import '../../test/support/fakes.dart';
import '../../test/support/pseudo_locale.dart';
import 'showcase.dart';

final GlobalKey _frame = GlobalKey();
const bool _pseudo = bool.fromEnvironment('PSEUDO');
const String _locale = String.fromEnvironment('LOCALE');

/// One language's shots: rendered in [strings] (null for English) and written
/// to [out] and, ranked, to the store listing [store]. Either may be absent.
class _Variant {
  const _Variant(this.name, this.strings, {this.out, this.store});

  final String name;
  final L? strings;
  final Directory? out;
  final Directory? store;
}

/// The store listing of language [code]: whichever fastlane locale directory
/// it already has (`es` → `es-ES`), else one named after the code.
Directory _listingFor(String code) {
  const root = 'fastlane/metadata/android';
  final existing = Directory(root).listSync().whereType<Directory>().map((d) => d.uri.pathSegments.reversed.skip(1).first);
  final dir = existing.firstWhere((n) => n == code || n.startsWith('$code-'), orElse: () => code);
  return Directory('$root/$dir/images/phoneScreenshots');
}

List<_Variant> _variants() {
  if (_pseudo) return [_Variant('pseudo', PseudoL(), out: Directory('build/screenshots-pseudo'))];
  if (_locale.isNotEmpty) {
    return [_Variant(_locale, lookupL(Locale(_locale)), out: Directory('build/screenshots-$_locale'))];
  }
  return [
    for (final locale in L.supportedLocales)
      locale.languageCode == 'en'
          ? _Variant('en', null, out: Directory('docs/screenshots'), store: _listingFor('en'))
          : _Variant(locale.languageCode, lookupL(locale), store: _listingFor(locale.languageCode)),
  ];
}

// The language being rendered; each group sets it before its shots.
late _Variant _current;
/// The language the seeded runner picked, so the story is in it too. The
/// pseudo-locale has no story translation, and English is the phone's.
String get _storyLanguage => _pseudo || _current.strings == null ? '' : _current.name;

List<LocalizationsDelegate<dynamic>> get _delegates =>
    _current.strings == null ? L.localizationsDelegates : delegatesFor(_current.strings!);

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
  setUpAll(loadFonts);

  for (final variant in _variants()) {
    group(variant.name, () {
      setUpAll(() {
        _current = variant;
        variant.out?.createSync(recursive: true);
        variant.store?.createSync(recursive: true);
        debugUseStrings(variant.strings);
      });
      tearDownAll(() => debugUseStrings(null));
      _shots();
    });
  }
}

void _shots() {

  testWidgets('dashboard', (tester) async {
    final state = await seedShowcase(tester, language: _storyLanguage);
    await _pump(tester, const HomeShell(), state);
    await _shoot(tester, 'dashboard');
  });

  testWidgets('mission brief', (tester) async {
    final state = await seedShowcase(tester, language: _storyLanguage);
    final mission = state.currentMission!.mission;
    await _pump(tester, MissionBriefScreen(mission: mission), state);
    await tester.pump(_typedOut);
    await _shoot(tester, 'briefing');
  });

  testWidgets('target picker', (tester) async {
    final state = await seedShowcase(tester, language: _storyLanguage);
    final mission = state.currentMission!.mission;
    await _pump(tester, MissionBriefScreen(mission: mission), state);
    await tester.pump(_typedOut);
    // The picker sits below the briefing text.
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, 'target');
  });

  testWidgets('run HUD mid-pursuit', (tester) async {
    final state = await seedShowcase(tester, language: _storyLanguage);
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
    final state = await seedShowcase(tester, language: _storyLanguage);
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
    final state = await seedShowcase(tester, language: _storyLanguage);
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
        .copyWith(trace: sampleRoute(seconds: 900, meters: 3100, fastFrom: 428, fastTo: 518));
    // Stored where the app keeps routes: the screen loads it from there.
    await tester.runAsync(() => state.runs.save(withStory));

    await _pump(tester, RunDetailScreen(run: withStory), state);
    // That load is real file I/O, which never completes inside the fake-async
    // zone — the shot used to be taken on LOADING TRACE. Each step of it
    // resumes inside the zone, so alternate real time with frames until the
    // route is in (CLAUDE.md, "Test traps").
    for (var i = 0; i < 40 && find.text(l10n.loadingTrace).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.text(l10n.loadingTrace), findsNothing, reason: 'the route never loaded');
    await tester.pump(const Duration(milliseconds: 400));
    // Scroll the story into view; the stats and route sit above it.
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump(const Duration(milliseconds: 400));
    await _shoot(tester, 'run-story');
  });

  testWidgets('mission packs', (tester) async {
    final state = await seedShowcase(tester, language: _storyLanguage);
    await _pump(tester, const MissionsScreen(), state);
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, 'packs');
  });

  testWidgets('stats', (tester) async {
    final state = await seedShowcase(tester, language: _storyLanguage);
    await _pump(tester, const HomeShell(), state);
    await tester.tap(find.text(l10n.navStats));
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, 'stats');
  });

  testWidgets('history', (tester) async {
    final state = await seedShowcase(tester, language: _storyLanguage);
    await _pump(tester, const HistoryScreen(), state);
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, 'history');
  });

  testWidgets('achievements', (tester) async {
    final state = await seedShowcase(tester, language: _storyLanguage);
    await _pump(tester, const HomeShell(), state);
    await tester.tap(find.text(l10n.navWall));
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, 'achievements');
  });

  testWidgets('codex', (tester) async {
    final state = await seedShowcase(tester, language: _storyLanguage);
    await _pump(tester, const HomeShell(), state);
    await tester.tap(find.text(l10n.navCodex));
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, 'codex');
  });
}

// ---------------------------------------------------------------------------

Future<void> _pump(WidgetTester tester, Widget home, AppState state, {RunEngine? engine}) =>
    pumpShowcase(tester, home, state, engine: engine, key: _frame, delegates: _delegates);

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
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();
    final out = _current.out;
    if (out != null) File('${out.path}/$name.png').writeAsBytesSync(bytes);
    final rank = _storeOrder[name];
    final store = _current.store;
    if (rank != null && store != null) File('${store.path}/${rank}_$name.png').writeAsBytesSync(bytes);
    image.dispose();
  });
}

