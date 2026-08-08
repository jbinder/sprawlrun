import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/run_record.dart';

import 'support/fakes.dart';

/// Exactly what version 0.1.0 wrote to `profile.json`. Frozen on purpose: it
/// must keep loading no matter what later versions add. Do not regenerate it
/// from the current `Profile.toJson` — that would make the test tautological.
const _profileV1 = '''
{
  "callsign": "MOLLY",
  "weightKg": 61.0,
  "units": "imperial",
  "streakGoal": {"metric": "kilometres", "target": 25.0},
  "audioInterrupt": "duck",
  "voiceEnabled": true,
  "speechRate": 0.52,
  "sfxVolume": 0.9,
  "ambientBed": false,
  "chasesEnabled": true,
  "autoPause": true,
  "keepScreenOn": true,
  "completedMissions": ["sp01", "sp02", "sp03"],
  "unlockedAchievements": {"dist_5k": "2026-07-28T09:30:00.000", "streak_1": "2026-07-29T18:02:11.000"},
  "unlockedCodex": ["cdx_ninsei", "cdx_turing"],
  "missionAttempts": {"sp01": 1, "sp04": 3},
  "lastGoalByMission": {"sp04": {"type": "distance", "value": 5000.0}}
}
''';

/// Exactly what version 0.1.0 wrote to `runs/index.json`.
const _indexV1 = '''
[
  {
    "id": "1785000000000000",
    "startedAt": "2026-07-28T07:00:00.000",
    "endedAt": "2026-07-28T07:31:00.000",
    "elapsedSeconds": 1860.0,
    "movingSeconds": 1802.0,
    "distanceMeters": 5321.0,
    "calories": 372.5,
    "goal": {"type": "time", "value": 1800.0},
    "outcome": "success",
    "missionId": "sp01",
    "missionCodename": "DEAD DROP",
    "missionOrder": 1,
    "chasesTotal": 1,
    "chasesEvaded": 1,
    "beatsHeard": 6,
    "trace": []
  },
  {
    "id": "1784900000000000",
    "startedAt": "2026-07-27T18:12:00.000",
    "endedAt": "2026-07-27T18:34:00.000",
    "elapsedSeconds": 1320.0,
    "movingSeconds": 1290.0,
    "distanceMeters": 3980.0,
    "calories": 251.0,
    "goal": {"type": "distance", "value": 4000.0},
    "outcome": "failed",
    "chasesTotal": 0,
    "chasesEvaded": 0,
    "beatsHeard": 4,
    "trace": []
  }
]
''';

void main() {
  late Directory root;

  setUp(() => root = tempRoot('upgrade'));
  tearDown(() => root.deleteSync(recursive: true));

  group('reading what the previous version wrote', () {
    test('a 0.1.0 profile survives the upgrade intact', () async {
      File('${root.path}/profile.json').writeAsStringSync(_profileV1);

      final loaded = await ProfileRepository(root).load();

      expect(loaded.callsign, 'MOLLY');
      expect(loaded.weightKg, 61);
      expect(loaded.units, UnitSystem.imperial);
      expect(loaded.audioInterrupt, AudioInterrupt.duck);
      expect(loaded.streakGoal.metric, StreakMetric.kilometres);
      expect(loaded.streakGoal.target, 25);
      expect(loaded.completedMissions, {'sp01', 'sp02', 'sp03'});
      expect(loaded.unlockedCodex, {'cdx_ninsei', 'cdx_turing'});
      expect(loaded.unlockedAchievements, hasLength(2));
      expect(loaded.missionAttempts['sp04'], 3);
      expect(loaded.lastGoalByMission['sp04']!['value'], 5000.0);
    });

    test('a field added after 0.1.0 takes its default rather than failing', () async {
      File('${root.path}/profile.json').writeAsStringSync(_profileV1);
      expect((await ProfileRepository(root).load()).resumeMusic, isTrue);
    });

    test('a 0.1.0 run log survives the upgrade intact', () async {
      Directory('${root.path}/runs').createSync(recursive: true);
      File('${root.path}/runs/index.json').writeAsStringSync(_indexV1);

      final runs = await RunRepository(Directory('${root.path}/runs')).loadAll();

      expect(runs, hasLength(2));
      expect(runs.first.missionCodename, 'DEAD DROP');
      expect(runs.first.distanceMeters, 5321);
      expect(runs.first.movingSeconds, 1802);
      expect(runs.first.chasesEvaded, 1);
      expect(runs.last.outcome, RunOutcome.failed);
      expect(runs.last.isMission, isFalse);
    });

    test('an upgraded profile is rewritten in a form the old version still reads', () async {
      // A downgrade is not supported, but a half-applied update that rolls back
      // must not find a file it cannot parse.
      File('${root.path}/profile.json').writeAsStringSync(_profileV1);
      final repo = ProfileRepository(root);
      await repo.save((await repo.load()).copyWith(callsign: 'CASE'));

      final raw = jsonDecode(File('${root.path}/profile.json').readAsStringSync()) as Map;
      for (final key in (jsonDecode(_profileV1) as Map).keys) {
        expect(raw.containsKey(key), isTrue, reason: '0.1.0 read "$key" and would now find it missing');
      }
    });
  });

  group('a write that is cut short', () {
    test('leaves the previous run log readable', () async {
      final runs = RunRepository(Directory('${root.path}/runs'));
      await runs.save(run(at: DateTime(2026, 7, 20)));
      await runs.save(run(at: DateTime(2026, 7, 22)));

      // What a kill mid-write used to leave behind: the file truncated to
      // nothing, because writeAsString truncates before it streams.
      final index = File('${root.path}/runs/index.json');
      final good = index.readAsStringSync();
      index.writeAsStringSync(good.substring(0, good.length ~/ 2));

      final reloaded = await RunRepository(Directory('${root.path}/runs')).loadAll();
      expect(reloaded, isEmpty, reason: 'a torn file cannot be parsed');

      // The point of the guarantee: the damaged bytes are kept rather than
      // overwritten by the next save.
      final kept = Directory('${root.path}/runs')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('corrupt'));
      expect(kept, hasLength(1));
      expect(kept.single.readAsStringSync(), good.substring(0, good.length ~/ 2));
    });

    test('never publishes a partial index in the first place', () async {
      final runs = RunRepository(Directory('${root.path}/runs'));
      await runs.save(run(at: DateTime(2026, 7, 20)));

      // The temp file the atomic swap goes through must not be left behind.
      final strays = Directory('${root.path}/runs')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp'));
      expect(strays, isEmpty);
    });

    test('a corrupt profile is kept, not silently replaced', () async {
      File('${root.path}/profile.json').writeAsStringSync('{"callsign": "MOL');

      final repo = ProfileRepository(root);
      expect((await repo.load()).callsign, 'RUNNER');
      await repo.save(const Profile(callsign: 'CASE'));

      final kept = root.listSync().whereType<File>().where((f) => f.path.contains('corrupt'));
      expect(kept, hasLength(1));
      expect(kept.single.readAsStringSync(), '{"callsign": "MOL');
    });
  });
}
