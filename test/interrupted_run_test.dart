import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/active_run_store.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/state/app_state.dart';

import 'support/fakes.dart';

/// A run used to live only in memory until it was finished, and a runner lost
/// a whole one when the app was swiped away. The run in progress is now kept
/// on disk, and a run the app died in is offered back on the next launch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  setUp(() => root = tempRoot('interrupted'));
  tearDown(() => root.deleteSync(recursive: true));

  AppState newState() => AppState(
    profiles: ProfileRepository(root),
    runs: RunRepository(Directory('${root.path}/runs')),
    missions: MissionRepository(externalDir: Directory('${root.path}/packs')),
    narrator: FakeNarrator(),
  );

  ActiveRunSnapshot snapshot({String? missionId, RunOutcome outcome = RunOutcome.failed, DateTime? at}) =>
      ActiveRunSnapshot(
        record: run(at: at ?? DateTime(2026, 10, 4, 9), meters: 4200, seconds: 1880, outcome: outcome, missionId: missionId),
        codexHeard: const ['cdx_courier'],
      );

  group('the store', () {
    test('round-trips a run in progress, trace and all', () async {
      final store = ActiveRunStore(root);
      final saved = snapshot();
      await store.save(saved);

      final loaded = await store.load();
      expect(loaded!.record.id, saved.record.id);
      expect(loaded.record.distanceMeters, 4200);
      expect(loaded.codexHeard, ['cdx_courier']);
    });

    test('nothing saved means nothing to offer', () async {
      expect(await ActiveRunStore(root).load(), isNull);
    });

    test('an unreadable file is set aside, never deleted — it is someone\'s run', () async {
      final store = ActiveRunStore(root);
      store.file.writeAsStringSync('{"record": {"trunc');
      expect(await store.load(), isNull);
      expect(store.file.existsSync(), isFalse);
      expect(root.listSync().map((f) => f.path).where((p) => p.contains('active_run')), isNotEmpty,
          reason: 'quarantined beside it');
    });

    test('clearing for one run leaves a newer run\'s copy alone', () async {
      final store = ActiveRunStore(root);
      final older = snapshot(at: DateTime(2026, 10, 3, 9));
      await store.save(snapshot(at: DateTime(2026, 10, 4, 9)));

      await store.clearIf(older.record.id);
      expect(store.file.existsSync(), isTrue);
    });
  });

  group('on the next launch', () {
    test('a run left unfinished is offered back', () async {
      await ActiveRunStore(root).save(snapshot());
      final state = newState();
      await state.load();
      expect(state.interruptedRun?.record.distanceMeters, 4200);
    });

    test('keeping it records it as finishing would have — mission and intel included', () async {
      await ActiveRunStore(root).save(snapshot(missionId: 'sp01', outcome: RunOutcome.success));
      final state = newState();
      await state.load();

      final report = await state.keepInterruptedRun();

      expect(report, isNotNull);
      expect(state.runLog.single.distanceMeters, 4200);
      expect(state.profile.completedMissions, contains('sp01'));
      expect(state.profile.unlockedCodex, contains('cdx_courier'));
      expect(state.interruptedRun, isNull);
      expect(state.activeRun.file.existsSync(), isFalse);

      // And it does not come back on the launch after.
      final again = newState();
      await again.load();
      expect(again.interruptedRun, isNull);
    });

    test('a run that was recorded before the app died is not offered twice', () async {
      final saved = snapshot();
      await RunRepository(Directory('${root.path}/runs')).save(saved.record);
      await ActiveRunStore(root).save(saved);

      final state = newState();
      await state.load();
      expect(state.interruptedRun, isNull);
      expect(state.runLog, hasLength(1));
      expect(state.activeRun.file.existsSync(), isFalse);
    });

    test('discarding it records nothing', () async {
      await ActiveRunStore(root).save(snapshot());
      final state = newState();
      await state.load();

      await state.discardInterruptedRun();

      expect(state.runLog, isEmpty);
      expect(state.interruptedRun, isNull);
      expect(state.activeRun.file.existsSync(), isFalse);
    });

    test('deciding late never deletes the copy of a run started since', () async {
      await ActiveRunStore(root).save(snapshot(at: DateTime(2026, 10, 3, 9)));
      final state = newState();
      await state.load();

      // A new run starts before the old one is dealt with, and saves over it.
      await state.activeRun.save(snapshot(at: DateTime(2026, 10, 4, 9)));
      await state.discardInterruptedRun();

      expect((await state.activeRun.load())?.record.startedAt, DateTime(2026, 10, 4, 9));
    });
  });
}
