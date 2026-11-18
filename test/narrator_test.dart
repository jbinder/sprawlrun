import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/models/mission.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/services/music_resume.dart';
import 'package:sprawl_run/services/narrator.dart';

void main() {
  group('voices handed to characters', () {
    Map<String, String> voice(String name, {String locale = 'en-US', bool network = false, String features = ''}) => {
      'name': name,
      'locale': locale,
      'network_required': network ? '1' : '0',
      'features': features,
    };

    test('only English ones that work offline and are installed', () {
      final usable = AudioNarrator.usableVoices([
        voice('en-us-x-sfg-local'),
        voice('en-us-x-sfg-network', network: true),
        voice('en-gb-x-rjs-local', locale: 'en-GB', features: 'networkTimeoutMs\tnotInstalled'),
        voice('de-de-x-nfh-local', locale: 'de-DE'),
        voice('en-au-x-aub-local', locale: 'en-AU', features: 'networkTimeoutMs\tnetworkRetriesCount'),
      ]).map((v) => v['name']);
      expect(usable, ['en-us-x-sfg-local', 'en-au-x-aub-local']);
    });
  });

  group('how long a line may take', () {
    test('outlasts the line at the speech rate it is spoken at', () {
      const line =
          'Seven years on file under Ossuary Row, in case anybody wants to sue you. Then the purge takes you. Every October.';
      // Roughly 14 characters a second at the engine's normal rate of 0.5.
      expect(AudioNarrator.speechBudget(line, 0.5), greaterThan(Duration(milliseconds: line.length * 1000 ~/ 14)));
      // The slowest voice at a slow setting still gets its time.
      expect(
        AudioNarrator.speechBudget(line, 0.15),
        greaterThan(Duration(milliseconds: (line.length * 1000 / 14 * 0.5 / 0.15).round())),
      );
    });

    test('is not open-ended', () {
      expect(AudioNarrator.speechBudget('x' * 180, 0.5), lessThan(const Duration(seconds: 30)));
    });
  });

  group('a translated story line', () {
    const line = StoryLine(speaker: 'KESTREL', text: 'Canal limpio.', language: 'es', original: 'Channel is clean.');

    test('is spoken as it is shown when the phone has a voice for it', () {
      expect(AudioNarrator.spokenForm(line, hasVoiceFor: (_) => true), same(line));
    });

    test('is spoken in its English, by the same speaker, when it has none', () {
      final spoken = AudioNarrator.spokenForm(line, hasVoiceFor: (l) => l == 'en');
      expect((spoken.speaker, spoken.text, spoken.language), ('KESTREL', 'Channel is clean.', null));
    });

    test('but a line the app wrote has no English to fall back to', () {
      const readout = StoryLine(speaker: 'SYSTEM', text: 'Kilómetro dos.', language: 'es');
      expect(AudioNarrator.spokenForm(readout, hasVoiceFor: (_) => false), same(readout));
    });
  });

  group('a run that is stopped', () {
    // No speech engine in the harness, so each line is held for its muted
    // length (at least 900 ms) — long enough to stop the beat mid-way.
    Future<(AudioNarrator, List<String?>)> narrator() async {
      final subject = AudioNarrator(
        resumeGuard: MusicResumeGuard(isMusicActive: () async => false, sendPlay: () async {}),
      );
      await subject.init(const Profile(sfxVolume: 0));
      final heard = <String?>[];
      subject.events.listen((e) => heard.add(e.line?.text));
      return (subject, heard);
    }

    const beat = [
      StoryLine(speaker: 'KESTREL', text: 'One.'),
      StoryLine(speaker: 'KESTREL', text: 'Two.'),
      StoryLine(speaker: 'KESTREL', text: 'Three.'),
    ];

    testWidgets('says nothing more of the beat in progress', (tester) async {
      await tester.runAsync(() async {
        final (subject, heard) = await narrator();
        final speaking = subject.speakBeat(beat);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(heard, ['One.']);

        await subject.stopAll();
        await speaking.timeout(const Duration(seconds: 5));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(heard, ['One.', null]);
      });
    });

    testWidgets('never starts a beat that was waiting behind it', (tester) async {
      await tester.runAsync(() async {
        final (subject, heard) = await narrator();
        final first = subject.speakBeat(beat.sublist(0, 1));
        final second = subject.speakBeat(const [StoryLine(speaker: 'HALCYON', text: 'Later.')]);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        await subject.stopAll();
        await Future.wait([first, second]).timeout(const Duration(seconds: 5));
        expect(heard, isNot(contains('Later.')));
      });
    });

    testWidgets('a beat of the next run is spoken in full', (tester) async {
      await tester.runAsync(() async {
        final (subject, heard) = await narrator();
        unawaited(subject.speakBeat(beat));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await subject.stopAll();

        heard.clear();
        await subject.speakBeat(beat.sublist(0, 2)).timeout(const Duration(seconds: 5));
        expect(heard, ['One.', 'Two.', null]);
      });
    });
  });
}
