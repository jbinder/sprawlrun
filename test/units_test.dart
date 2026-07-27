import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/services/energy.dart';
import 'package:sprawl_run/services/geo.dart';
import 'package:sprawl_run/util/format.dart';

void main() {
  group('RunGoal', () {
    test('a time goal measures time and ignores distance', () {
      const goal = RunGoal(GoalType.time, 600);
      expect(goal.progress(elapsedSeconds: 300, distanceMeters: 99999), 0.5);
      expect(goal.isMet(elapsedSeconds: 599, distanceMeters: 0), isFalse);
      expect(goal.isMet(elapsedSeconds: 600, distanceMeters: 0), isTrue);
      expect(goal.remaining(elapsedSeconds: 450, distanceMeters: 0), 150);
    });

    test('a distance goal measures distance and ignores time', () {
      const goal = RunGoal(GoalType.distance, 5000);
      expect(goal.progress(elapsedSeconds: 99999, distanceMeters: 2500), 0.5);
      expect(goal.isMet(elapsedSeconds: 0, distanceMeters: 5000), isTrue);
    });

    test('progress never exceeds one, so the ring cannot overflow', () {
      const goal = RunGoal(GoalType.time, 60);
      expect(goal.progress(elapsedSeconds: 6000, distanceMeters: 0), 1.0);
      expect(goal.remaining(elapsedSeconds: 6000, distanceMeters: 0), 0);
    });

    test('round-trips through JSON', () {
      const goal = RunGoal(GoalType.distance, 4321);
      expect(RunGoal.fromJson(goal.toJson()), goal);
    });

    test('renders itself for the UI', () {
      expect(const RunGoal(GoalType.time, 1500).toString(), '25 min');
      expect(const RunGoal(GoalType.distance, 5000).toString(), '5.0 km');
    });
  });

  group('Geo', () {
    test('measures a known distance', () {
      // One degree of latitude is about 111.2 km.
      expect(Geo.distance(52.0, 13.0, 53.0, 13.0), closeTo(111195, 300));
    });

    test('is symmetric and zero for the same point', () {
      expect(Geo.distance(52.52, 13.4, 52.52, 13.4), 0);
      expect(
        Geo.distance(52.52, 13.4, 52.53, 13.41),
        closeTo(Geo.distance(52.53, 13.41, 52.52, 13.4), 0.001),
      );
    });

    test('longitude degrees shrink away from the equator', () {
      final atEquator = Geo.distance(0, 0, 0, 1);
      final atBerlin = Geo.distance(52.5, 13.0, 52.5, 14.0);
      expect(atBerlin, lessThan(atEquator * 0.65));
    });
  });

  group('Energy', () {
    test('burn scales with body mass', () {
      final light = Energy.kcal(distanceMeters: 5000, seconds: 1800, weightKg: 55);
      final heavy = Energy.kcal(distanceMeters: 5000, seconds: 1800, weightKg: 90);
      expect(heavy, greaterThan(light));
      expect(heavy / light, closeTo(90 / 55, 0.01));
    });

    test('a 5 km run in 30 minutes lands in the expected range', () {
      // ACSM puts a 72 kg runner at roughly 350-400 kcal for 5 km.
      final kcal = Energy.kcal(distanceMeters: 5000, seconds: 1800, weightKg: 72);
      expect(kcal, inInclusiveRange(320, 420));
    });

    test('running burns more per minute than walking', () {
      final walk = Energy.kcal(distanceMeters: 1500, seconds: 900, weightKg: 72);
      final runFast = Energy.kcal(distanceMeters: 3000, seconds: 900, weightKg: 72);
      expect(runFast, greaterThan(walk));
    });

    test('degenerate inputs return zero rather than NaN', () {
      expect(Energy.kcal(distanceMeters: 0, seconds: 0, weightKg: 72), 0);
      expect(Energy.kcal(distanceMeters: 100, seconds: 60, weightKg: 0), 0);
    });
  });

  group('Fmt', () {
    test('clock switches to hours only when needed', () {
      expect(Fmt.clock(0), '00:00');
      expect(Fmt.clock(65), '01:05');
      expect(Fmt.clock(3599), '59:59');
      expect(Fmt.clock(3600), '1:00:00');
      expect(Fmt.clock(3725), '1:02:05');
    });

    test('pace converts per unit and never renders :60', () {
      expect(Fmt.pace(360, UnitSystem.metric), '6:00');
      expect(Fmt.pace(0, UnitSystem.metric), '--:--');
      expect(Fmt.pace(359.6, UnitSystem.metric), '6:00');
      // 6:00/km is about 9:39/mile.
      expect(Fmt.pace(360, UnitSystem.imperial), '9:39');
    });

    test('distance changes precision with magnitude and unit', () {
      expect(Fmt.distance(5321, UnitSystem.metric), '5.32');
      expect(Fmt.distance(15321, UnitSystem.metric), '15.3');
      expect(Fmt.distance(1609.344, UnitSystem.imperial), '1.00');
    });

    test('groups long numbers for glanceability', () {
      expect(Fmt.grouped(950), '950');
      expect(Fmt.grouped(12345), '12 345');
    });

    test('short duration reads naturally either side of an hour', () {
      expect(Fmt.shortDuration(1800), '30m');
      expect(Fmt.shortDuration(4320), '1h 12m');
    });

    test('countdown degrades from days to minutes', () {
      expect(Fmt.countdown(const Duration(days: 3, hours: 4)), '3d 04h');
      expect(Fmt.countdown(const Duration(hours: 5, minutes: 9)), '5h 09m');
      expect(Fmt.countdown(const Duration(minutes: 40)), '40m');
      expect(Fmt.countdown(const Duration(seconds: -10)), '0h');
    });
  });
}
