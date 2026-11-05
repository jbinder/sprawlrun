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
