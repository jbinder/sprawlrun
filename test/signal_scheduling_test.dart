import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/services/signal_planner.dart';
import 'package:sprawl_run/services/signal_scheduler.dart';
import 'package:sprawl_run/state/app_state.dart';

import 'support/fakes.dart';

/// Whether the app actually asks the platform to send anything, as opposed to
/// whether the plan is right — that is `signal_planner_test.dart`.
void main() {
  late List<List<PlannedSignal>> scheduled;
  late int cancels;

  SignalScheduler recording() => SignalScheduler(
    schedule: (signals) async => scheduled.add(signals),
    cancelAll: () async => cancels++,
  );

  Future<AppState> boot({Profile? profile}) async {
    final root = tempRoot('signals');
    addTearDown(() => root.deleteSync(recursive: true));
    final profiles = ProfileRepository(root);
    if (profile != null) await profiles.save(profile);

    final state = AppState(
      profiles: profiles,
      runs: RunRepository(Directory('${root.path}/runs')),
      missions: MissionRepository(externalDir: Directory('${root.path}/packs'), bundle: _DiskBundle()),
      narrator: FakeNarrator(),
      signals: recording(),
    );
    await state.load();
    return state;
  }

  setUp(() {
    scheduled = [];
    cancels = 0;
  });

  test('a runner who has not asked for reminders is never scheduled anything', () async {
    await boot();
    expect(scheduled, isEmpty);
    expect(cancels, 1, reason: 'and anything left over from before is cleared');
  });

  test('switching reminders on schedules the week', () async {
    final state = await boot();
    await state.updateProfile(
      state.profile.copyWith(signals: const SignalSettings(remindersEnabled: true)),
    );

    expect(scheduled, hasLength(1));
    expect(scheduled.single, isNotEmpty, reason: 'the bundled packs carry generic reminders');
    expect(
      scheduled.single.every((s) => s.kind == SignalKind.reminder),
      isTrue,
      reason: 'ambient is not part of this stage',
    );
  });

  test('switching them off again clears the schedule', () async {
    final state = await boot(profile: const Profile(signals: SignalSettings(remindersEnabled: true)));
    scheduled.clear();
    cancels = 0;

    await state.updateProfile(
      state.profile.copyWith(signals: state.profile.signals.copyWith(remindersEnabled: false)),
    );

    expect(scheduled, isEmpty);
    expect(cancels, 1);
  });

  test('finishing a run re-plans, so today is not asked about again', () async {
    final state = await boot(profile: const Profile(signals: SignalSettings(remindersEnabled: true)));
    scheduled.clear();

    await state.completeRun(run(at: DateTime.now(), meters: 5000, seconds: 1800));

    expect(scheduled, hasLength(1), reason: 'the plan is rebuilt after every run');
    expect(
      scheduled.single.any((s) => s.at.day == DateTime.now().day),
      isFalse,
      reason: 'already been out today',
    );
  });
}

/// Reads the bundled packs straight off disk: a plain unit test has no asset
/// bundle, and without the packs there is no signal copy to schedule.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = File(key).readAsBytesSync();
    return ByteData.view(bytes.buffer);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async => File(key).readAsStringSync();
}
