import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/l10n/l10n.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/state/app_state.dart';
import 'package:sprawl_run/theme/colour_theme.dart';
import 'package:sprawl_run/util/clock.dart';

import 'support/fakes.dart';

/// Importing mission packs through the file picker — the only route in that
/// works, since the folder Settings used to point at is private on Android.
void main() {
  late Directory root;
  late Directory packsDir;
  late MissionRepository repo;

  setUp(() {
    root = tempRoot('pack-import');
    packsDir = Directory('${root.path}/packs');
    repo = MissionRepository(externalDir: packsDir, bundle: _DiskBundle());
  });
  tearDown(() => root.deleteSync(recursive: true));

  String pack({
    String id = 'ghost_line',
    String title = 'GHOST LINE',
    List<String> missionIds = const ['gl01'],
    Object? translations,
    Object? theme,
  }) =>
      jsonEncode({
        'id': id,
        'translations': ?translations,
        'theme': ?theme,
        'title': title,
        'tagline': 'Test pack',
        'missions': [
          for (var i = 0; i < missionIds.length; i++)
            {
              'id': missionIds[i],
              'order': i + 1,
              'codename': 'OP ${i + 1}',
              'title': 'Op ${i + 1}',
              'suggestedGoal': {'type': 'time', 'value': 900},
            },
        ],
      });

  Map<String, dynamic> glacier() =>
      {...jsonDecode(File('assets/themes/glacier.json').readAsStringSync()) as Map<String, dynamic>, 'id': 'tide', 'name': 'TIDE'};

  List<String> filesOnDisk() =>
      packsDir.existsSync() ? (packsDir.listSync().map((f) => f.uri.pathSegments.last).toList()..sort()) : [];

  group('importing', () {
    test('a pack is stored under its own id and loads beside the bundled ones', () async {
      await repo.importPack(pack());
      final packs = await repo.loadPacks();

      expect(filesOnDisk(), ['ghost_line.json']);
      expect(packs.map((p) => p.id), containsAll(['sprawl_prime', 'null_tide', 'ghost_line']));
      expect(repo.importedIds, {'ghost_line'});
    });

    test('importing a newer version replaces the old one rather than adding a copy', () async {
      await repo.importPack(pack(title: 'GHOST LINE'));
      await repo.importPack(pack(title: 'GHOST LINE v2', missionIds: ['gl01', 'gl02']));

      expect(filesOnDisk(), ['ghost_line.json']);
      final loaded = (await repo.loadPacks()).singleWhere((p) => p.id == 'ghost_line');
      expect(loaded.title, 'GHOST LINE v2');
      expect(loaded.missions, hasLength(2));
    });

    test('a pack with a bundled id replaces it, and removing it brings the original back', () async {
      await repo.importPack(pack(id: 'sprawl_prime', title: 'PATCHED'));
      expect((await repo.loadPacks()).singleWhere((p) => p.id == 'sprawl_prime').title, 'PATCHED');
      expect(repo.bundledIds.contains('sprawl_prime') && repo.importedIds.contains('sprawl_prime'), isTrue);

      await repo.removePack('sprawl_prime');
      final restored = (await repo.loadPacks()).singleWhere((p) => p.id == 'sprawl_prime');
      expect(restored.title, isNot('PATCHED'));
      expect(restored.missions, hasLength(10));
    });

    test('a copy put in place by hand under another name is cleared on import', () async {
      // The old instructions let a pack sit there under any file name.
      packsDir.createSync(recursive: true);
      File('${packsDir.path}/my-download (1).json').writeAsStringSync(pack(title: 'OLD'));

      await repo.importPack(pack(title: 'NEW'));
      expect(filesOnDisk(), ['ghost_line.json']);
      expect((await repo.loadPacks()).singleWhere((p) => p.id == 'ghost_line').title, 'NEW');
    });

    test('removal finds a pack by what it contains, not what the file is called', () async {
      packsDir.createSync(recursive: true);
      File('${packsDir.path}/whatever.json').writeAsStringSync(pack());
      await repo.removePack('ghost_line');
      expect(filesOnDisk(), isEmpty);
    });
  });

  group('refused, with nothing stored', () {
    Future<String> refusal(String source) async {
      try {
        await repo.importPack(source);
      } on PackImportException catch (e) {
        expect(filesOnDisk(), isEmpty, reason: 'nothing may be written for a refused import');
        return e.message;
      }
      fail('accepted a file that should have been refused');
    }

    test('a file that is not JSON', () async {
      expect(await refusal('not json at all'), contains('not JSON'));
    });

    test('JSON that is not a pack — a backup, say', () async {
      expect(await refusal('{"format":"sprawlrun.backup","runs":[]}'), contains('not a mission pack'));
    });

    test('a pack with no missions', () async {
      expect(await refusal(pack(missionIds: [])), contains('no missions'));
    });

    test('two missions sharing an id', () async {
      expect(await refusal(pack(missionIds: ['x', 'x'])), contains('"x"'));
    });

    test('a mission missing a required field, said plainly before the detail', () async {
      final broken = jsonEncode({
        'id': 'broken',
        'missions': [
          {'id': 'b1', 'order': 1, 'title': 'No codename', 'suggestedGoal': {'type': 'time', 'value': 900}},
        ],
      });
      expect(await refusal(broken), startsWith('The pack could not be read.'));
    });

    test('a translations block that is not language → key → text', () async {
      expect(await refusal(pack(translations: ['es'])), contains('"translations"'));
      expect(await refusal(pack(translations: {'Spanish': <String, String>{}})), contains('"translations"'));
      expect(await refusal(pack(translations: {'en': <String, String>{}})), contains('"translations"'));
    });

    test('a translated string the pack does not have, named', () async {
      expect(await refusal(pack(translations: {'es': {'gl01.titel': 'Op uno'}})), contains('"gl01.titel"'));
    });

    test('a theme that would not pass as a theme of its own, with its reason', () async {
      final unreadable = {...glacier(), 'colours': {...glacier()['colours'] as Map, 'text': '#0E1A22'}};
      final message = await refusal(pack(theme: unreadable));
      expect(message, startsWith('The pack\'s "theme" cannot be used.'));
      expect(message, contains('text'));
      expect(await refusal(pack(theme: 'Not An Id')), contains('"theme"'));
      expect(await refusal(pack(theme: 7)), contains('"theme"'));
    });

    test('an id that would escape the folder', () async {
      // Becomes the file name, so `../profile` would overwrite the runner's
      // data. Refused rather than cleaned up.
      expect(await refusal(pack(id: '../profile')), contains('letters, digits'));
      expect(File('${root.path}/profile.json').existsSync(), isFalse);
    });
  });

  group('a pack\'s own colours', () {
    late AppState state;
    late ProfileRepository profiles;

    setUp(() async {
      profiles = ProfileRepository(root);
      state = AppState(
        profiles: profiles,
        runs: RunRepository(Directory('${root.path}/runs')),
        missions: repo,
        narrator: FakeNarrator(),
      );
    });
    tearDown(() => debugNow = null);

    Future<void> playing(String packId, {Profile profile = const Profile(theme: 'volt')}) async {
      // July: no season in force, so only the pack and the runner compete.
      debugNow ??= DateTime(2026, 7, 15, 12);
      await profiles.save(profile.copyWith(activePackId: packId));
      await state.load();
    }

    ColourTheme named(String id) => state.themes.singleWhere((t) => t.id == id);

    test('a theme carried whole is read in, and worn while the pack is selected', () async {
      await repo.importPack(pack(theme: glacier()));
      final ghost = (await repo.loadPacks()).singleWhere((p) => p.id == 'ghost_line');
      expect(ghost.ownTheme?.id, 'tide');

      await playing('ghost_line');
      expect(state.packTheme?.id, 'tide');
      expect(state.palette, same(state.packTheme!.palette));

      await state.selectPack('sprawl_prime');
      expect(state.packTheme, isNull);
      expect(state.palette, same(named('volt').palette), reason: 'the runner\'s own theme on any other pack');
    });

    test('a theme named by id is the one on the phone, and an unknown id brings nothing', () async {
      await repo.importPack(pack(theme: 'glacier'));
      await playing('ghost_line');
      expect(state.palette, same(named('glacier').palette));

      await repo.importPack(pack(theme: 'nowhere'));
      await state.load();
      expect(state.packTheme, isNull);
      expect(state.palette, same(named('volt').palette));
    });

    test('the runner can refuse them', () async {
      await repo.importPack(pack(theme: 'glacier'));
      await playing('ghost_line', profile: const Profile(theme: 'volt', packColours: false));
      expect(state.packTheme, isNull);
      expect(state.palette, same(named('volt').palette));

      await state.updateProfile(state.profile.copyWith(packColours: true));
      expect(state.palette, same(named('glacier').palette));
    });

    test('a season in force wears its own over them', () async {
      debugNow = DateTime(2026, 10, 20, 12);
      await repo.importPack(pack(theme: 'glacier'));
      await playing('ghost_line');
      expect(state.season, isNotNull);
      expect(state.palette, same(state.season!.palette));
    });

    test('the switch survives a save, and a profile from before it lets packs choose', () {
      expect(Profile.fromJson(const {'callsign': 'CASE'}).packColours, isTrue);
      expect(Profile.fromJson(const Profile(packColours: false).toJson()).packColours, isFalse);
    });
  });

  test('removing a pack keeps progress, so importing it again picks up where it was', () async {
    final profiles = ProfileRepository(root);
    await profiles.save(const Profile(completedMissions: {'gl01'}));
    final state = AppState(
      profiles: profiles,
      runs: RunRepository(Directory('${root.path}/runs')),
      missions: repo,
      narrator: FakeNarrator(),
    );
    await state.load();

    await state.importMissionPack(pack(missionIds: ['gl01', 'gl02']));
    await state.removeMissionPack('ghost_line');
    expect(state.packs.map((p) => p.id), isNot(contains('ghost_line')));
    expect(state.profile.completedMissions, contains('gl01'));

    await state.importMissionPack(pack(missionIds: ['gl01', 'gl02']));
    expect(state.packs.map((p) => p.id), contains('ghost_line'));
    expect(state.profile.completedMissions, contains('gl01'), reason: 'still cleared after coming back');
  });

  testWidgets('a pack carries its own translation, shown in that language', (tester) async {
    final profiles = ProfileRepository(root);
    final state = AppState(
      profiles: profiles,
      runs: RunRepository(Directory('${root.path}/runs')),
      missions: repo,
      narrator: FakeNarrator(),
    );
    addTearDown(() => useLocale(const Locale('en')));
    await tester.runAsync(() async {
      await profiles.save(const Profile(language: 'es'));
      await state.load();
      await state.importMissionPack(
        pack(translations: {'es': {'tagline': 'Paquete de prueba', 'gl01.title': 'Op uno'}}),
      );
    });
    final ghost = state.packs.firstWhere((p) => p.id == 'ghost_line');
    expect((ghost.tagline, ghost.missions.single.title), ('Paquete de prueba', 'Op uno'));
    expect(ghost.missions.single.codename, 'OP 1', reason: 'a name');
  });
}

/// Reads the bundled packs straight off disk: a plain unit test has no asset
/// bundle.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.view(File(key).readAsBytesSync().buffer);

  @override
  Future<String> loadString(String key, {bool cache = true}) async => File(key).readAsStringSync();
}
