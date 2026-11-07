import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/audio/song.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/services/music_director.dart';

void main() {
  const usual = 3.0;

  /// Runs [seconds] at [speed], returning every change asked for along the way.
  List<MusicCue> run(MusicDirector d, int seconds, double speed) => [
    for (var i = 0; i < seconds; i++) ?d.tick(speed),
  ];

  MusicDirector director() => MusicDirector(usualSpeed: usual);

  group('pace', () {
    test('the usual pace leaves the song as written', () {
      expect(run(director(), 300, usual), isEmpty);
    });

    test('easing off well below it thins the song out', () {
      final cues = run(director(), 60, usual * 0.6);
      expect(cues.single.level, MusicLevel.low);
      expect(cues.single.atOnce, isFalse);
    });

    test('a slower stretch is not enough: a climb keeps its music', () {
      expect(run(director(), 300, usual * 0.8), isEmpty);
    });

    test('pushing past it lifts the song', () {
      expect(run(director(), 60, usual * 1.2).single.level, MusicLevel.high);
    });

    test('nothing is judged on a few seconds', () {
      expect(run(director(), MusicDirector.minimumSeconds - 1, usual * 0.5), isEmpty);
    });

    test('a burst inside a steady run changes nothing', () {
      final d = director();
      run(d, 60, usual);
      expect(run(d, 5, usual * 1.5), isEmpty);
      expect(run(d, 60, usual), isEmpty);
    });

    test('hovering on a threshold does not flip the song back and forth', () {
      final d = director();
      expect(run(d, 60, usual * 1.2).single.level, MusicLevel.high);
      // Below where it rose, above where it falls.
      expect(run(d, 120, usual * 1.08), isEmpty);
      expect(run(d, 60, usual).single.level, MusicLevel.normal);
    });

    test('with no history to go by, pace changes nothing', () {
      final d = MusicDirector(usualSpeed: null);
      expect(run(d, 120, 1), isEmpty);
      expect(run(d, 120, 6), isEmpty);
      expect(run(d, 120, 0), isEmpty);
    });
  });

  group('stopping', () {
    test('a traffic light does not strip the song', () {
      final d = director();
      run(d, 60, usual);
      expect(run(d, 45, 0), isEmpty);
      expect(run(d, 60, usual), isEmpty);
    });

    test('a real stop thins it out, and running again brings it back', () {
      final d = director();
      run(d, 60, usual);
      expect(run(d, 70, 0).single.level, MusicLevel.low);
      expect(run(d, 60, usual).single.level, MusicLevel.normal);
    });
  });

  group('with no reading of the speed', () {
    test('the level holds, however long it lasts', () {
      final d = director();
      run(d, 60, usual * 1.2);
      expect([for (var i = 0; i < 300; i++) ?d.tick(null)], isEmpty);
    });

    test('the goal\'s lift still ends', () {
      final d = director();
      run(d, 60, usual);
      d.goalReached();
      final after = [for (var i = 0; i < MusicDirector.goalLiftSeconds; i++) ?d.tick(null)];
      expect(after.single.level, MusicLevel.normal);
    });
  });

  group('chases', () {
    test('a chase lifts the song at once, and lets go at the next phrase', () {
      final d = director();
      final start = d.setChasing(true)!;
      expect((start.level, start.atOnce), (MusicLevel.high, true));
      expect(run(d, 120, usual * 0.5), isEmpty, reason: 'pace does not interrupt a chase');

      final end = d.setChasing(false)!;
      expect((end.level, end.atOnce), (MusicLevel.low, false));
    });

    test('a chase ending at the usual pace returns to the song as written', () {
      final d = director();
      d.setChasing(true);
      run(d, 30, usual);
      expect(d.setChasing(false)!.level, MusicLevel.normal);
    });
  });

  group('the goal', () {
    test('gives one lift, and the song carries on', () {
      final d = director();
      run(d, 60, usual);
      final lift = d.goalReached()!;
      expect((lift.level, lift.atOnce), (MusicLevel.high, true));
      final after = run(d, MusicDirector.goalLiftSeconds, usual);
      expect(after.single.level, MusicLevel.normal);
      expect(run(d, 120, usual), isEmpty);
    });

    test('reached during a chase, the chase keeps the song up', () {
      final d = director();
      d.setChasing(true);
      expect(d.goalReached(), isNull);
      expect(run(d, MusicDirector.goalLiftSeconds + 5, usual), isEmpty);
    });
  });

  group('usual speed', () {
    final day = DateTime(2026, 10, 1);
    RunRecord record(
      int n, {
      double meters = 5000,
      double seconds = 1800,
      Activity activity = Activity.run,
      double estimated = 0,
    }) => RunRecord(
      id: 'r$n',
      startedAt: day.add(Duration(days: n)),
      endedAt: day.add(Duration(days: n, seconds: seconds.round())),
      elapsedSeconds: seconds,
      movingSeconds: seconds,
      distanceMeters: meters,
      calories: 0,
      goal: const RunGoal(GoalType.time, 1800),
      outcome: RunOutcome.success,
      activity: activity,
      estimatedMeters: estimated,
    );

    test('needs a few runs to go by', () {
      expect(MusicDirector.usualSpeedOf([record(1), record(2)], Activity.run), isNull);
      expect(MusicDirector.usualSpeedOf([record(1), record(2), record(3)], Activity.run), closeTo(5000 / 1800, 0.001));
    });

    test('one odd run moves it very little', () {
      final log = [record(1), record(2), record(3), record(4, meters: 12000)];
      expect(MusicDirector.usualSpeedOf(log, Activity.run), lessThan(3));
    });

    test('runs and walks are judged apart', () {
      final log = [
        for (var i = 0; i < 3; i++) record(i),
        for (var i = 3; i < 6; i++) record(i, meters: 2000, activity: Activity.walk),
      ];
      expect(MusicDirector.usualSpeedOf(log, Activity.walk), closeTo(2000 / 1800, 0.001));
      expect(MusicDirector.usualSpeedOf(log, Activity.run), closeTo(5000 / 1800, 0.001));
    });

    test('short runs and estimated distance do not count', () {
      final log = [
        record(1),
        record(2),
        record(3, meters: 100),
        record(4, seconds: 60),
        record(5, estimated: 4000),
      ];
      expect(MusicDirector.usualSpeedOf(log, Activity.run), isNull);
    });

    test('only recent runs count', () {
      final log = [
        for (var i = 0; i < 10; i++) record(i, meters: 3000),
        for (var i = 10; i < 20; i++) record(i, meters: 6000),
      ];
      expect(MusicDirector.usualSpeedOf(log, Activity.run), closeTo(6000 / 1800, 0.001));
    });
  });
}
