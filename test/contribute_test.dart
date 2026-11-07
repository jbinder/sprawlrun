import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/l10n/l10n.dart';
import 'package:sprawl_run/services/project_links.dart';
import 'package:sprawl_run/state/app_state.dart';
import 'package:sprawl_run/theme/cyber_theme.dart';
import 'package:sprawl_run/widgets/contribute_controls.dart';

import 'support/fakes.dart';

void main() {
  group('the links', () {
    String form(String template) => File('.github/ISSUE_TEMPLATE/$template').readAsStringSync();

    test('lead to issue forms that exist, by the ids of their fields', () {
      final bug = ProjectLinks.bug(version: 'v0.8.0 · build 9', language: 'Español');
      final source = form(bug.queryParameters['template']!);
      expect(source, contains('id: version'));
      expect(source, contains('id: language'));
      expect(bug.queryParameters['version'], 'v0.8.0 · build 9');
      form(ProjectLinks.idea.queryParameters['template']!);
    });

    test('leave out what is not known', () {
      expect(ProjectLinks.bug().queryParameters.keys, ['template']);
    });

    test('the music page is where the link says, and every site on it is a real link', () {
      expect(ProjectLinks.findMusic.path, endsWith('/blob/main/docs/FIND_MUSIC.md'));
      final page = File('docs/FIND_MUSIC.md').readAsStringSync();
      expect(RegExp(r'\]\(https://').allMatches(page).length, greaterThan(5));
      expect(page, contains('Settings → Audio → Run music'));
    });

    test('the music form asks little, and has what the page needs', () {
      final source = form(ProjectLinks.suggestMusic.queryParameters['template']!);
      for (final field in ['track', 'artist', 'link', 'why', 'good_for', 'vocals', 'style', 'mood', 'bpm', 'length', 'licence', 'free']) {
        expect(source, contains('id: $field'), reason: field);
      }
      // Each extra required field is someone who does not bother.
      expect('required: true'.allMatches(source).length, 4, reason: 'track, artist, link and the permission');
      final page = File('docs/FIND_MUSIC.md').readAsStringSync();
      expect(page, contains('template=music_suggestion.yml'));
      expect(page, contains('label%3Amusic'), reason: 'the way to the votes');
      expect(File('CONTRIBUTING.md').readAsStringSync(), contains('docs/FIND_MUSIC.md'));
    });

    test('every entry on the music page is complete', () {
      final page = File('docs/FIND_MUSIC.md').readAsStringSync();
      expect(page.indexOf('## Music runners suggest'), lessThan(page.indexOf('## Where to look')), reason: 'the people first');
      final section = RegExp(r'## Music runners suggest\n(.*?)\n## ', dotAll: true).firstMatch(page)!.group(1)!;
      final entries = section.split(RegExp(r'^### ', multiLine: true)).skip(1).toList();
      expect(entries, isNotEmpty, reason: 'or this test checks nothing');
      for (final entry in entries) {
        final name = entry.split('\n').first;
        expect(name, matches(RegExp(r'^\[.+\]\(https://[^)]+\) by .+$')), reason: 'a linked name and an artist: $name');
        expect(name, isNot(matches(RegExp(r'\.(mp3|ogg|flac|wav|zip|m4a|opus)\)'))), reason: 'the page, not the file: $name');
        expect(entry, contains('**Style:**'), reason: name);
        expect(entry, contains('**Licence:**'), reason: name);
        expect(entry, matches(RegExp(r'\*\*Suggested by:\*\* \S')), reason: name);
        expect(entry, matches(RegExp(r'\[👍 vote\]\(https://github\.com/jbinder/sprawlrun/issues/\d+\)')), reason: name);
        for (final bpm in RegExp(r'\*\*BPM:\*\* (\S+)').allMatches(entry)) {
          expect(bpm[1], matches(RegExp(r'^(\d{2,3}(-\d{2,3})?|-)$')), reason: name);
        }
      }
    });

    test('CONTRIBUTING is where the link says', () {
      expect(File(ProjectLinks.contributing.pathSegments.last).existsSync(), isTrue);
      expect(ProjectLinks.contributing.path, endsWith('/blob/main/CONTRIBUTING.md'));
    });
  });

  group('the buttons', () {
    late List<Uri> opened;

    Future<void> pump(WidgetTester tester, {required bool browser}) async {
      final root = tempRoot('contribute');
      addTearDown(() => root.deleteSync(recursive: true));
      final state = AppState(
        profiles: ProfileRepository(root),
        runs: RunRepository(Directory('${root.path}/runs')),
        missions: MissionRepository(externalDir: Directory('${root.path}/packs')),
        narrator: FakeNarrator(),
      );
      await tester.runAsync(state.load);
      opened = [];
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            localizationsDelegates: L.localizationsDelegates,
            theme: buildCyberTheme(),
            home: Scaffold(
              body: ContributeControls(
                open: (url) async {
                  opened.add(url);
                  return browser;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('each opens its own page', (tester) async {
      await pump(tester, browser: true);
      await tester.tap(find.text(l10n.contributeIdea.toUpperCase()));
      await tester.tap(find.text(l10n.contributeHow.toUpperCase()));
      await tester.pump();
      expect(opened, [ProjectLinks.idea, ProjectLinks.contributing]);
    });

    testWidgets('says so when nothing can open it, with the address to copy', (tester) async {
      await pump(tester, browser: false);
      await tester.tap(find.text(l10n.contributeHow.toUpperCase()));
      await tester.pump();
      expect(find.textContaining('CONTRIBUTING.md'), findsOneWidget);
    });
  });
}
