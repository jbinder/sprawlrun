import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sprawl_run/screens/settings_screen.dart';
import 'package:sprawl_run/state/app_state.dart';
import 'package:sprawl_run/theme/cyber_theme.dart';

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
      child: MaterialApp(theme: buildCyberTheme(), home: const SettingsScreen()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return state;
}

void main() {
  testWidgets('the data section offers both directions of a backup', (tester) async {
    await pumpSettings(tester);

    // CyberButton renders its label uppercased.
    expect(find.text('EXPORT BACKUP'), findsOneWidget);
    expect(find.text('IMPORT BACKUP'), findsOneWidget);
    expect(find.text('RESET ALL PROGRESS'), findsOneWidget);
  });

  testWidgets('the resume-music repair is offered only when pausing', (tester) async {
    // Ducking never leaves a player stuck, so the setting would be noise.
    await pumpSettings(tester, profile: const Profile(audioInterrupt: AudioInterrupt.duck));
    expect(find.text('Force music back on'), findsNothing);
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
