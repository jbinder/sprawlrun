import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:sprawl_run/app.dart';
import 'package:sprawl_run/data/active_run_store.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/l10n/generated/l10n_en.dart';
import 'package:sprawl_run/l10n/l10n.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/release_notes.dart';
import 'package:sprawl_run/screens/settings_screen.dart';
import 'package:sprawl_run/services/run_engine.dart';
import 'package:sprawl_run/state/app_state.dart';
import 'package:sprawl_run/theme/cyber_theme.dart';

import 'support/fakes.dart';

/// After an update the runner is told once what it brought — every version
/// they skipped included — and never over something else on screen.
void main() {
  final current = ReleaseNotes.all.first;

  group('which notes are due', () {
    ReleaseNote note(String v) => ReleaseNote(version: v, name: (_) => v, items: (_) => const []);
    final catalogue = [note('0.12.0'), note('0.11.0'), note('0.10.0'), note('0.9.0')];
    List<String> due(String? seen, String now) =>
        [for (final n in ReleaseNotes.since(seen, now, from: catalogue)) n.version];

    test('none once this version has been seen', () => expect(due('0.12.0', '0.12.0'), isEmpty));

    test('every skipped version, newest first', () {
      expect(due('0.9.0', '0.12.0'), ['0.12.0', '0.11.0', '0.10.0']);
    });

    test('nothing newer than what is installed', () => expect(due('0.9.0', '0.11.0'), ['0.11.0', '0.10.0']));

    test('an installation from before release notes hears about this version only', () {
      expect(due(null, '0.12.0'), ['0.12.0']);
    });

    test('a version without notes, such as a patch release, adds none', () {
      expect(due('0.12.0', '0.12.1'), isEmpty);
      expect(due('0.11.0', '0.12.1'), ['0.12.0']);
    });

    test('a long absence lists the newest few; GitHub has the rest', () {
      final many = [for (var minor = 30; minor >= 10; minor--) note('0.$minor.0')];
      final shown = ReleaseNotes.since('0.10.0', '0.30.0', from: many);
      expect(shown, hasLength(ReleaseNotes.shownAtMost));
      expect(shown.first.version, '0.30.0');
    });

    test('versions compare as numbers, not text', () {
      expect(ReleaseNotes.compareVersions('0.10.0', '0.9.0'), 1);
      expect(ReleaseNotes.compareVersions('1.0.0', '0.99.9'), 1);
      expect(ReleaseNotes.compareVersions('0.9.0+113', '0.9.0'), 0);
    });

    test('the catalogue is newest first, with a name and something to say', () {
      final l = LEn();
      for (var i = 0; i < ReleaseNotes.all.length; i++) {
        final n = ReleaseNotes.all[i];
        if (i > 0) expect(ReleaseNotes.compareVersions(ReleaseNotes.all[i - 1].version, n.version), 1);
        expect(n.name(l), isNotEmpty);
        expect(n.items(l), isNotEmpty);
      }
    });

    test('a feature release cannot ship without notes', () {
      final version = RegExp(r'^version:\s*(\d+)\.(\d+)', multiLine: true)
          .firstMatch(File('pubspec.yaml').readAsStringSync())!;
      final shipped = '${version.group(1)}.${version.group(2)}.0';
      expect(ReleaseNotes.compareVersions(current.version, shipped), greaterThanOrEqualTo(0),
          reason: 'add $shipped at the top of ReleaseNotes.all');
    });
  });

  group('on launch', () {
    late Directory root;
    setUp(() => root = tempRoot('release_notes'));
    tearDown(() => root.deleteSync(recursive: true));

    Future<AppState> boot(
      WidgetTester tester, {
      Profile? profile,
      bool withRuns = true,
      ActiveRunSnapshot? interrupted,
    }) async {
      final profiles = ProfileRepository(root);
      final runs = RunRepository(Directory('${root.path}/runs'));
      final state = AppState(
        profiles: profiles,
        runs: runs,
        missions: MissionRepository(externalDir: Directory('${root.path}/packs')),
        narrator: FakeNarrator(),
        appVersion: () async => current.version,
      );
      await tester.runAsync(() async {
        if (profile != null) await profiles.save(profile);
        if (withRuns) await runs.save(run(at: DateTime(2026, 10, 4, 9), meters: 5000, seconds: 1800));
        if (interrupted != null) await ActiveRunStore(root).save(interrupted);
        await state.load();
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
            ChangeNotifierProvider(create: (_) => RunEngine(narrator: FakeNarrator(), location: FakeLocation())),
          ],
          child: MaterialApp(
            localizationsDelegates: L.localizationsDelegates,
            theme: buildCyberTheme(),
            navigatorObservers: [appRouteObserver],
            home: const HomeShell(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return state;
    }

    Future<void> close(WidgetTester tester) async {
      await tester.tap(find.text(LEn().whatsNewClose));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Marking it seen writes the profile.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }

    final title = find.text(LEn().whatsNewTitle);

    testWidgets('an existing installation is told once, and not again', (tester) async {
      final state = await boot(tester, profile: const Profile());
      expect(title, findsOneWidget);
      expect(find.text(current.items(LEn()).first), findsOneWidget);

      await close(tester);
      expect(title, findsNothing);
      expect(state.profile.releaseNotesSeen, current.version);
      expect(state.releaseNotesDue, isEmpty);
    });

    testWidgets('a fresh installation has nothing to catch up on', (tester) async {
      final state = await boot(tester, withRuns: false);
      expect(title, findsNothing);
      expect(state.profile.releaseNotesSeen, current.version);
    });

    testWidgets('a killed run is decided first', (tester) async {
      final state = await boot(
        tester,
        profile: const Profile(),
        interrupted: ActiveRunSnapshot(record: run(at: DateTime(2026, 10, 5, 9), meters: 1200, seconds: 600), codexHeard: const []),
      );
      expect(title, findsNothing);

      await tester.runAsync(state.discardInterruptedRun);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(title, findsOneWidget);
    });

    testWidgets('it waits while another screen is on top, and shows when the home screen is back',
        (tester) async {
      final state = AppState(
        profiles: ProfileRepository(root),
        runs: RunRepository(Directory('${root.path}/runs')),
        missions: MissionRepository(externalDir: Directory('${root.path}/packs')),
        narrator: FakeNarrator(),
        appVersion: () async => current.version,
      );
      await tester.runAsync(() async {
        await ProfileRepository(root).save(const Profile());
        await RunRepository(Directory('${root.path}/runs')).save(run(at: DateTime(2026, 10, 4, 9), meters: 5000, seconds: 1800));
      });
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
            ChangeNotifierProvider(create: (_) => RunEngine(narrator: FakeNarrator(), location: FakeLocation())),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            localizationsDelegates: L.localizationsDelegates,
            theme: buildCyberTheme(),
            navigatorObservers: [appRouteObserver],
            home: const HomeShell(),
          ),
        ),
      );
      // Something else — as a tapped notification's timeline would be — is
      // pushed before the launch settles.
      navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('ON TOP'))));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(state.load);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('ON TOP'), findsOneWidget);
      expect(title, findsNothing);

      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(title, findsOneWidget);
    });
  });

  testWidgets('Settings names the version, and tapping it shows its notes again', (tester) async {
    final root = tempRoot('release_notes_settings');
    addTearDown(() => root.deleteSync(recursive: true));
    tester.view.physicalSize = const Size(1200, 24000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    PackageInfo.setMockInitialValues(
      appName: 'SPRAWL//RUN',
      packageName: 'io.github.jbinder.sprawlrun',
      version: current.version,
      buildNumber: '113',
      buildSignature: '',
    );
    final state = AppState(
      profiles: ProfileRepository(root),
      runs: RunRepository(Directory('${root.path}/runs')),
      missions: MissionRepository(externalDir: Directory('${root.path}/packs')),
      narrator: FakeNarrator(),
    );
    await tester.runAsync(state.load);
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider.value(value: state)],
        child: MaterialApp(
          localizationsDelegates: L.localizationsDelegates,
          theme: buildCyberTheme(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    final l = LEn();
    expect(find.text(current.name(l).toUpperCase()), findsOneWidget);
    await tester.tap(find.text(l.whatsNewHint));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l.whatsNewTitle), findsOneWidget);
    expect(find.text(l.whatsNewRelease(current.version, current.name(l)).toUpperCase()), findsOneWidget);
  });
}
