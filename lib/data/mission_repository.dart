import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/mission.dart';

/// Loads mission packs.
///
/// Two sources, in order:
///   1. the packs bundled with the app ([bundledPacks]);
///   2. any `*.json` dropped into `<documents>/mission_packs/`.
///
/// The second source is the whole future-content story: a new pack is a plain
/// JSON file with the same shape as `assets/missions/sprawl_prime.json`, and
/// nothing in the app needs to change to play it.
class MissionRepository {
  MissionRepository({required this.externalDir, AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const List<String> bundledPacks = ['assets/missions/sprawl_prime.json'];

  /// Where side-loaded packs live. Created lazily; missing is not an error.
  final Directory externalDir;
  final AssetBundle _bundle;

  List<MissionPack>? _cache;

  /// Problems found while loading side-loaded packs, surfaced in Settings so a
  /// malformed pack is debuggable without a log viewer.
  final List<String> loadErrors = [];

  Future<List<MissionPack>> loadPacks() async {
    if (_cache != null) return _cache!;
    final packs = <MissionPack>[];
    loadErrors.clear();

    for (final path in bundledPacks) {
      try {
        packs.add(MissionPack.fromJson(Map<String, dynamic>.from(jsonDecode(await _bundle.loadString(path)) as Map)));
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
          // A side-loaded pack may deliberately replace a bundled one.
          packs.removeWhere((p) => p.id == pack.id);
          packs.add(pack);
        } on Object catch (e) {
          loadErrors.add('${file.uri.pathSegments.last}: $e');
        }
      }
    }

    return _cache = packs;
  }

  void invalidate() => _cache = null;

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
