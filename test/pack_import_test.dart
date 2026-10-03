import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/state/app_state.dart';

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

  String pack({String id = 'ghost_line', String title = 'GHOST LINE', List<String> missionIds = const ['gl01']}) =>
      jsonEncode({
        'id': id,
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

    test('an id that would escape the folder', () async {
      // Becomes the file name, so `../profile` would overwrite the runner's
      // data. Refused rather than cleaned up.
      expect(await refusal(pack(id: '../profile')), contains('letters, digits'));
      expect(File('${root.path}/profile.json').existsSync(), isFalse);
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
}

/// Reads the bundled packs straight off disk: a plain unit test has no asset
/// bundle.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.view(File(key).readAsBytesSync().buffer);

  @override
  Future<String> loadString(String key, {bool cache = true}) async => File(key).readAsStringSync();
}
