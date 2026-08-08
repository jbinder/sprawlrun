import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/profile.dart';
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
}
