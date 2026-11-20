import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/audio/song.dart';
import 'package:sprawl_run/data/song_repository.dart';

import 'support/fakes.dart';

/// A song that parses: a shipped one under another id and name.
String songJson({String id = 'mine', String name = 'Mine', Map<String, Object?> extra = const {}}) {
  final base = jsonDecode(File('assets/songs/cold_boot.json').readAsStringSync()) as Map<String, dynamic>;
  return jsonEncode({...base, 'id': id, 'name': name, ...extra});
}

Matcher refusedWith(String text) =>
    throwsA(isA<SongFormatException>().having((e) => e.message, 'message', contains(text)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late SongRepository repo;
  final shipped = [
    for (final f in Directory('assets/songs').listSync().whereType<File>())
      (jsonDecode(f.readAsStringSync()) as Map)['id'] as String,
  ];

  setUp(() async {
    root = tempRoot('songs');
    repo = SongRepository(importDir: Directory('${root.path}/songs'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('offers every shipped song, and nothing more until one is imported', () async {
    expect((await repo.songs()).map((s) => s.id), unorderedEquals(shipped));
    expect(repo.builtInIds, shipped.toSet());
    expect(repo.importedIds, isEmpty);
  });

  test('adds a song after the shipped ones, replaces it on a re-import and removes it', () async {
    await repo.importSong(songJson());
    expect((await repo.songs()).last.id, 'mine');
    expect(repo.importedIds, {'mine'});

    await repo.importSong(songJson(name: 'Mine II'));
    expect((await repo.songs()).where((s) => s.id == 'mine').single.name, 'Mine II');

    await repo.removeSong('mine');
    expect((await repo.songs()).map((s) => s.id), isNot(contains('mine')));
    expect(repo.importedIds, isEmpty);
  });

  test('plays an imported song: its source is found by id', () async {
    final source = songJson();
    await repo.importSong(source);
    expect(await repo.sourceOf('mine'), source);
    expect(await repo.importedSource('mine'), source);
    expect(await repo.sourceOf('cold_boot'), isNotNull);
    expect(await repo.importedSource('cold_boot'), isNull, reason: 'a shipped song is not exported');
  });

  test('will not take a built-in id', () async {
    expect(() => repo.importSong(songJson(id: 'cold_boot')), refusedWith('already uses the id "cold_boot"'));
  });

  test('refuses what the format refuses', () async {
    expect(() => repo.importSong('{'), refusedWith('not JSON'));
    expect(() => repo.importSong(songJson(extra: {'format': Song.currentFormat + 1})), refusedWith('newer version'));
    expect(() => repo.importSong(' ' * (Song.maxBytes + 1)), refusedWith('too large'));
    expect(Directory('${root.path}/songs').existsSync(), isFalse, reason: 'nothing refused is kept');
  });

  test('skips a broken file instead of failing the rest', () async {
    await repo.importSong(songJson());
    File('${root.path}/songs/broken.json').writeAsStringSync('{');
    expect((await repo.songs()).map((s) => s.id), contains('mine'));
    expect(await repo.sourceOf('broken'), isNull);
  });

  test('a shipped song wins over an import that took its id first', () async {
    Directory('${root.path}/songs').createSync(recursive: true);
    File('${root.path}/songs/cold_boot.json').writeAsStringSync(songJson(id: 'cold_boot', name: 'Impostor'));
    final songs = await repo.songs();
    expect(songs.where((s) => s.id == 'cold_boot').single.name, 'Cold Boot');
    expect(repo.importedIds, isEmpty);
  });

  group('a backup', () {
    test('carries the imported songs only, and brings them back', () async {
      await repo.importSong(songJson());
      final carried = await repo.importedForBackup();
      expect(carried.map((s) => s['id']), ['mine']);

      final other = SongRepository(importDir: Directory('${root.path}/elsewhere'));
      expect(await other.restore(carried, replace: false), 1);
      expect((await other.songs()).map((s) => s.id), contains('mine'));
    });

    test('merging keeps a song this phone already has; replacing makes the set the backup\'s', () async {
      await repo.importSong(songJson(name: 'Here'));
      await repo.importSong(songJson(id: 'only_here'));
      final backup = [jsonDecode(songJson(name: 'From backup')) as Map<String, dynamic>];

      expect(await repo.restore(backup, replace: false), 0);
      expect((await repo.songs()).where((s) => s.id == 'mine').single.name, 'Here');

      expect(await repo.restore(backup, replace: true), 1);
      final ids = (await repo.songs()).map((s) => s.id);
      expect(ids, contains('mine'));
      expect(ids, isNot(contains('only_here')));
      expect((await repo.songs()).where((s) => s.id == 'mine').single.name, 'From backup');
    });

    test('skips a song that no longer passes rather than failing the restore', () async {
      final backup = [
        jsonDecode(songJson(id: 'cold_boot')) as Map<String, dynamic>,
        {'id': 'junk'},
        jsonDecode(songJson()) as Map<String, dynamic>,
      ];
      expect(await repo.restore(backup, replace: false), 1);
      expect(repo.importedIds, {'mine'});
    });
  });
}
