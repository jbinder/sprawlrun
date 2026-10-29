import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/gpx_export.dart';
import 'package:sprawl_run/models/achievement.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/services/achievement_engine.dart';
import 'package:sprawl_run/services/stats_service.dart';

import 'support/fakes.dart';

/// Walking: the same missions and totals, its own achievements, no pace
/// records — and nothing changes for a runner who never chooses it.
void main() {
  final monday = DateTime(2026, 10, 26, 7);
  DateTime day(int n) => monday.add(Duration(days: n));

  test('a record keeps being a walk, and one from before walking is a run', () {
    final walk = run(at: monday, activity: Activity.walk);
    expect(RunRecord.fromJson(walk.toJson()).activity, Activity.walk);
    expect(run(at: monday).toJson().containsKey('activity'), isFalse, reason: 'a run is written as it always was');
    expect(RunRecord.fromJson(run(at: monday).toJson()).activity, Activity.run);
    expect(Activity.parse('hovercraft'), Activity.run, reason: 'a newer build\'s activity reads as a run');
  });

  test('the briefing remembers what was chosen last, and starts as a run', () {
    expect(const Profile().lastActivity, Activity.run);
    final walker = const Profile().copyWith(lastActivity: Activity.walk);
    expect(Profile.fromJson(walker.toJson()).lastActivity, Activity.walk);
    expect(Profile.fromJson(const Profile().toJson()..remove('lastActivity')).lastActivity, Activity.run);
  });

  test('walks count for the totals and the streak, but set no pace record', () {
    final log = [
      run(at: day(0), meters: 5000, seconds: 1800),
      run(at: day(1), meters: 5000, seconds: 1200, activity: Activity.walk), // impossibly quick, to be sure
    ];
    final stats = StatsService.lifetime(log, const StreakGoal());
    expect(stats.totalRuns, 2);
    expect(stats.totalDistanceMeters, 10000);
    expect(stats.bestPaceSecondsPerKm, closeTo(360, 0.1), reason: 'the run\'s, not the walk\'s');
    expect(stats.walks, 1);
    expect(stats.walkedMeters, 5000);

    final walkedWeek = StatsService.streak([run(at: day(1), activity: Activity.walk)], const StreakGoal());
    expect(walkedWeek.currentValue, greaterThan(0), reason: 'a walk moves the weekly target');
  });

  test('walks earn the walking achievements and nothing else', () {
    final log = [
      for (var i = 0; i < 3; i++) run(at: day(i), meters: 12000, seconds: 7200, activity: Activity.walk),
    ];
    final stats = StatsService.forAchievements(log, const StreakGoal());
    final earned = AchievementEngine.newlyEarned(stats, const {}).map((a) => a.id).toSet();
    expect(earned, containsAll(['walk_first', 'walk_10k']));
    expect(earned.where((id) => !id.startsWith('walk_')), isEmpty, reason: 'not dist_25k, not single_10k, not a streak');
  });

  test('a runner\'s wall is unchanged by the walking ladder\'s arrival', () {
    final log = [for (var i = 0; i < 5; i++) run(at: day(i), meters: 6000, seconds: 1900)];
    expect(
      StatsService.forAchievements(log, const StreakGoal()).totalDistanceMeters,
      StatsService.lifetime(log, const StreakGoal()).totalDistanceMeters,
    );
    final earned = AchievementEngine.newlyEarned(StatsService.forAchievements(log, const StreakGoal()), const {});
    expect(earned.where((a) => a.category == AchCategory.walking), isEmpty);
  });

  test('walking achievements are dated to the walk that earned them', () {
    final log = [
      run(at: day(0), meters: 4000, seconds: 2800, activity: Activity.walk),
      run(at: day(2), meters: 7000, seconds: 4800, activity: Activity.walk),
    ];
    final dates = AchievementEngine.backfill(log, const StreakGoal(), const {});
    expect(dates['walk_first'], log[0].endedAt);
    expect(dates['walk_10k'], log[1].endedAt);
  });

  test('a walk exports to GPX as a walk', () {
    final walk = run(at: monday, activity: Activity.walk);
    expect(GpxExport.of(walk, const []), contains('<type>walking</type>'));
    expect(GpxExport.of(run(at: monday), const []), contains('<type>running</type>'));
  });
}
