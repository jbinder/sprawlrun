import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/migrations.dart';
import 'package:sprawl_run/models/profile.dart';

import 'support/fakes.dart';

void main() {
  final march = DateTime(2026, 3, 2, 7);
  const length = Duration(seconds: 2000);
  final log = [
    for (var i = 0; i < 3; i++) run(at: march.add(Duration(days: 7 * i)), meters: 6000, seconds: 2000),
  ];
  DateTime endOf(int index) => march.add(Duration(days: 7 * index) + length);

  test('a profile already at the current version is left alone', () {
    const current = Profile(dataVersion: Migrations.current);
    expect(Migrations.apply(current, log), isNull);
  });

  test('an unversioned profile is brought to the current version', () {
    const old = Profile();
    expect(old.dataVersion, 0, reason: 'anything written before migrations existed');
    expect(Migrations.apply(old, log)!.dataVersion, Migrations.current);
  });

  test('a fresh install with no history still lands on the current version', () {
    expect(Migrations.apply(const Profile(), const [])!.dataVersion, Migrations.current);
  });

  group('v1 — achievement unlock dates', () {
    test('moves dates credited to the wrong run back to the run that earned them', () {
      // The shape of the bug: a catalogue addition stamped everything with
      // whatever run came next.
      final sweptUp = Profile(
        unlockedAchievements: {
          for (final id in ['dist_5k', 'single_30m', 'time_1h']) id: endOf(2),
        },
      );

      final fixed = Migrations.apply(sweptUp, log)!;
      expect(fixed.unlockedAchievements['dist_5k'], endOf(0));
      expect(fixed.unlockedAchievements['time_1h'], endOf(1));
      expect(fixed.dataVersion, Migrations.current);
    });

    test('leaves everything else on the profile untouched', () {
      final before = Profile(
        callsign: 'MOLLY',
        weightKg: 68,
        completedMissions: const {'sp01'},
        unlockedCodex: const {'cdx_courier'},
        unlockedAchievements: {'dist_5k': endOf(2)},
      );
      final after = Migrations.apply(before, log)!;

      expect(after.callsign, 'MOLLY');
      expect(after.weightKg, 68);
      expect(after.completedMissions, before.completedMissions);
      expect(after.unlockedCodex, before.unlockedCodex);
    });

    test('running it twice changes nothing the second time', () {
      final once = Migrations.apply(const Profile(), log)!;
      expect(Migrations.apply(once, log), isNull, reason: 'already at the current version');

      // And re-running the step itself is harmless, which is what matters if
      // the app dies between migrating and saving.
      final again = Migrations.apply(once.copyWith(dataVersion: 0), log)!;
      expect(again.unlockedAchievements, once.unlockedAchievements);
    });
  });
}
