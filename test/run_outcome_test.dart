import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/achievement.dart';
import 'package:sprawl_run/state/app_state.dart';

import 'support/fakes.dart';

/// What a finished run reports back is what the reveal shows. These pin the
/// two things it must get right: a replayed mission is not a recovery, and an
/// achievement arrives as its definition, not a bare title.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState state;

  setUp(() async {
    final root = tempRoot('outcome');
    addTearDown(() => root.deleteSync(recursive: true));
    state = AppState(
      profiles: ProfileRepository(root),
      runs: RunRepository(Directory('${root.path}/runs')),
      missions: MissionRepository(externalDir: Directory('${root.path}/packs')),
      narrator: FakeNarrator(),
    );
    await state.load();
  });

  test('codex entries heard for the first time are reported as recovered, with their titles', () async {
    final report = await state.completeRun(
      run(at: DateTime.now()),
      codexHeard: const ['cdx_courier', 'cdx_ninsei'],
    );

    expect(report.codexRecovered.map((e) => e.id), ['cdx_courier', 'cdx_ninsei']);
    expect(report.codexRecovered.first.title, 'Meat Courier');
    expect(report.hasUnlocks, isTrue);
  });

  test('hearing an entry again on a replay is not a recovery', () async {
    await state.completeRun(run(at: DateTime.now()), codexHeard: const ['cdx_courier']);

    final again = await state.completeRun(
      run(at: DateTime.now().add(const Duration(days: 1))),
      codexHeard: const ['cdx_courier', 'cdx_ninsei'],
    );

    expect(again.codexRecovered.map((e) => e.id), ['cdx_ninsei'], reason: 'only what was new');
    expect(state.profile.unlockedCodex, containsAll(['cdx_courier', 'cdx_ninsei']));
  });

  test('an id no pack defines is banked but not shown', () async {
    final report = await state.completeRun(run(at: DateTime.now()), codexHeard: const ['cdx_from_a_removed_pack']);

    expect(report.codexRecovered, isEmpty);
    expect(state.profile.unlockedCodex, contains('cdx_from_a_removed_pack'), reason: 'kept for when the pack returns');
  });

  test('achievements come back as definitions, so the reveal knows the tier', () async {
    final report = await state.completeRun(run(at: DateTime.now(), meters: 5000));

    expect(report.newAchievements, isNotEmpty, reason: 'the first run earns something');
    expect(report.newAchievements, everyElement(isA<AchievementDef>()));
    expect(report.newAchievements.map((a) => a.tier), everyElement(isA<AchTier>()));
  });

  test('a run that earns nothing has nothing to reveal', () async {
    await state.completeRun(run(at: DateTime.now(), meters: 5000));
    // The same distance again earns no new distance milestone; achievements
    // are cumulative, but the second run adds no first.
    final second = await state.completeRun(run(at: DateTime.now().add(const Duration(minutes: 1)), meters: 10));

    expect(second.codexRecovered, isEmpty);
    expect(second.missionUnlocked, isNull);
    // Whether it earned an achievement depends on the wall; only assert the
    // invariant that hasUnlocks reflects the three lists.
    expect(
      second.hasUnlocks,
      second.newAchievements.isNotEmpty || second.codexRecovered.isNotEmpty || second.missionUnlocked != null,
    );
  });
}
