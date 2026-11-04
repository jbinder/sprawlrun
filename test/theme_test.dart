import 'dart:convert';
import 'dart:io';
import 'package:flutter/painting.dart' show Color, HSLColor, HSVColor;

import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/data/theme_repository.dart';
import 'package:sprawl_run/l10n/l10n.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/state/app_state.dart';
import 'package:sprawl_run/theme/colour_theme.dart';
import 'package:sprawl_run/theme/cyber_palette.dart';
import 'package:sprawl_run/theme/theme_draft.dart';

import 'support/fakes.dart';

/// A valid theme file, with [colours] and [extra] laid over GLACIER's.
String themeJson({String id = 'mine', String name = 'MINE', Map<String, Object?> colours = const {}, Map<String, Object?> extra = const {}}) {
  final base = jsonDecode(File('assets/themes/glacier.json').readAsStringSync()) as Map<String, dynamic>;
  return jsonEncode({
    ...base,
    'id': id,
    'name': name,
    'colours': {...base['colours'] as Map, ...colours}..removeWhere((_, v) => v == null),
    ...extra,
  });
}

Matcher refusedWith(String text) =>
    throwsA(isA<ThemeFormatException>().having((e) => e.message, 'message', contains(text)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the shipped themes', () {
    final files = Directory('assets/themes').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();

    test('are there', () {
      expect(files.map((f) => f.uri.pathSegments.last), containsAll(['synth.json', 'glacier.json', 'volt.json']));
    });

    // The house rules for a contributed theme, beyond what an import checks.
    for (final file in files) {
      final fileName = file.uri.pathSegments.last;
      test('$fileName parses, is named for its id and keeps success green', () {
        final theme = ColourTheme.parse(file.readAsStringSync());
        expect('${theme.id}.json', fileName);
        expect(theme.author, isNotNull, reason: 'a contributed theme credits its author');
        final hue = HSVColor.fromColor(theme.palette.green).hue;
        expect(hue, inInclusiveRange(80, 165), reason: 'a met goal should look met in every theme');
        final shipped = {for (final l in L.supportedLocales) l.languageCode};
        expect(shipped, containsAll(theme.names.keys), reason: 'a name in a language the app does not speak');
      });
    }

    test('have ids and names of their own', () {
      final themes = [ColourTheme.neon, for (final f in files) ColourTheme.parse(f.readAsStringSync())];
      expect(themes.map((t) => t.id).toSet(), hasLength(themes.length));
      expect(themes.map((t) => t.name).toSet(), hasLength(themes.length));
    });

    test('NEON passes the rules it sets for everyone else', () {
      expect(ColourTheme.legibilityProblem(CyPalette.standard), isNull);
    });
  });

  group('a theme file', () {
    test('reads its roles into the palette', () {
      final theme = ColourTheme.parse(themeJson(colours: {'primary': '#7FB0FF'}));
      expect(theme.palette.cyan, const Color(0xFF7FB0FF));
      expect(theme.nameIn('es'), 'GLACIAR', reason: 'the names block carries over from glacier.json');
      expect(theme.nameIn('fr'), 'MINE');
    });

    test('is refused when it is not one', () {
      expect(() => ColourTheme.parse('nope'), refusedWith('not JSON'));
      expect(() => ColourTheme.parse('{"id": "x", "name": "X"}'), refusedWith('not a colour theme'));
      expect(() => ColourTheme.parse(themeJson(id: '../profile')), refusedWith('id may only use'));
      expect(() => ColourTheme.parse(themeJson(name: 'A NAME FAR TOO LONG TO FIT')), refusedWith('1 to 16'));
      expect(() => ColourTheme.parse(themeJson(extra: {'names': {'es': 3}})), refusedWith('"names" block'));
    });

    test('names the colour that is wrong', () {
      expect(() => ColourTheme.parse(themeJson(colours: {'primery': '#FFFFFF'})), refusedWith('"primery" is not a colour'));
      expect(() => ColourTheme.parse(themeJson(colours: {'story': null})), refusedWith('does not set "story"'));
      expect(() => ColourTheme.parse(themeJson(colours: {'hostile': 'red'})), refusedWith('"hostile" is red'));
      expect(() => ColourTheme.parse(themeJson(colours: {'hostile': '#FF000080'})), refusedWith('"hostile" is'));
    });

    test('is refused when it could not be read', () {
      expect(() => ColourTheme.parse(themeJson(colours: {'text': '#202838'})), refusedWith('"text" is too close'));
      expect(() => ColourTheme.parse(themeJson(colours: {'textDim': '#1A2433'})), refusedWith('"textDim"'));
      expect(() => ColourTheme.parse(themeJson(colours: {'hostile': '#6EA8FF'})), refusedWith('"primary" and "hostile"'));
    });
  });

  group('importing', () {
    late Directory root;
    late ThemeRepository repo;

    setUp(() async {
      root = tempRoot('themes');
      repo = ThemeRepository(importDir: Directory('${root.path}/themes'));
      await repo.loadThemes();
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('offers NEON first, then the shipped themes by name', () async {
      final names = (await repo.loadThemes()).map((t) => t.name).toList();
      expect(names.take(4), ['NEON', 'GLACIER', 'SYNTHWAVE', 'VOLT']);
    });

    test('adds a theme after the shipped ones, replaces it on a re-import and removes it', () async {
      await repo.importTheme(themeJson());
      expect((await repo.loadThemes()).last.id, 'mine');
      expect(repo.importedIds, {'mine'});

      await repo.importTheme(themeJson(name: 'MINE II'));
      final themes = await repo.loadThemes();
      expect(themes.where((t) => t.id == 'mine').single.name, 'MINE II');

      await repo.removeTheme('mine');
      expect((await repo.loadThemes()).map((t) => t.id), isNot(contains('mine')));
      expect(repo.importedIds, isEmpty);
    });

    test('will not take a built-in id', () async {
      expect(() => repo.importTheme(themeJson(id: 'neon')), refusedWith('already uses the id "neon"'));
      expect(() => repo.importTheme(themeJson(id: 'glacier')), refusedWith('already uses the id "glacier"'));
    });

    test('reports a broken file instead of failing the rest', () async {
      await repo.importTheme(themeJson());
      File('${root.path}/themes/broken.json').writeAsStringSync('{');
      final themes = await repo.loadThemes();
      expect(themes.map((t) => t.id), contains('mine'));
      expect(repo.loadErrors.single, startsWith('broken.json'));
    });
  });

  group('the editor\'s draft', () {
    late ColourTheme glacier;
    setUp(() => glacier = ColourTheme.parse(File('assets/themes/glacier.json').readAsStringSync()));

    test('a main colour takes its shades along, as far from it as they were', () {
      final draft = ThemeDraft(base: glacier.palette, name: 'MINE');
      const red = Color(0xFF3A0A0A);
      draft.set('background', red);
      expect(draft.colours['background'], red);
      for (final shade in ThemeDraft.shadesOf['background']!) {
        final was = HSLColor.fromColor(glacier.palette.v0id), wasShade = HSLColor.fromColor(ColourTheme.rolesOf(glacier.palette)[shade]!);
        final now = HSLColor.fromColor(red), nowShade = HSLColor.fromColor(draft.colours[shade]!);
        expect(nowShade.lightness - now.lightness, closeTo(wasShade.lightness - was.lightness, 0.01), reason: shade);
      }
      expect(draft.colours['text'], glacier.palette.ink, reason: 'not a shade of the background');
      expect(draft.changed, isTrue);
    });

    test('any other colour is set on its own', () {
      final draft = ThemeDraft(base: glacier.palette, name: 'MINE')..set('panel', const Color(0xFF101820));
      expect(draft.colours['panel'], const Color(0xFF101820));
      expect(draft.colours['background'], glacier.palette.v0id);
    });

    test('says which role cannot be read, and by how much', () {
      final draft = ThemeDraft(base: glacier.palette, name: 'MINE');
      expect(draft.issue, isNull);
      draft.set('text', glacier.palette.panelHi);
      final issue = draft.issue;
      expect(issue, isA<LowContrast>().having((i) => i.role, 'role', 'text').having((i) => i.needed, 'needed', 7));
      expect((issue as LowContrast).ratio, lessThan(2));

      draft.set('text', glacier.palette.ink);
      draft.set('hostile', glacier.palette.cyan);
      expect(draft.issue, isA<SameColour>().having((i) => i.second, 'second', 'hostile'));
    });

    test('a theme written out reads back as the same theme', () {
      final back = ColourTheme.parse(glacier.toJson());
      expect(back.id, glacier.id);
      expect(back.author, glacier.author);
      expect(ColourTheme.rolesOf(back.palette), ColourTheme.rolesOf(glacier.palette));
    });
  });

  group('saving from the editor', () {
    late Directory root;
    late AppState state;

    setUp(() async {
      root = tempRoot('theme-editor');
      state = AppState(
        profiles: ProfileRepository(root),
        runs: RunRepository(Directory('${root.path}/runs')),
        missions: MissionRepository(externalDir: Directory('${root.path}/packs')),
        narrator: FakeNarrator(),
      );
      await state.load();
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('a copy is saved as a new theme of its own and put on', () async {
      final volt = state.themes.singleWhere((t) => t.id == 'volt');
      final first = await state.saveThemeDraft(ThemeDraft(base: volt.palette, name: 'MY VOLT')..set('primary', const Color(0xFFFF9900)));
      final second = await state.saveThemeDraft(ThemeDraft(base: volt.palette, name: 'AGAIN'));
      expect((first.id, second.id), ('custom-1', 'custom-2'));
      expect(state.profile.theme, 'custom-2');
      expect(state.themeRepository.importedIds, {'custom-1', 'custom-2'});
      expect(state.themes.singleWhere((t) => t.id == 'custom-1').palette.cyan, const Color(0xFFFF9900));
      expect(state.themes.singleWhere((t) => t.id == 'volt').palette.cyan, isNot(const Color(0xFFFF9900)), reason: 'the original is untouched');
    });

    test('changing the runner\'s own theme saves over it', () async {
      final volt = state.themes.singleWhere((t) => t.id == 'volt');
      final mine = await state.saveThemeDraft(ThemeDraft(base: volt.palette, name: 'MINE'));
      await state.saveThemeDraft(ThemeDraft.of(mine)..name = 'MINE II');
      expect(state.themeRepository.importedIds, {'custom-1'});
      expect(state.theme.name, 'MINE II');
    });
  });

  group('the profile', () {
    test('wears NEON when it predates themes or names one that is gone', () {
      expect(Profile.fromJson(const {'callsign': 'CASE'}).theme, 'neon');
      expect(Profile.fromJson(const Profile(theme: 'volt').toJson()).theme, 'volt');
    });
  });
}
