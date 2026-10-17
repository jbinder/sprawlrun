import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/l10n/l10n.dart';
import 'package:sprawl_run/models/mission.dart';
import 'package:sprawl_run/models/pack_strings.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/signal_log.dart';
import 'package:sprawl_run/services/signal_library.dart';
import 'package:sprawl_run/state/app_state.dart';

import '../tool/pack_strings.dart';
import 'support/fakes.dart';
import 'support/pseudo.dart';

/// The contract for story translations: what a translator is offered, how a
/// translation is applied, and that every shipped one fits.
void main() {
  MissionPack load(String path) => MissionPack.fromJson(jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>);
  final bundled = {for (final path in MissionRepository.bundledPacks) path: load(path)};
  final prime = bundled['assets/missions/sprawl_prime.json']!;

  /// Every string of [pack] in the pseudo-language.
  Map<String, String> everything(MissionPack pack) => {
    for (final MapEntry(:key, :value) in packStrings(pack).entries) key: pseudo(value.english),
  };

  test('each bundled pack\'s English source is current', () {
    for (final MapEntry(key: path, value: pack) in bundled.entries) {
      final file = File(MissionRepository.translationPath(path, 'en'));
      expect(file.existsSync(), isTrue, reason: '${file.path} is missing — run: fvm dart run tool/pack_strings.dart');
      expect(
        file.readAsStringSync(),
        packSourceArb(pack),
        reason: '${file.path} is stale — run: fvm dart run tool/pack_strings.dart',
      );
    }
  });

  test('names are never offered, and everything else is', () {
    final translated = localizePack(prime, 'xx', everything(prime));
    expect(translated.title, prime.title);
    expect(translated.tagline, isNot(prime.tagline));
    for (final (i, m) in translated.missions.indexed) {
      final english = prime.missions[i];
      expect((m.codename, m.location), (english.codename, english.location));
      expect([m.title, m.brief, m.objective, m.debrief], everyElement(startsWith('[')));
      for (final (j, b) in m.beats.indexed) {
        final lines = [...b.lines, ...?b.chase?.escapedLines, ...?b.chase?.caughtLines];
        final englishLines = [...english.beats[j].lines, ...?english.beats[j].chase?.escapedLines, ...?english.beats[j].chase?.caughtLines];
        expect(lines.map((l) => l.speaker), englishLines.map((l) => l.speaker));
        expect(lines.map((l) => l.text), everyElement(startsWith('[')));
        expect(b.chase?.pursuer, english.beats[j].chase?.pursuer);
        if (english.beats[j].headline != null) expect(b.headline, startsWith('['));
      }
      for (final c in m.codex) {
        expect([c.title, c.category, c.body], everyElement(startsWith('[')));
      }
    }
  });

  test('a translated line knows its language and its English', () {
    final translated = localizePack(prime, 'es', everything(prime));
    final line = translated.missions.first.beats.first.lines.first;
    final english = prime.missions.first.beats.first.lines.first;
    expect(line.language, 'es');
    expect(line.original, english.text);
    expect(english.language, isNull);
  });

  test('a mission is translated whole or not at all', () {
    final strings = everything(prime);
    final first = prime.missions.first;
    final missing = '${first.id}.${first.beats.last.id}.0';
    expect(strings.remove(missing), isNotNull);

    final translated = localizePack(prime, 'es', strings);
    expect(translatedMissions(prime, strings), isNot(contains(first.id)));
    expect(translated.missions.first.brief, first.brief, reason: 'one line short, so all of it stays English');
    expect(translated.missions.first.beats.first.lines.first.language, isNull);
    expect(translated.missions[1].brief, startsWith('['), reason: 'the next mission is complete');
  });

  test('the pack\'s own text is translated string by string', () {
    final translated = localizePack(prime, 'es', {'tagline': 'Diez carreras.'});
    expect(translated.tagline, 'Diez carreras.');
    expect(translated.missions.first.brief, prime.missions.first.brief);
  });

  test('a codex category is offered once, however many entries share it', () {
    final keys = packStrings(prime).keys.where((k) => k.startsWith('category.')).toList();
    final categories = {for (final m in prime.missions) for (final c in m.codex) c.category};
    expect(keys, hasLength(categories.length));
  });

  test('a translated signal keeps its English reference, so THE WIRE still finds it', () {
    final translated = localizePack(prime, 'es', everything(prime));
    final english = prime.signals.ambient.first;
    final shown = translated.signals.ambient.first;
    expect(shown.text, pseudo(english.text));
    expect(shown.ref, signalRef(english.text));

    final entry = SignalLogEntry(at: DateTime(2026, 10, 1), kind: SignalKind.ambient, from: english.from, ref: english.ref);
    expect(SignalLibrary.fromPacks([translated]).resolve(entry)!.text, pseudo(english.text));
    expect(SignalLibrary.fromPacks([prime]).resolve(entry)!.text, english.text);
  });

  test('an outdated translation still shows, since keys are paths', () {
    final strings = everything(prime);
    final json = jsonDecode(File('assets/missions/sprawl_prime.json').readAsStringSync()) as Map<String, dynamic>;
    ((json['missions'] as List).first as Map)['brief'] = 'A typo fixed in the English.';
    final reworded = MissionPack.fromJson(json);
    expect(
      localizePack(reworded, 'es', strings).missions.first.brief,
      strings['${prime.missions.first.id}.brief'],
      reason: 'the translation made from the old English, rather than English',
    );
  });

  group('every shipped translation', () {
    final dir = Directory('assets/missions/l10n');
    for (final MapEntry(key: path, value: pack) in bundled.entries) {
      final name = path.split('/').last.replaceAll('.json', '');
      final strings = packStrings(pack);
      for (final file in dir.listSync().whereType<File>()) {
        final match = RegExp('^${name}_(\\w+)\\.arb\$').firstMatch(file.uri.pathSegments.last);
        if (match == null || match[1] == 'en') continue;
        test('${file.uri.pathSegments.last} fits its pack', () {
          final translation = MissionRepository.parseTranslation(file.readAsStringSync());
          for (final MapEntry(:key, :value) in translation.entries) {
            expect(strings, contains(key), reason: '$key is not in $name');
            final limit = key.contains('.signals.debrief.') || key.startsWith('signals.debrief.')
                ? 90
                : key.contains('signals.')
                ? 180
                : strings[key]!.note.contains('Spoken aloud')
                ? 260
                : null;
            if (limit != null) expect(value.length, lessThanOrEqualTo(limit), reason: '$key is too long');
          }
        });
      }
    }
  });

  testWidgets('the repository attaches a bundled translation, and the app shows it in that language', (tester) async {
    final root = tempRoot('pack_strings');
    addTearDown(() => root.deleteSync(recursive: true));
    final bundle = _Bundle({
      MissionRepository.translationPath('assets/missions/sprawl_prime.json', 'es'): jsonEncode({
        '@@locale': 'es',
        'tagline': 'Diez carreras.',
      }),
    });
    final profiles = ProfileRepository(root);
    final state = AppState(
      profiles: profiles,
      runs: RunRepository(Directory('${root.path}/runs')),
      missions: MissionRepository(externalDir: Directory('${root.path}/packs'), bundle: bundle),
      narrator: FakeNarrator(),
    );
    addTearDown(() => useLocale(const Locale('en')));
    await tester.runAsync(() async {
      await profiles.save(const Profile(language: 'es'));
      await state.load();
    });
    expect(state.missions.loadErrors, isEmpty);
    String tagline() => state.packs.firstWhere((p) => p.id == prime.id).tagline;
    expect(tagline(), 'Diez carreras.');

    await tester.runAsync(() => state.updateProfile(state.profile.copyWith(language: 'en')));
    expect(tagline(), prime.tagline);
  });
}

/// The real assets, plus [extra] files in place of or beside them.
class _Bundle extends CachingAssetBundle {
  _Bundle(this.extra);

  final Map<String, String> extra;

  @override
  Future<ByteData> load(String key) async {
    if (extra[key] case final text?) return ByteData.sublistView(utf8.encode(text));
    if (key == 'AssetManifest.bin') {
      // Lists the extra files too, since the repository only loads what the
      // manifest says is there.
      const codec = StandardMessageCodec();
      final manifest = Map<Object?, Object?>.from(codec.decodeMessage(await rootBundle.load(key)) as Map);
      for (final path in extra.keys) {
        manifest[path] = [
          {'asset': path},
        ];
      }
      return codec.encodeMessage(manifest)!;
    }
    return rootBundle.load(key);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async => extra[key] ?? rootBundle.loadString(key, cache: cache);
}
