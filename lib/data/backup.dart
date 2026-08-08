import 'dart:convert';

import '../models/profile.dart';
import '../models/run_record.dart';
import 'profile_repository.dart';
import 'run_repository.dart';

/// Everything the app knows about a runner, in one portable JSON document.
///
/// The app stores nothing anywhere else — stats, streaks and achievement
/// progress are all derived from the run log — so a profile plus every run,
/// GPS traces included, is a genuinely complete backup. Restoring one onto an
/// empty install reproduces the original device exactly.
class BackupArchive {
  const BackupArchive({required this.exportedAt, required this.profile, required this.runs});

  /// Marker in the JSON that identifies the file as ours. Checked on import so
  /// a runner who picks the wrong file gets an explanation rather than a wiped
  /// campaign.
  static const String magic = 'sprawlrun.backup';

  /// Bumped only for a change that older builds could not read correctly.
  /// Additive fields do not need it — both sides tolerate what they don't know.
  static const int currentVersion = 1;

  final DateTime exportedAt;
  final Profile profile;

  /// Every stored run, traces included.
  final List<RunRecord> runs;

  int get traceCount => runs.where((r) => r.trace.isNotEmpty).length;

  Map<String, dynamic> toJson() => {
    'format': magic,
    'version': currentVersion,
    'exportedAt': exportedAt.toIso8601String(),
    'profile': profile.toJson(),
    'runs': runs.map((r) => r.toJson()).toList(),
  };

  /// Parses an exported document.
  ///
  /// Throws [BackupFormatException] for anything that is not one of ours, and
  /// for a version this build predates. Individual malformed runs are dropped
  /// rather than failing the whole import — a backup that is 99% readable is
  /// worth more than an error.
  factory BackupArchive.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const BackupFormatException('That file is not JSON.');
    }
    if (decoded is! Map || decoded['format'] != magic) {
      throw const BackupFormatException('That is not a SPRAWL//RUN backup file.');
    }
    final version = (decoded['version'] as num?)?.toInt() ?? 0;
    if (version > currentVersion) {
      throw BackupFormatException(
        'That backup was written by a newer version of the app (format $version). Update and try again.',
      );
    }

    final runs = <RunRecord>[];
    for (final entry in (decoded['runs'] as List? ?? const [])) {
      try {
        runs.add(RunRecord.fromJson(Map<String, dynamic>.from(entry as Map)));
      } on Object {
        // Skip the unreadable run; the rest of the log still imports.
        continue;
      }
    }
    runs.sort((a, b) => b.startedAt.compareTo(a.startedAt));

    Profile profile;
    try {
      profile = Profile.fromJson(Map<String, dynamic>.from(decoded['profile'] as Map));
    } on Object {
      throw const BackupFormatException('The backup is missing a readable profile.');
    }

    return BackupArchive(
      exportedAt: DateTime.tryParse(decoded['exportedAt'] as String? ?? '') ?? DateTime.now(),
      profile: profile,
      runs: runs,
    );
  }
}

class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What an import should do with the data already on the device.
enum ImportMode {
  /// Restore the backup exactly: settings, progress and run log all replaced.
  /// This is what you want on a new phone.
  replace,

  /// Keep this device's settings and add anything the backup has that is
  /// missing here. Runs are matched by id, campaign progress is unioned.
  merge,
}

/// What an import actually did, so the UI can report it honestly.
class ImportReport {
  const ImportReport({
    required this.mode,
    required this.runsAdded,
    required this.runsAlreadyPresent,
    required this.missionsAdded,
    required this.achievementsAdded,
    required this.codexAdded,
  });

  final ImportMode mode;
  final int runsAdded;
  final int runsAlreadyPresent;
  final int missionsAdded;
  final int achievementsAdded;
  final int codexAdded;
}

/// Reads and writes [BackupArchive]s against the real repositories.
///
/// Owns no UI and no file picking: the caller supplies a string to import and
/// decides where an exported string goes. That keeps the whole round trip
/// testable without a device.
class BackupService {
  BackupService({required this.profiles, required this.runs});

  final ProfileRepository profiles;
  final RunRepository runs;

  /// A filename that sorts chronologically and survives a share sheet.
  static String suggestedFileName(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'sprawlrun-backup-${at.year}-${two(at.month)}-${two(at.day)}-${two(at.hour)}${two(at.minute)}.json';
  }

  /// Collects the whole device state, pulling each GPS trace back in — the run
  /// log is stored without them, so this is the one place that reassembles a
  /// complete record.
  Future<BackupArchive> collect() async {
    final index = await runs.loadAll();
    final full = <RunRecord>[];
    for (final run in index) {
      full.add(run.withTrace(await runs.loadTrace(run.id)));
    }
    return BackupArchive(
      exportedAt: DateTime.now(),
      profile: await profiles.load(),
      runs: full,
    );
  }

  Future<String> exportToJson() async => jsonEncode((await collect()).toJson());

  /// Writes [archive] into the repositories and reports what changed.
  ///
  /// The run log is written in one pass rather than run by run, so an import
  /// that dies halfway cannot leave a half-restored index behind.
  Future<ImportReport> import(BackupArchive archive, ImportMode mode) async {
    if (mode == ImportMode.replace) {
      await runs.replaceAll(archive.runs);
      await profiles.save(archive.profile);
      return ImportReport(
        mode: mode,
        runsAdded: archive.runs.length,
        runsAlreadyPresent: 0,
        missionsAdded: archive.profile.completedMissions.length,
        achievementsAdded: archive.profile.unlockedAchievements.length,
        codexAdded: archive.profile.unlockedCodex.length,
      );
    }

    final existing = await runs.loadAll();
    final knownIds = existing.map((r) => r.id).toSet();
    final incoming = archive.runs.where((r) => !knownIds.contains(r.id)).toList();

    // Existing runs are re-read with their traces so replaceAll does not drop
    // the trace files it is about to rewrite the index for.
    final kept = <RunRecord>[];
    for (final run in existing) {
      kept.add(run.withTrace(await runs.loadTrace(run.id)));
    }
    await runs.replaceAll([...kept, ...incoming]);

    final local = await profiles.load();
    final merged = _mergeProfiles(local, archive.profile);
    await profiles.save(merged);

    return ImportReport(
      mode: mode,
      runsAdded: incoming.length,
      runsAlreadyPresent: archive.runs.length - incoming.length,
      missionsAdded: merged.completedMissions.length - local.completedMissions.length,
      achievementsAdded: merged.unlockedAchievements.length - local.unlockedAchievements.length,
      codexAdded: merged.unlockedCodex.length - local.unlockedCodex.length,
    );
  }

  /// Keeps [local]'s settings and identity — the runner configured this device
  /// on purpose — and takes the union of everything that represents progress.
  /// Progress is only ever added, never revoked, so merging in an older backup
  /// cannot relock a mission.
  static Profile _mergeProfiles(Profile local, Profile incoming) {
    final achievements = Map<String, DateTime>.from(local.unlockedAchievements);
    incoming.unlockedAchievements.forEach((id, at) {
      final mine = achievements[id];
      // Whichever device earned it first is the honest unlock date.
      if (mine == null || at.isBefore(mine)) achievements[id] = at;
    });

    final attempts = Map<String, int>.from(local.missionAttempts);
    incoming.missionAttempts.forEach((id, count) {
      attempts[id] = (attempts[id] ?? 0) > count ? attempts[id]! : count;
    });

    return local.copyWith(
      completedMissions: {...local.completedMissions, ...incoming.completedMissions},
      unlockedAchievements: achievements,
      unlockedCodex: {...local.unlockedCodex, ...incoming.unlockedCodex},
      missionAttempts: attempts,
      // A goal this device has never chosen is worth inheriting; one it has is
      // the runner's more recent decision and stays.
      lastGoalByMission: {...incoming.lastGoalByMission, ...local.lastGoalByMission},
    );
  }
}
