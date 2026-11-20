import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../audio/song.dart';
import '../l10n/l10n.dart';
import 'atomic_write.dart';

/// The songs on offer: every file in `assets/songs/`, and the ones the runner
/// imported.
///
/// Shipped songs are found through the asset manifest rather than listed in
/// code, so adding a song is adding a file — see docs/SONGS.md. Imported songs
/// live in [importDir], the app's private storage, and come in only through
/// [importSong], fed by the system file picker as themes and mission packs are.
/// The same instance serves Settings and the player, so a song imported a
/// moment ago plays on the next run.
class SongRepository {
  SongRepository({required this.importDir, AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const String assetFolder = 'assets/songs/';

  final Directory importDir;
  final AssetBundle _bundle;

  /// Ids of the songs that came from [importDir], and so can be removed.
  final Set<String> importedIds = {};

  /// Ids an import may not take: every shipped song.
  final Set<String> builtInIds = {};

  /// Every song that parses, for the runner to choose from: the shipped ones,
  /// then the imported ones. A shipped song added later under an imported
  /// song's id wins over the import.
  Future<List<Song>> songs() async {
    importedIds.clear();
    builtInIds.clear();
    final out = <Song>[];
    for (final path in await _assetSongs()) {
      try {
        final song = Song.parse(await _bundle.loadString(path));
        if (builtInIds.add(song.id)) out.add(song);
      } on Object catch (e) {
        debugPrint('Song $path: $e');
      }
    }
    for (final file in await _importedFiles()) {
      try {
        final song = Song.parse(await file.readAsString());
        if (builtInIds.contains(song.id) || !importedIds.add(song.id)) continue;
        out.add(song);
      } on Object catch (e) {
        debugPrint('Song ${file.uri.pathSegments.last}: $e');
      }
    }
    return out;
  }

  /// The file for [id], checked, or null if there is no such song or it does not
  /// parse. A bad file costs the runner the music, never the run. A shipped song
  /// is looked for first, as [songs] lets it win.
  Future<String?> sourceOf(String id) async {
    for (final path in await _assetSongs()) {
      final source = await _checked(() => _bundle.loadString(path), id, path);
      if (source != null) return source;
    }
    for (final file in await _importedFiles()) {
      final source = await _checked(file.readAsString, id, file.path);
      if (source != null) return source;
    }
    return null;
  }

  Future<String?> _checked(Future<String> Function() read, String id, String where) async {
    try {
      final source = await read();
      if (Song.parse(source).id == id) return source;
    } on Object catch (e) {
      debugPrint('Song $where: $e');
    }
    return null;
  }

  /// Validates a picked file and keeps it under its id, so importing a revised
  /// version replaces the old one — the edit-and-reimport loop for someone
  /// writing a song. Throws [SongFormatException] with a message fit to show
  /// the runner.
  Future<Song> importSong(String source) async {
    final song = Song.parse(source);
    if (builtInIds.isEmpty) await songs();
    if (builtInIds.contains(song.id)) throw SongFormatException(l10n.songErrorBuiltInId(song.id));
    await importDir.create(recursive: true);
    await writeAtomically(File('${importDir.path}/${song.id}.json'), source);
    importedIds.add(song.id);
    return song;
  }

  /// An imported song's file as it was imported, for exporting; null for a
  /// shipped song or one that has gone.
  Future<String?> importedSource(String id) async {
    final file = File('${importDir.path}/$id.json');
    return await file.exists() ? file.readAsString() : null;
  }

  /// The imported songs as their files have them, for a backup: they are the
  /// runner's own and exist nowhere else. Only the ones that still load.
  Future<List<Map<String, dynamic>>> importedForBackup() async {
    final out = <Map<String, dynamic>>[];
    for (final file in await _importedFiles()) {
      try {
        final source = await file.readAsString();
        Song.parse(source);
        out.add(Map<String, dynamic>.from(jsonDecode(source) as Map));
      } on Object {
        continue;
      }
    }
    return out;
  }

  /// Puts back the songs a backup carried, each checked as an import is.
  /// [replace] makes this device's imported songs exactly the backup's;
  /// otherwise only the ones it lacks are added, and a song it already has
  /// under the same id stays as it is here. One that no longer passes — or
  /// whose id a shipped song has taken since — is skipped rather than failing
  /// the restore. Returns how many were added.
  Future<int> restore(List<Map<String, dynamic>> songList, {required bool replace}) async {
    if (replace) {
      for (final file in await _importedFiles()) {
        await file.delete();
      }
    }
    await songs();
    final have = {...importedIds};
    var added = 0;
    for (final raw in songList) {
      if (have.contains(raw['id'])) continue;
      try {
        final song = await importSong(jsonEncode(raw));
        have.add(song.id);
        added++;
      } on SongFormatException {
        continue;
      }
    }
    return added;
  }

  /// Deletes an imported song. Its id is checked by [Song.parse] on the way
  /// in, so it is a safe file name.
  Future<void> removeSong(String id) async {
    final file = File('${importDir.path}/$id.json');
    if (await file.exists()) await file.delete();
    importedIds.remove(id);
  }

  Future<List<String>> _assetSongs() async {
    try {
      final assets = (await AssetManifest.loadFromAssetBundle(_bundle)).listAssets();
      return [for (final a in assets) if (a.startsWith(assetFolder) && a.endsWith('.json')) a]..sort();
    } on Object {
      return const [];
    }
  }

  Future<List<File>> _importedFiles() async {
    if (!await importDir.exists()) return const [];
    final files = await importDir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.json'))
        .cast<File>()
        .toList();
    return files..sort((a, b) => a.path.compareTo(b.path));
  }
}
