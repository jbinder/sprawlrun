import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/l10n/l10n.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sprawl_run/screens/settings_screen.dart';
import 'package:sprawl_run/state/app_state.dart';
import 'package:sprawl_run/theme/cyber_theme.dart';
import 'package:sprawl_run/util/clock.dart';

import 'support/fakes.dart';

/// Boots the settings screen alone against throwaway storage.
///
/// The tall viewport is the usual trick: the settings list is lazy, and these
/// tests care about rows near the bottom of it.
Future<AppState> pumpSettings(WidgetTester tester, {Profile? profile}) async {
  final root = tempRoot('settings');
  addTearDown(() => root.deleteSync(recursive: true));

  // Settings is a long lazy list; this is tall enough that the DATA section at
  // the very bottom is built rather than scrolled to.
  tester.view.physicalSize = const Size(1200, 24000);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  // package_info_plus has no platform side in the harness; without this the
  // colophon would just say OFFLINE BUILD, which is also what the tests check
  // it falls back to when the values are absent.
  PackageInfo.setMockInitialValues(
    appName: 'SPRAWL//RUN',
    packageName: 'io.github.jbinder.sprawlrun',
    version: '9.9.9',
    buildNumber: '999',
    buildSignature: '',
  );

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
      providers: [ChangeNotifierProvider.value(value: state)],
      child: MaterialApp(localizationsDelegates: L.localizationsDelegates, theme: buildCyberTheme(), home: const SettingsScreen()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return state;
}

void main() {
  testWidgets('changing the weekly target records the change, so past weeks keep theirs', (tester) async {
    final state = await pumpSettings(tester, profile: const Profile(streakGoal: StreakGoal(target: 30)));
    final plus = find.descendant(
      of: find.ancestor(of: find.text('Weekly target'), matching: find.byType(Row)).first,
      matching: find.byIcon(Icons.add),
    );
    await tester.tap(plus);
    await tester.pump();

    expect(state.profile.streakGoal.target, greaterThan(30));
    expect(state.profile.streakGoalChanges.first.goal.target, 30, reason: 'what applied before the change');
    expect(state.profile.streakGoalChanges.last.goal, state.profile.streakGoal);
  });

  testWidgets('the weekly target shows just the amount — its label already says weekly', (tester) async {
    await pumpSettings(tester, profile: const Profile(streakGoal: StreakGoal(target: 45)));
    expect(find.text('Weekly target'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);
    expect(find.textContaining('min / week'), findsNothing);
  });

  testWidgets('the data section offers both directions of a backup', (tester) async {
    await pumpSettings(tester);

    // CyberButton renders its label uppercased.
    expect(find.text('EXPORT BACKUP'), findsOneWidget);
    expect(find.text('IMPORT BACKUP'), findsOneWidget);
    expect(find.text('RESET ALL PROGRESS'), findsOneWidget);
  });

  testWidgets('packs are imported, marked as such, and removable — the shipped ones are not', (tester) async {
    final state = await pumpSettings(tester);
    expect(find.text('IMPORT PACK'), findsOneWidget);
    expect(find.text('RELOAD PACKS'), findsNothing, reason: 'it pointed at a folder nobody can reach');
    expect(find.text('IMPORTED'), findsNothing, reason: 'the shipped packs cannot be removed');

    await tester.runAsync(() => state.importMissionPack(jsonEncode({
      'id': 'ghost_line',
      'title': 'GHOST LINE',
      'missions': [
        {'id': 'gl01', 'order': 1, 'codename': 'OP 1', 'title': 'Op 1', 'suggestedGoal': {'type': 'time', 'value': 900}},
      ],
    })));
    await tester.pump();
    expect(find.text('IMPORTED'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove GHOST LINE'));
    await tester.pump();
    expect(find.text('REMOVE GHOST LINE'), findsOneWidget);
    expect(find.textContaining('import it again and you pick up where you were'), findsOneWidget);

    // Removal lists, reads and deletes files. Real file I/O never completes on
    // its own inside the fake-async zone (CLAUDE.md, "Test traps"), and the
    // dialog's answer resumes inside it — so let real time pass and then flush
    // the zone, a few times over, once per step of the chain.
    await tester.tap(find.text('REMOVE'));
    for (var i = 0; i < 20 && state.packs.any((p) => p.id == 'ghost_line'); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.text('IMPORTED'), findsNothing);
    expect(state.packs.map((p) => p.id), isNot(contains('ghost_line')));
  });

  testWidgets('the resume-music repair is offered only when pausing', (tester) async {
    // Ducking never leaves a player stuck, so the setting would be noise.
    await pumpSettings(tester, profile: const Profile(audioInterrupt: AudioInterrupt.duck));
    expect(find.text('Force music back on'), findsNothing);
  });

  group('run music', () {
    Future<void> pick(WidgetTester tester, String option) async {
      await tester.tap(find.text('Run music'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(option).last);
      // The answer resumes in the fake zone and then writes the profile, so the
      // real file I/O needs turns outside it before the screen rebuilds.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('one choice among off, the bed, the library and a folder', (tester) async {
      final state = await pumpSettings(tester);
      expect(find.text('The app plays no music of its own. Yours carries on.'), findsOneWidget);

      await tester.tap(find.text('Run music'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Song library'), findsOneWidget);
      expect(find.text('From a folder'), findsOneWidget);
      expect(find.text('Neon Pursuit'), findsNothing, reason: 'songs are in the library, not here');
      await tester.tap(find.text('Off').last);
      await tester.pump(const Duration(milliseconds: 300));

      await pick(tester, 'Ambient bed');
      expect(state.profile.music, Profile.ambientMusic);
      expect(state.profile.ambientBedOn, isTrue);
      expect(find.text('Music volume'), findsOneWidget);
      expect(find.text('Music follows your effort'), findsNothing);

      await pick(tester, 'Song library');
      expect(state.profile.music, Profile.bestMatchMusic);
      expect(state.profile.generatedMusicOn, isTrue);
      expect(find.text('Music volume'), findsOneWidget);
      expect(find.text('Music follows your effort'), findsOneWidget);
      expect(find.text('Best match, 6 of 6 songs'), findsOneWidget);

      await pick(tester, 'Off');
      expect(state.profile.music, Profile.noMusic);
      expect(find.text('Music volume'), findsNothing);
      expect(find.text('Music follows your effort'), findsNothing);
    });

    testWidgets('someone with no folder yet still reaches the way to find music', (tester) async {
      final state = await pumpSettings(tester);
      await pick(tester, 'From a folder');
      expect(state.musicFolderName, isNull, reason: 'they backed out of the picker');
      expect(state.profile.music, Profile.folderMusic);
      expect(find.text('Choose'), findsOneWidget);
      expect(find.text('Where to find music'), findsOneWidget);
      expect(find.text('Suggest music to run to'), findsOneWidget);
      expect(find.textContaining('No music found'), findsOneWidget);

      await pick(tester, 'Off');
      expect(find.text('Where to find music'), findsNothing);
    });
  });

  group('song library', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<AppState> library(WidgetTester tester, {Profile profile = const Profile(music: Profile.bestMatchMusic)}) async {
      final state = await pumpSettings(tester, profile: profile);
      await tester.tap(find.text('Song library').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      return state;
    }

    testWidgets('lists every song, by whom and how long', (tester) async {
      final state = await library(tester);
      for (final song in state.songs) {
        expect(find.text(song.name), findsOneWidget);
      }
      expect(find.textContaining('by SPRAWL//RUN'), findsNWidgets(state.songs.length));
      expect(find.textContaining('more battery'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(state.songs.length));
    });

    testWidgets('a song switched off is left out of what a run picks', (tester) async {
      final state = await library(tester);
      final row = find.ancestor(of: find.text('Undercity'), matching: find.byType(Row)).first;
      await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
      await settle(tester);
      expect(state.profile.songsLeftOut, ['undercity']);
      const goal = RunGoal(GoalType.time, 1800);
      expect(state.musicQueue(goal: goal, activity: Activity.run), isNot(contains('undercity')));
    });

    testWidgets('the last song in cannot be switched off', (tester) async {
      final state = await pumpSettings(
        tester,
        profile: const Profile(music: Profile.shuffleMusic, songsLeftOut: ['black_ice', 'cold_boot', 'neon_pursuit', 'skyline_breach', 'sodium_rain']),
      );
      await tester.tap(find.text('Song library').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final row = find.ancestor(of: find.text('Undercity'), matching: find.byType(Row)).first;
      final last = tester.widget<Switch>(find.descendant(of: row, matching: find.byType(Switch)));
      expect(last.onChanged, isNull);
      expect(state.profile.songsLeftOut, hasLength(5));
    });

    testWidgets('modes write the same setting the run reads', (tester) async {
      final state = await library(tester);
      await tester.tap(find.text('SHUFFLE'));
      await settle(tester);
      expect(state.profile.music, Profile.shuffleMusic);

      await tester.tap(find.text('ONE SONG'));
      await settle(tester);
      expect(state.profile.generatedMusicOn, isTrue);
      expect(find.byType(Switch), findsNothing, reason: 'a switch means nothing with one song');

      await tester.tap(find.text('Undercity'));
      await settle(tester);
      expect(state.profile.music, 'undercity');
      const goal = RunGoal(GoalType.time, 1800);
      expect(state.musicQueue(goal: goal, activity: Activity.run), ['undercity']);
    });
  });

  testWidgets('the queue for a run follows the choice', (tester) async {
    final state = await pumpSettings(tester);
    const goal = RunGoal(GoalType.time, 1800);
    List<String> queue(String music, {Activity activity = Activity.run}) {
      state.profile = state.profile.copyWith(music: music);
      return state.musicQueue(goal: goal, activity: activity);
    }

    expect(queue(Profile.noMusic), isEmpty);
    expect(queue(Profile.ambientMusic), isEmpty);
    expect(queue('undercity'), ['undercity'], reason: 'a chosen song repeats by itself');
    expect(queue(Profile.shuffleMusic).length, state.songs.length);
    expect(queue(Profile.bestMatchMusic, activity: Activity.walk).first, 'sodium_rain');
    expect(queue('a_song_since_removed').length, state.songs.length, reason: 'falls back to a match, not silence');
    expect(state.songName('undercity'), 'Undercity');
    expect(state.songName('a_song_since_removed'), isNull);
  });

  testWidgets('toggling the resume-music repair persists it', (tester) async {
    final state = await pumpSettings(tester);
    expect(state.profile.resumeMusic, isTrue, reason: 'on by default');

    final row = find.ancestor(of: find.text('Force music back on'), matching: find.byType(Row)).first;
    await tester.tap(find.descendant(of: row, matching: find.byType(Switch)), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));

    // Only the in-memory flip is asserted here: the write behind it is real
    // file I/O, which never completes in a widget test's fake-async zone.
    // persistence_test.dart covers the round trip to disk.
    expect(state.profile.resumeMusic, isFalse);
  });

  group('colours', () {
    tearDown(() => debugNow = null);

    testWidgets('a swatch per theme, and tapping one picks it', (tester) async {
      debugNow = DateTime(2026, 7, 27, 21);
      final state = await pumpSettings(tester);
      expect(state.profile.theme, 'neon', reason: 'the year-round look by default');
      for (final name in ['NEON', 'SYNTHWAVE', 'GLACIER', 'VOLT']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('IMPORT THEME'), findsOneWidget);

      await tester.tap(find.text('GLACIER'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.profile.theme, 'glacier');
      expect(state.palette.cyan, state.theme.palette.cyan);
      expect(find.textContaining('wears its own colours'), findsNothing, reason: 'no season in July');
    });

    testWidgets('the picked theme credits its author', (tester) async {
      debugNow = DateTime(2026, 7, 27, 21);
      await pumpSettings(tester, profile: const Profile(theme: 'glacier'));
      expect(find.text('GLACIER by SPRAWL//RUN'), findsOneWidget);
      expect(find.byTooltip('Remove GLACIER'), findsNothing, reason: 'a shipped theme cannot be removed');
    });

    testWidgets('in season, the picker says the season overrides it', (tester) async {
      debugNow = DateTime(2026, 10, 30, 8);
      await pumpSettings(tester);
      expect(find.textContaining('SAMHAIN PROTOCOL wears its own colours'), findsOneWidget);
    });

    testWidgets('with seasonal events off, nothing overrides it', (tester) async {
      debugNow = DateTime(2026, 10, 30, 8);
      await pumpSettings(tester, profile: const Profile(seasonalEvents: false));
      expect(find.textContaining('wears its own colours'), findsNothing);
    });
  });

  testWidgets('the colophon shows the installed version and build', (tester) async {
    await pumpSettings(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('V9.9.9 · BUILD 999 · OFFLINE'), findsOneWidget);
    expect(find.textContaining('github.com/jbinder/sprawlrun'), findsOneWidget);
  });

  group('signals', () {
    testWidgets('the schedule stays hidden until reminders are switched on', (tester) async {
      await pumpSettings(tester);

      expect(find.text('SIGNALS'), findsOneWidget);
      expect(find.text('Reminders'), findsOneWidget);
      expect(find.text('Days'), findsNothing, reason: 'nothing to schedule while it is off');
      expect(find.text('Time'), findsNothing);
    });

    testWidgets('switching reminders on reveals the days and the time', (tester) async {
      await pumpSettings(
        tester,
        profile: const Profile(signals: SignalSettings(remindersEnabled: true)),
      );

      expect(find.text('Days'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('07:00'), findsOneWidget, reason: 'the default hour');
    });

    testWidgets('the time steps in quarter hours and wraps at midnight', (tester) async {
      final state = await pumpSettings(
        tester,
        profile: const Profile(
          signals: SignalSettings(remindersEnabled: true, minutesFromMidnight: 0),
        ),
      );

      final row = find.ancestor(of: find.text('Time'), matching: find.byType(Row)).first;
      await tester.tap(find.descendant(of: row, matching: find.byIcon(Icons.remove)), warnIfMissed: false);
      await tester.pump();

      expect(
        state.profile.signals.minutesFromMidnight,
        23 * 60 + 45,
        reason: 'a quarter hour before midnight, not a negative time',
      );
    });

    testWidgets('the last remaining day cannot be switched off', (tester) async {
      // "No days at all" is what the Reminders switch is for; a schedule that
      // never fires would just look broken.
      final state = await pumpSettings(
        tester,
        profile: const Profile(
          signals: SignalSettings(remindersEnabled: true, weekdays: {DateTime.wednesday}),
        ),
      );

      final row = find.ancestor(of: find.text('Days'), matching: find.byType(Column)).first;
      await tester.tap(find.descendant(of: row, matching: find.text('W')).first, warnIfMissed: false);
      await tester.pump();

      expect(state.profile.signals.weekdays, {DateTime.wednesday});
    });
  });
}
