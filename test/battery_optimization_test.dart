import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/services/battery_optimization.dart';
import 'package:sprawl_run/state/app_state.dart';

import 'support/fakes.dart';

/// A vendor battery manager killed a run in its foreground service at 4.6 of
/// 5 km. The app now asks, once before a run, to be left out of battery
/// optimisation, and Settings shows where things stand.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  setUp(() => root = tempRoot('battery'));
  tearDown(() => root.deleteSync(recursive: true));

  /// Android, as far as these tests need it: optimised until the dialog is
  /// answered with [grant].
  ({AppState state, List<String> calls}) withPhone({bool optimized = true, bool grant = true}) {
    var on = optimized;
    final calls = <String>[];
    final state = AppState(
      profiles: ProfileRepository(root),
      runs: RunRepository(Directory('${root.path}/runs')),
      missions: MissionRepository(externalDir: Directory('${root.path}/packs')),
      narrator: FakeNarrator(),
      battery: BatteryOptimization(
        optimized: () async => on,
        requestExemption: () async {
          calls.add('dialog');
          if (grant) on = false;
          return !on;
        },
      ),
    );
    return (state: state, calls: calls);
  }

  test('an optimised phone is asked once; allowing it is remembered', () async {
    final (:state, :calls) = withPhone();
    await state.load();
    expect(state.shouldAskBatteryExemption, isTrue);

    await state.requestBatteryExemption();
    expect(calls, ['dialog']);
    expect(state.batteryOptimized, isFalse);
    expect(state.shouldAskBatteryExemption, isFalse);
    expect(state.profile.batteryAsked, isTrue);
  });

  test('declining in Android\'s dialog is not asked again before a run, but Settings still says so', () async {
    final (:state, :calls) = withPhone(grant: false);
    await state.load();
    await state.requestBatteryExemption();
    expect(calls, ['dialog']);
    expect(state.batteryOptimized, isTrue, reason: 'Settings shows the warning and its button');
    expect(state.shouldAskBatteryExemption, isFalse);
  });

  test('not now is remembered too', () async {
    final (:state, :calls) = withPhone();
    await state.load();
    await state.declineBatteryExemption();
    expect(calls, isEmpty);
    expect(state.shouldAskBatteryExemption, isFalse);
  });

  test('a phone that is not optimising the app is never asked', () async {
    final (:state, calls: _) = withPhone(optimized: false);
    await state.load();
    expect(state.shouldAskBatteryExemption, isFalse);
  });

  test('a profile from before the question starts unasked', () {
    expect(Profile.fromJson(const {'callsign': 'CASE'}).batteryAsked, isFalse);
    expect(Profile.fromJson(const Profile(batteryAsked: true).toJson()).batteryAsked, isTrue);
  });
}
