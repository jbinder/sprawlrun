import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/run_record.dart';

import 'support/fakes.dart';

void main() {
  group('RunRepository', () {
    late Directory root;
    late RunRepository repo;

    setUp(() {
      root = tempRoot('runs');
      repo = RunRepository(root);
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('an empty store reads as empty, not as an error', () async {
      expect(await repo.loadAll(), isEmpty);
    });

    test('saves and reloads a run from disk', () async {
      final record = run(at: DateTime(2026, 7, 22, 8), meters: 5321, seconds: 1834);
      await repo.save(record);

      // A fresh repository, so this genuinely comes back off disk.
      final reloaded = await RunRepository(root).loadAll();
      expect(reloaded, hasLength(1));
      expect(reloaded.single.distanceMeters, 5321);
      expect(reloaded.single.elapsedSeconds, 1834);
      expect(reloaded.single.outcome, RunOutcome.success);
    });

    test('returns runs newest first', () async {
      await repo.save(run(at: DateTime(2026, 7, 20)));
      await repo.save(run(at: DateTime(2026, 7, 22)));
      await repo.save(run(at: DateTime(2026, 7, 21)));

      final all = await RunRepository(root).loadAll();
      expect(all.map((r) => r.startedAt.day), [22, 21, 20]);
    });

    test('the index stays small; traces live in their own files', () async {
      final trace = [
        for (var i = 0; i < 500; i++)
          TracePoint(lat: 52.52 + i * 0.0001, lon: 13.40, elapsedSeconds: i.toDouble()),
      ];
      final record = RunRecord(
        id: 'r1',
        startedAt: DateTime(2026, 7, 22),
        endedAt: DateTime(2026, 7, 22, 0, 30),
        elapsedSeconds: 1800,
        movingSeconds: 1750,
        distanceMeters: 5000,
        calories: 350,
        goal: const RunGoal(GoalType.time, 1800),
        outcome: RunOutcome.success,
        trace: trace,
      );
      await repo.save(record);

      final indexed = jsonDecode(File('${root.path}/index.json').readAsStringSync()) as List;
      expect((indexed.single as Map)['trace'], isEmpty, reason: 'the index must not carry trace points');

      final loaded = await RunRepository(root).loadAll();
      expect(loaded.single.trace, isEmpty, reason: 'traces load lazily');
      expect(await repo.loadTrace('r1'), hasLength(500));
    });

    test('deleting a run removes it and its trace', () async {
      final record = RunRecord(
        id: 'r1',
        startedAt: DateTime(2026, 7, 22),
        endedAt: DateTime(2026, 7, 22),
        elapsedSeconds: 600,
        movingSeconds: 600,
        distanceMeters: 2000,
        calories: 120,
        goal: const RunGoal(GoalType.time, 600),
        outcome: RunOutcome.success,
        trace: const [TracePoint(lat: 1, lon: 2, elapsedSeconds: 0)],
      );
      await repo.save(record);
      await repo.delete('r1');

      expect(await RunRepository(root).loadAll(), isEmpty);
      expect(await repo.loadTrace('r1'), isEmpty);
    });

    test('saving the same id twice replaces rather than duplicates', () async {
      final first = run(at: DateTime(2026, 7, 22), meters: 1000);
      await repo.save(first);
      await repo.save(first.copyWith(outcome: RunOutcome.failed));

      final all = await RunRepository(root).loadAll();
      expect(all, hasLength(1));
      expect(all.single.outcome, RunOutcome.failed);
    });

    test('a corrupt index degrades to empty instead of crashing the app', () async {
      File('${root.path}/index.json').writeAsStringSync('{not json at all');
      expect(await RunRepository(root).loadAll(), isEmpty);
    });
  });

  group('ProfileRepository', () {
    late Directory root;

    setUp(() => root = tempRoot('profile'));
    tearDown(() => root.deleteSync(recursive: true));

    test('an absent profile reads as the defaults', () async {
      final profile = await ProfileRepository(root).load();
      expect(profile.callsign, 'RUNNER');
      expect(profile.streakGoal.target, 30);
      expect(profile.audioInterrupt, AudioInterrupt.pause);
    });

    test('round-trips settings and progress', () async {
      final unlockedAt = DateTime(2026, 7, 22, 9, 30);
      await ProfileRepository(root).save(
        const Profile(
          callsign: 'MOLLY',
          weightKg: 61,
          units: UnitSystem.imperial,
          streakGoal: StreakGoal(metric: StreakMetric.kilometres, target: 25),
          audioInterrupt: AudioInterrupt.duck,
          resumeMusic: false,
          completedMissions: {'sp01', 'sp02'},
          unlockedCodex: {'cdx_ninsei'},
          missionAttempts: {'sp03': 2},
        ).copyWith(unlockedAchievements: {'dist_5k': unlockedAt}),
      );

      final loaded = await ProfileRepository(root).load();
      expect(loaded.callsign, 'MOLLY');
      expect(loaded.weightKg, 61);
      expect(loaded.units, UnitSystem.imperial);
      expect(loaded.streakGoal.metric, StreakMetric.kilometres);
      expect(loaded.streakGoal.target, 25);
      expect(loaded.audioInterrupt, AudioInterrupt.duck);
      expect(loaded.resumeMusic, isFalse);
      expect(loaded.completedMissions, {'sp01', 'sp02'});
      expect(loaded.unlockedCodex, {'cdx_ninsei'});
      expect(loaded.missionAttempts['sp03'], 2);
      expect(loaded.unlockedAchievements['dist_5k'], unlockedAt);
    });

    test('a corrupt profile falls back to defaults rather than blocking launch', () async {
      File('${root.path}/profile.json').writeAsStringSync(']]not json[[');
      expect((await ProfileRepository(root).load()).callsign, 'RUNNER');
    });
  });

  group('MissionRepository', () {
    late Directory external;

    setUp(() => external = tempRoot('packs'));
    tearDown(() => external.deleteSync(recursive: true));

    /// Serves the bundled campaign from disk so the test needs no asset bundle.
    AssetBundle diskBundle() => _DiskBundle();

    test('loads the bundled campaign', () async {
      final repo = MissionRepository(externalDir: external, bundle: diskBundle());
      final packs = await repo.loadPacks();
      expect(packs, hasLength(1));
      expect(packs.single.id, 'sprawl_prime');
      expect(packs.single.missions, hasLength(10));
      expect(repo.loadErrors, isEmpty);
    });

    test('picks up a side-loaded pack without an app update', () async {
      File('${external.path}/extra.json').writeAsStringSync(
        jsonEncode({
          'id': 'extra_pack',
          'title': 'CHIBA NIGHTS',
          'tagline': 'more',
          'missions': [
            {
              'id': 'x1',
              'order': 1,
              'codename': 'X ONE',
              'title': 'Extra One',
              'suggestedGoal': {'type': 'time', 'value': 900},
              'beats': [
                {
                  'id': 'x1b0',
                  'at': {'fraction': 0.0},
                  'lines': [
                    {'speaker': 'KESTREL', 'text': 'hello'},
                  ],
                },
              ],
            },
          ],
        }),
      );

      final repo = MissionRepository(externalDir: external, bundle: diskBundle());
      final packs = await repo.loadPacks();
      expect(packs, hasLength(2));
      expect(packs.last.title, 'CHIBA NIGHTS');
      expect((await repo.allMissions()), hasLength(11));
    });

    test('a malformed side-loaded pack is reported, not fatal', () async {
      File('${external.path}/broken.json').writeAsStringSync('{ oh dear');
      final repo = MissionRepository(externalDir: external, bundle: diskBundle());

      final packs = await repo.loadPacks();
      expect(packs, hasLength(1), reason: 'the bundled campaign still loads');
      expect(repo.loadErrors, hasLength(1));
      expect(repo.loadErrors.single, contains('broken.json'));
    });

    test('a side-loaded pack can replace a bundled one by id', () async {
      File('${external.path}/override.json').writeAsStringSync(
        jsonEncode({'id': 'sprawl_prime', 'title': 'REVISED', 'missions': []}),
      );
      final packs = await MissionRepository(externalDir: external, bundle: diskBundle()).loadPacks();
      expect(packs, hasLength(1));
      expect(packs.single.title, 'REVISED');
    });
  });

  group('mission chain', () {
    Future<List<dynamic>> chainFor(Set<String> completed) async {
      final missions = await MissionRepository(
        externalDir: tempRoot('chain'),
        bundle: _DiskBundle(),
      ).allMissions();
      return resolveChain(missions, completed, const {});
    }

    test('only the first mission is playable on a fresh install', () async {
      final chain = (await chainFor({})).cast<MissionProgress>();
      expect(chain.first.state, MissionState.available);
      expect(chain.skip(1).every((m) => m.state == MissionState.locked), isTrue);
    });

    test('clearing a mission unlocks exactly the next one', () async {
      final chain = (await chainFor({'sp01', 'sp02'})).cast<MissionProgress>();
      expect(chain[0].state, MissionState.completed);
      expect(chain[1].state, MissionState.completed);
      expect(chain[2].state, MissionState.available);
      expect(chain[3].state, MissionState.locked);
    });

    test('a gap in progress does not open later missions', () async {
      // sp03 cleared but sp02 not: the chain still stops at sp02.
      final chain = (await chainFor({'sp01', 'sp03'})).cast<MissionProgress>();
      expect(chain[1].state, MissionState.available);
      expect(chain[2].state, MissionState.completed);
      expect(chain[3].state, MissionState.locked);
    });

    test('a finished campaign leaves nothing available', () async {
      final all = {for (var i = 1; i <= 10; i++) 'sp${i.toString().padLeft(2, '0')}'};
      final chain = (await chainFor(all)).cast<MissionProgress>();
      expect(chain.every((m) => m.state == MissionState.completed), isTrue);
    });
  });
}

/// Reads bundled assets straight off the filesystem, so repository tests do not
/// depend on a Flutter asset bundle being wired up.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = File(key).readAsBytesSync();
    return ByteData.view(bytes.buffer);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async => File(key).readAsStringSync();
}
