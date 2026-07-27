import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/models/achievement.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/stats.dart';
import 'package:sprawl_run/services/achievement_engine.dart';
import 'package:sprawl_run/services/stats_service.dart';

import 'support/fakes.dart';

void main() {
  group('catalogue integrity', () {
    test('ids are unique', () {
      final ids = kAchievements.map((a) => a.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('every entry is presentable and reachable', () {
      for (final a in kAchievements) {
        expect(a.title, isNotEmpty, reason: a.id);
        expect(a.description, isNotEmpty, reason: a.id);
        expect(a.target, greaterThan(0), reason: a.id);
        expect(a.format(a.target), isNotEmpty, reason: a.id);
      }
    });

    test('nothing is earned on a fresh install', () {
      expect(AchievementEngine.earnedCount(LifetimeStats.empty), 0);
    });

    test('there are plenty of them, across every category', () {
      expect(kAchievements.length, greaterThanOrEqualTo(40));
      for (final category in AchCategory.values) {
        expect(
          kAchievements.where((a) => a.category == category),
          isNotEmpty,
          reason: '${category.label} has no achievements',
        );
      }
    });
  });

  group('earning', () {
    final now = DateTime(2026, 7, 22, 18);

    test('the first mission unlocks the first-mission achievement', () {
      final stats = StatsService.lifetime([run(at: now, missionId: 'sp01')], const StreakGoal());
      final fresh = AchievementEngine.newlyEarned(stats, const {});
      expect(fresh.map((a) => a.id), contains('mission_1'));
    });

    test('nothing is awarded twice', () {
      final stats = StatsService.lifetime([run(at: now, missionId: 'sp01')], const StreakGoal());
      final first = AchievementEngine.newlyEarned(stats, const {});
      final second = AchievementEngine.newlyEarned(stats, first.map((a) => a.id).toSet());
      expect(second, isEmpty);
    });

    test('distance tiers unlock in order as the kilometres add up', () {
      List<String> earnedAfter(double meters) {
        final stats = StatsService.lifetime(
          [run(at: now, meters: meters, seconds: meters / 3)],
          const StreakGoal(),
        );
        return AchievementEngine.newlyEarned(stats, const {}).map((a) => a.id).toList();
      }

      expect(earnedAfter(6000), contains('dist_5k'));
      expect(earnedAfter(6000), isNot(contains('dist_25k')));
      expect(earnedAfter(30000), containsAll(['dist_5k', 'dist_25k']));
      expect(earnedAfter(30000), isNot(contains('dist_50k')));
    });

    test('a pace record needs a run of at least 3 km', () {
      // 2 km at 4:00/km — very fast, but too short to qualify.
      final short = StatsService.lifetime([run(at: now, meters: 2000, seconds: 480)], const StreakGoal());
      expect(AchievementEngine.newlyEarned(short, const {}).map((a) => a.id), isNot(contains('pace_600')));

      // 4 km at 5:00/km.
      final long = StatsService.lifetime([run(at: now, meters: 4000, seconds: 1200)], const StreakGoal());
      final ids = AchievementEngine.newlyEarned(long, const {}).map((a) => a.id);
      expect(ids, containsAll(['pace_600', 'pace_530', 'pace_500']));
      expect(ids, isNot(contains('pace_430')));
    });

    test('a clean mission earns Untouched; being caught does not', () {
      final caught = StatsService.lifetime(
        [run(at: now, missionId: 'sp01', chasesTotal: 2, chasesEvaded: 1)],
        const StreakGoal(),
      );
      expect(AchievementEngine.newlyEarned(caught, const {}).map((a) => a.id), isNot(contains('perfect_1')));

      final clean = StatsService.lifetime(
        [run(at: now, missionId: 'sp01', chasesTotal: 2, chasesEvaded: 2)],
        const StreakGoal(),
      );
      expect(AchievementEngine.newlyEarned(clean, const {}).map((a) => a.id), contains('perfect_1'));
    });

    test('streak achievements follow the runner\'s own weekly goal', () {
      final runs = [
        for (var w = 0; w < 4; w++)
          run(at: DateTime(2026, 7, 20).subtract(Duration(days: 7 * w)).add(const Duration(hours: 9)), seconds: 2400),
      ];

      // 30 min/week: four weeks in a row clears streak_2 and streak_4.
      final easy = StatsService.lifetime(runs, const StreakGoal(target: 30));
      expect(AchievementEngine.newlyEarned(easy, const {}).map((a) => a.id), containsAll(['streak_2', 'streak_4']));

      // 120 min/week: the same runs meet nothing, so no streak at all.
      final hard = StatsService.lifetime(runs, const StreakGoal(target: 120));
      expect(AchievementEngine.newlyEarned(hard, const {}).map((a) => a.id), isNot(contains('streak_2')));
    });

    test('deleting the run that earned something un-earns it', () {
      final runs = [run(at: now, meters: 6000, seconds: 1800)];
      final withRun = StatsService.lifetime(runs, const StreakGoal());
      expect(kAchievements.firstWhere((a) => a.id == 'dist_5k').isEarned(withRun), isTrue);

      final without = StatsService.lifetime(const [], const StreakGoal());
      expect(kAchievements.firstWhere((a) => a.id == 'dist_5k').isEarned(without), isFalse);
    });
  });

  group('the wall', () {
    test('lists earned first, then the closest to falling', () {
      final stats = StatsService.lifetime(
        [run(at: DateTime(2026, 7, 22), meters: 6000, seconds: 1800)],
        const StreakGoal(),
      );
      final wall = AchievementEngine.wall(stats, const {});

      expect(wall, hasLength(kAchievements.length));
      final firstUnearned = wall.indexWhere((v) => !v.earned);
      expect(wall.take(firstUnearned).every((v) => v.earned), isTrue);

      final unearned = wall.skip(firstUnearned).toList();
      for (var i = 1; i < unearned.length; i++) {
        expect(unearned[i - 1].progress, greaterThanOrEqualTo(unearned[i].progress));
      }
    });

    test('progress labels read sensibly mid-way', () {
      final stats = StatsService.lifetime(
        [run(at: DateTime(2026, 7, 22), meters: 2500, seconds: 900)],
        const StreakGoal(),
      );
      final dist5k = kAchievements.firstWhere((a) => a.id == 'dist_5k');
      expect(dist5k.progressOf(stats), closeTo(0.5, 0.01));
      expect(dist5k.progressLabel(stats), '2.5 km / 5.0 km');
    });
  });
}
