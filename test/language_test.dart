import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sprawl_run/app.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/l10n/l10n.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/services/run_engine.dart';
import 'package:sprawl_run/state/app_state.dart';
import 'package:sprawl_run/util/format.dart';

import 'support/fakes.dart';

void main() {
  group('which language is shown', () {
    test('the runner\'s choice, when the app has it', () {
      expect(resolveLocale('es', const [Locale('en', 'US')]), const Locale('es'));
    });

    test('otherwise the first phone language the app has, by language alone', () {
      expect(resolveLocale(null, const [Locale('de'), Locale('es', 'MX'), Locale('en')]), const Locale('es'));
      expect(resolveLocale('xx', const [Locale('es', 'AR')]), const Locale('es'), reason: 'a choice no longer shipped');
    });

    test('otherwise English', () {
      expect(resolveLocale(null, const [Locale('de'), Locale('ja')]), const Locale('en'));
    });
  });

  test('a chosen language is stored, and an empty one means the phone\'s', () {
    final chosen = Profile.fromJson(const Profile(language: 'es').toJson());
    expect(chosen.languageCode, 'es');
    expect(Profile.fromJson(chosen.copyWith(language: '').toJson()).languageCode, isNull);
    expect(const Profile().toJson(), isNot(contains('language')));
  });

  testWidgets('picking Spanish changes the screen and everything off it', (tester) async {
    final root = tempRoot('language');
    addTearDown(() => root.deleteSync(recursive: true));
    final profiles = ProfileRepository(root);
    final state = AppState(
      profiles: profiles,
      runs: RunRepository(Directory('${root.path}/runs')),
      missions: MissionRepository(externalDir: Directory('${root.path}/packs')),
      narrator: FakeNarrator(),
    );
    await tester.runAsync(() async {
      await profiles.save(const Profile(language: 'es'));
      await state.load();
    });
    addTearDown(() => useLocale(const Locale('en')));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider(create: (_) => RunEngine(narrator: FakeNarrator(), location: FakeLocation())),
        ],
        child: const SprawlRunApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('MURO'), findsOneWidget, reason: 'the navigation, through L.of');
    expect(Fmt.weekday(DateTime(2026, 10, 12)), 'LUN', reason: 'and code with no context, through l10n');
    expect(state.week.label, 'ÚLTIMOS 7 DÍAS', reason: 'figures derived before the first frame');

    // Back to the phone's language, which the harness reports as English.
    await tester.runAsync(() => state.updateProfile(state.profile.copyWith(language: '')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('WALL'), findsOneWidget);
    expect(Fmt.weekday(DateTime(2026, 10, 12)), 'MON');
  });

  testWidgets('a runner following the phone follows it when it changes', (tester) async {
    final root = tempRoot('language');
    addTearDown(() => root.deleteSync(recursive: true));
    var phone = const [Locale('en', 'US')];
    final state = AppState(
      systemLocales: () => phone,
      profiles: ProfileRepository(root),
      runs: RunRepository(Directory('${root.path}/runs')),
      missions: MissionRepository(externalDir: Directory('${root.path}/packs')),
      narrator: FakeNarrator(),
    );
    await tester.runAsync(state.load);
    addTearDown(() => useLocale(const Locale('en')));
    expect(state.locale, const Locale('en'));

    phone = const [Locale('es', 'ES')];
    await tester.runAsync(state.systemLocalesChanged);
    expect(state.locale, const Locale('es'));
    expect(l10n.navWall, 'MURO');
  });
}
