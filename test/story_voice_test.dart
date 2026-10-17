import 'package:flutter/widgets.dart' show Locale, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/l10n/l10n.dart';
import 'package:sprawl_run/models/pack_strings.dart';
import 'package:sprawl_run/screens/mission_brief_screen.dart';

import '../tool/screenshots/showcase.dart';
import 'support/fakes.dart';

/// A translated mission on a phone that cannot speak the translation is
/// spoken in English, and the briefing says so before the runner sets off.
/// The screen is pumped with the English delegates; the packs follow the
/// profile's Spanish.
final _english = lookupL(const Locale('en'));

void main() {
  Future<void> brief(WidgetTester tester, {required Set<String> voices, bool voiceEnabled = true}) async {
    // Tall, so the list builds down past the info row.
    final state = await seedShowcase(tester, logicalSize: const Size(360, 3000));
    addTearDown(() => useLocale(const Locale('en')));
    (state.narrator as FakeNarrator).voices = voices;
    await tester.runAsync(
      () => state.updateProfile(state.profile.copyWith(language: 'es', voiceEnabled: voiceEnabled)),
    );
    state.debugTranslatePacks('es', (pack) => {for (final e in packStrings(pack).entries) e.key: 'ES ${e.value.english}'});
    final mission = state.currentMission!.mission;
    expect(mission.translatedInto, 'es');
    await pumpShowcase(tester, MissionBriefScreen(mission: mission), state);
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('without a voice for the language, the briefing says why it will be English', (tester) async {
    await brief(tester, voices: {'en'});
    expect(find.text(_english.storyVoiceMissing), findsOneWidget);
  });

  testWidgets('with one, nothing to say', (tester) async {
    await brief(tester, voices: {'en', 'es'});
    expect(find.text(_english.storyVoiceMissing), findsNothing);
  });

  testWidgets('nor when nothing is spoken at all', (tester) async {
    await brief(tester, voices: {'en'}, voiceEnabled: false);
    expect(find.text(_english.storyVoiceMissing), findsNothing);
  });
}
