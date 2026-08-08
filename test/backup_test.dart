import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/backup.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/run_record.dart';

import 'support/fakes.dart';

/// A device's worth of state, so a test can state only what it cares about.
Future<BackupService> seed(
  Directory root, {
  Profile profile = const Profile(),
  List<RunRecord> runs = const [],
}) async {
  final service = BackupService(
    profiles: ProfileRepository(root),
    runs: RunRepository(Directory('${root.path}/runs')),
  );
  await service.profiles.save(profile);
  for (final record in runs) {
    await service.runs.save(record);
  }
  return service;
}

RunRecord traced(DateTime at, {int points = 3}) => RunRecord(
  id: at.microsecondsSinceEpoch.toString(),
  startedAt: at,
  endedAt: at.add(const Duration(minutes: 30)),
  elapsedSeconds: 1800,
  movingSeconds: 1750,
  distanceMeters: 5000,
  calories: 350,
  goal: const RunGoal(GoalType.time, 1800),
  outcome: RunOutcome.success,
  trace: [
    for (var i = 0; i < points; i++)
      TracePoint(lat: 52.52 + i * 0.001, lon: 13.40, elapsedSeconds: i * 10.0, speedMps: 3),
  ],
);

void main() {
  late Directory source;
  late Directory target;

  setUp(() {
    source = tempRoot('backup_src');
    target = tempRoot('backup_dst');
  });

  tearDown(() {
    source.deleteSync(recursive: true);
    target.deleteSync(recursive: true);
  });

  group('export', () {
    test('carries the profile, the run log and the GPS traces', () async {
      final service = await seed(
        source,
        profile: const Profile(
          callsign: 'MOLLY',
          weightKg: 61,
          units: UnitSystem.imperial,
          completedMissions: {'sp01', 'sp02'},
          unlockedCodex: {'cdx_ninsei'},
        ),
        runs: [traced(DateTime(2026, 7, 20), points: 40), traced(DateTime(2026, 7, 22), points: 12)],
      );

      final archive = await service.collect();

      expect(archive.profile.callsign, 'MOLLY');
      expect(archive.runs, hasLength(2));
      expect(archive.traceCount, 2);
      // The traces live in separate files and must be pulled back in by name;
      // getting this wrong exports an index with empty traces and looks fine.
      expect(archive.runs.map((r) => r.trace.length), [12, 40]);
    });

    test('produces a document that identifies itself', () async {
      final service = await seed(source);
      final json = jsonDecode(await service.exportToJson()) as Map<String, dynamic>;

      expect(json['format'], BackupArchive.magic);
      expect(json['version'], BackupArchive.currentVersion);
      expect(DateTime.parse(json['exportedAt'] as String), isNotNull);
    });

    test('an untouched install exports cleanly rather than failing', () async {
      final service = BackupService(
        profiles: ProfileRepository(source),
        runs: RunRepository(Directory('${source.path}/runs')),
      );
      final archive = BackupArchive.parse(await service.exportToJson());
      expect(archive.runs, isEmpty);
      expect(archive.profile.callsign, 'RUNNER');
    });
  });

  group('parse', () {
    test('rejects a file that is not ours before anything is touched', () {
      expect(
        () => BackupArchive.parse('{"format":"something.else","runs":[]}'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects text that is not JSON at all', () {
      expect(() => BackupArchive.parse('<html>'), throwsA(isA<BackupFormatException>()));
    });

    test('refuses a backup from a newer format rather than guessing', () {
      final future = jsonEncode({
        'format': BackupArchive.magic,
        'version': BackupArchive.currentVersion + 1,
        'profile': const Profile().toJson(),
        'runs': [],
      });
      expect(() => BackupArchive.parse(future), throwsA(isA<BackupFormatException>()));
    });

    test('drops an unreadable run instead of losing the whole log', () {
      final mixed = jsonEncode({
        'format': BackupArchive.magic,
        'version': 1,
        'profile': const Profile().toJson(),
        'runs': [
          traced(DateTime(2026, 7, 22)).toJson(),
          {'id': 'broken'},
          traced(DateTime(2026, 7, 20)).toJson(),
        ],
      });
      expect(BackupArchive.parse(mixed).runs, hasLength(2));
    });
  });

  group('replace', () {
    test('reproduces the source device exactly on an empty target', () async {
      final from = await seed(
        source,
        profile: const Profile(callsign: 'MOLLY', weightKg: 61, completedMissions: {'sp01'}),
        runs: [traced(DateTime(2026, 7, 20), points: 40), traced(DateTime(2026, 7, 22), points: 12)],
      );
      final to = await seed(target);

      final report = await to.import(BackupArchive.parse(await from.exportToJson()), ImportMode.replace);

      expect(report.runsAdded, 2);
      final restored = await to.collect();
      expect(restored.profile.callsign, 'MOLLY');
      expect(restored.profile.weightKg, 61);
      expect(restored.profile.completedMissions, {'sp01'});
      expect(restored.runs.map((r) => r.trace.length), [12, 40]);
    });

    test('a second round trip is stable', () async {
      final from = await seed(
        source,
        profile: const Profile(callsign: 'MOLLY', unlockedCodex: {'cdx_ninsei'}),
        runs: [traced(DateTime(2026, 7, 22), points: 9)],
      );
      final to = await seed(target);

      final first = await from.exportToJson();
      await to.import(BackupArchive.parse(first), ImportMode.replace);
      final second = await to.exportToJson();

      final a = jsonDecode(first) as Map<String, dynamic>..remove('exportedAt');
      final b = jsonDecode(second) as Map<String, dynamic>..remove('exportedAt');
      expect(b, a);
    });

    test('wipes what the target already had, traces included', () async {
      final from = await seed(source, runs: [traced(DateTime(2026, 7, 22))]);
      final doomed = traced(DateTime(2026, 6, 1));
      final to = await seed(
        target,
        profile: const Profile(callsign: 'OLD'),
        runs: [doomed],
      );

      await to.import(BackupArchive.parse(await from.exportToJson()), ImportMode.replace);

      final left = await to.runs.loadAll();
      expect(left, hasLength(1));
      expect(left.single.startedAt.month, 7);
      expect(await to.runs.loadTrace(doomed.id), isEmpty, reason: 'orphaned traces must not survive');
      expect((await to.profiles.load()).callsign, 'RUNNER');
    });
  });

  group('merge', () {
    test('adds only the runs the target does not already have', () async {
      final shared = traced(DateTime(2026, 7, 20));
      final from = await seed(source, runs: [shared, traced(DateTime(2026, 7, 22))]);
      final to = await seed(target, runs: [shared, traced(DateTime(2026, 7, 25))]);

      final report = await to.import(BackupArchive.parse(await from.exportToJson()), ImportMode.merge);

      expect(report.runsAdded, 1);
      expect(report.runsAlreadyPresent, 1);
      expect((await to.runs.loadAll()).map((r) => r.startedAt.day), [25, 22, 20]);
    });

    test('keeps the traces the target already had', () async {
      final mine = traced(DateTime(2026, 7, 25), points: 30);
      final from = await seed(source, runs: [traced(DateTime(2026, 7, 22), points: 5)]);
      final to = await seed(target, runs: [mine]);

      await to.import(BackupArchive.parse(await from.exportToJson()), ImportMode.merge);

      expect(await to.runs.loadTrace(mine.id), hasLength(30));
    });

    test('unions progress and leaves this device\'s settings alone', () async {
      final from = await seed(
        source,
        profile: const Profile(
          callsign: 'MOLLY',
          weightKg: 61,
          units: UnitSystem.imperial,
          completedMissions: {'sp01', 'sp02'},
          unlockedCodex: {'cdx_ninsei'},
          missionAttempts: {'sp03': 5},
        ),
      );
      final to = await seed(
        target,
        profile: const Profile(
          callsign: 'CASE',
          weightKg: 80,
          completedMissions: {'sp01'},
          unlockedCodex: {'cdx_turing'},
          missionAttempts: {'sp03': 2},
        ),
      );

      final report = await to.import(BackupArchive.parse(await from.exportToJson()), ImportMode.merge);

      final merged = await to.profiles.load();
      expect(merged.callsign, 'CASE', reason: 'settings belong to this device');
      expect(merged.weightKg, 80);
      expect(merged.units, UnitSystem.metric);
      expect(merged.completedMissions, {'sp01', 'sp02'});
      expect(merged.unlockedCodex, {'cdx_ninsei', 'cdx_turing'});
      expect(merged.missionAttempts['sp03'], 5, reason: 'the higher attempt count is the true one');
      expect(report.missionsAdded, 1);
      expect(report.codexAdded, 1);
    });

    test('an achievement keeps the earliest unlock date', () async {
      final early = DateTime(2026, 3, 1);
      final late = DateTime(2026, 7, 1);
      final from = await seed(
        source,
        profile: const Profile().copyWith(unlockedAchievements: {'dist_5k': early}),
      );
      final to = await seed(
        target,
        profile: const Profile().copyWith(unlockedAchievements: {'dist_5k': late, 'streak_4': late}),
      );

      await to.import(BackupArchive.parse(await from.exportToJson()), ImportMode.merge);

      final merged = await to.profiles.load();
      expect(merged.unlockedAchievements['dist_5k'], early);
      expect(merged.unlockedAchievements['streak_4'], late);
    });

    test('merging an older backup cannot relock a mission', () async {
      final from = await seed(source, profile: const Profile(completedMissions: {'sp01'}));
      final to = await seed(target, profile: const Profile(completedMissions: {'sp01', 'sp02', 'sp03'}));

      await to.import(BackupArchive.parse(await from.exportToJson()), ImportMode.merge);

      expect((await to.profiles.load()).completedMissions, {'sp01', 'sp02', 'sp03'});
    });
  });

  test('the suggested filename sorts chronologically', () {
    expect(
      BackupService.suggestedFileName(DateTime(2026, 7, 4, 9, 5)),
      'sprawlrun-backup-2026-07-04-0905.json',
    );
  });
}
