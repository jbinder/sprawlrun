import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/mission.dart';
import 'atomic_write.dart';

/// Loads mission packs.
///
/// Two sources, in order:
///   1. the packs bundled with the app ([bundledPacks]);
///   2. any `*.json` in `<documents>/mission_packs/`, put there by
///      [importPack].
///
/// The second source is the whole future-content story: a new pack is a plain
/// JSON file with the same shape as `assets/missions/sprawl_prime.json`, and
/// nothing in the app needs to change to play it.
///
/// That directory is the app's private storage, which a runner cannot reach on
/// Android without root. For a long time Settings told them to drop files into
/// it anyway; [importPack] — fed by the system file picker — is the only route
/// in that actually works.
class MissionRepository {
  MissionRepository({required this.externalDir, AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const List<String> bundledPacks = [
    'assets/missions/sprawl_prime.json',
    'assets/missions/null_tide.json',
  ];

  /// Where side-loaded packs live. Created lazily; missing is not an error.
  final Directory externalDir;
  final AssetBundle _bundle;

  List<MissionPack>? _cache;

  /// Problems found while loading side-loaded packs, surfaced in Settings so a
  /// malformed pack is debuggable without a log viewer.
  final List<String> loadErrors = [];

  /// Ids of the packs that came from [externalDir] rather than the app, and so
  /// can be removed again. Filled by [loadPacks].
  final Set<String> importedIds = {};

  /// Ids of the packs shipped with the app. An imported pack with one of these
  /// ids replaces the shipped one until it is removed again.
  final Set<String> bundledIds = {};

  /// Largest file an import will read. The shipped packs are under 200 KB;
  /// anything far bigger is not a pack, and is refused before it is parsed.
  static const int maxPackBytes = 4 * 1024 * 1024;

  Future<List<MissionPack>> loadPacks() async {
    if (_cache != null) return _cache!;
    final packs = <MissionPack>[];
    loadErrors.clear();
    importedIds.clear();
    bundledIds.clear();

    for (final path in bundledPacks) {
      try {
        final pack = MissionPack.fromJson(Map<String, dynamic>.from(jsonDecode(await _bundle.loadString(path)) as Map));
        packs.add(pack);
        bundledIds.add(pack.id);
      } on Object catch (e) {
        loadErrors.add('$path: $e');
      }
    }

    if (await externalDir.exists()) {
      final files = await externalDir
          .list()
          .where((e) => e is File && e.path.toLowerCase().endsWith('.json'))
          .cast<File>()
          .toList();
      files.sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        try {
          final pack = MissionPack.fromJson(
            Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map),
          );
          // A side-loaded pack may deliberately replace a bundled one. It
          // takes the bundled pack's place rather than moving to the end, so
          // patching shipped content does not reorder the campaign list.
          final existing = packs.indexWhere((p) => p.id == pack.id);
          if (existing >= 0) {
            packs[existing] = pack;
          } else {
            packs.add(pack);
          }
          importedIds.add(pack.id);
        } on Object catch (e) {
          loadErrors.add('${file.uri.pathSegments.last}: $e');
        }
      }
    }

    return _cache = packs;
  }

  void invalidate() => _cache = null;

  /// Checks [source] is a playable pack and stores it, replacing any earlier
  /// import of the same pack. Throws [PackImportException] with a message fit
  /// to show the runner.
  ///
  /// Stored under the pack's own id rather than the picked file's name, so
  /// importing a revised version of a pack replaces it instead of adding a
  /// second copy beside it — which is also the edit-and-reimport loop for
  /// someone writing a pack.
  Future<MissionPack> importPack(String source) async {
    final MissionPack pack;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map || decoded['id'] is! String || decoded['missions'] is! List) {
        throw const PackImportException(
          'That is not a mission pack — it needs an "id" and a list of "missions".',
        );
      }
      pack = MissionPack.fromJson(Map<String, dynamic>.from(decoded));
    } on PackImportException {
      rethrow;
    } on FormatException {
      throw const PackImportException('That file is not JSON.');
    } on Object catch (e) {
      // A missing or mistyped field in a mission. The detail is for the author;
      // the first sentence is for everyone else.
      throw PackImportException('The pack could not be read. A mission is missing a required field.\n$e');
    }

    final fileName = packFileName(pack.id);
    if (fileName == null) {
      throw const PackImportException('The pack id may only use letters, digits, "-" and "_".');
    }
    if (pack.missions.isEmpty) {
      throw const PackImportException('The pack has no missions in it.');
    }
    final ids = <String>{};
    for (final m in pack.missions) {
      if (!ids.add(m.id)) {
        throw PackImportException('Two missions share the id "${m.id}".');
      }
    }

    await externalDir.create(recursive: true);
    final target = File('${externalDir.path}/$fileName');
    await writeAtomically(target, source);
    // Only once the new copy is safely written: any other file holding this
    // pack — one put in place by hand, under some other name — goes, so the
    // two cannot disagree about which version is loaded.
    await _deleteFilesOf(pack.id, except: target);
    invalidate();
    return pack;
  }

  /// Deletes an imported pack. A pack that replaced a bundled one leaves the
  /// bundled version in its place. Progress is untouched: completed missions
  /// are recorded by id, so importing the pack again picks up where it was.
  Future<void> removePack(String id) async {
    await _deleteFilesOf(id);
    invalidate();
  }

  /// Deletes every imported file holding pack [id], matched by what a file
  /// contains rather than what it is called: packs put in place by hand under
  /// the old instructions can have any name.
  Future<void> _deleteFilesOf(String id, {File? except}) async {
    if (!await externalDir.exists()) return;
    await for (final entry in externalDir.list()) {
      if (entry is! File || !entry.path.toLowerCase().endsWith('.json')) continue;
      if (except != null && entry.path == except.path) continue;
      try {
        final raw = jsonDecode(await entry.readAsString());
        if (raw is Map && raw['id'] == id) await entry.delete();
      } on Object {
        continue;
      }
    }
  }

  /// The file an imported pack is kept in, or null for an id that could not be
  /// a safe filename. Ids are checked rather than cleaned up: a pack id that
  /// reached the filesystem as `../profile` would overwrite the runner's data.
  static String? packFileName(String id) =>
      RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id) ? '$id.json' : null;

  /// Every mission across every pack, in campaign order.
  Future<List<Mission>> allMissions() async {
    final packs = await loadPacks();
    return [for (final pack in packs) ...pack.missions];
  }
}

/// The campaign chain: which missions are done, which one is live, which are
/// still dark.
enum MissionState { completed, available, locked }

class MissionProgress {
  const MissionProgress({required this.mission, required this.state, required this.attempts});

  final Mission mission;
  final MissionState state;
  final int attempts;

  bool get isPlayable => state != MissionState.locked;

  /// How the runner has got on with it, independent of whether it is reachable.
  MissionStatus get status => state == MissionState.completed
      ? MissionStatus.finished
      : attempts > 0
      ? MissionStatus.started
      : MissionStatus.fresh;
}

/// Progress on a single mission: untouched, attempted, or cleared.
enum MissionStatus { fresh, started, finished }

/// Where a pack stands as a whole.
enum PackState {
  /// Nothing attempted yet.
  fresh,

  /// Some progress, missions still open.
  active,

  /// Every mission cleared.
  done,
}

/// A pack with the runner's progress through it.
class PackProgress {
  const PackProgress({required this.pack, required this.chain, required this.selected});

  final MissionPack pack;
  final List<MissionProgress> chain;

  /// Whether this is the pack the ops screen shows.
  final bool selected;

  int get completed => chain.where((m) => m.state == MissionState.completed).length;
  int get total => chain.length;
  bool get isDone => total > 0 && completed == total;
  bool get isFresh => chain.every((m) => m.attempts == 0 && m.state != MissionState.completed);

  PackState get state => isDone
      ? PackState.done
      : isFresh
      ? PackState.fresh
      : PackState.active;
}

/// Resolves the locked/available/completed chain for one pack.
///
/// Exactly one mission is [MissionState.available] at a time: the lowest-order
/// mission that has not been completed. Everything after it stays locked, which
/// is what keeps the story in order.
List<MissionProgress> resolveChain(
  List<Mission> missions,
  Set<String> completed,
  Map<String, int> attempts,
) {
  final ordered = List<Mission>.from(missions)..sort((a, b) => a.order.compareTo(b.order));
  var nextFound = false;
  return [
    for (final mission in ordered)
      MissionProgress(
        mission: mission,
        attempts: attempts[mission.id] ?? 0,
        state: () {
          if (completed.contains(mission.id)) return MissionState.completed;
          if (!nextFound) {
            nextFound = true;
            return MissionState.available;
          }
          return MissionState.locked;
        }(),
      ),
  ];
}

/// Why a pack could not be imported, in words for the runner.
class PackImportException implements Exception {
  const PackImportException(this.message);

  final String message;

  @override
  String toString() => message;
}
