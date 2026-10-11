import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/services/stats_service.dart';

import 'support/fakes.dart';

/// Each week of a streak is judged against the target in force *that* week.
///
/// Every past week used to be re-judged against today's target, so raising it
/// once — to 135 min, by accident — showed a streak of 0 with every run still
/// in the log.
void main() {
  final wednesday = DateTime(2026, 7, 22, 18, 0);
  DateTime monday(int weeksAgo) => DateTime(2026, 7, 20).subtract(Duration(days: 7 * weeksAgo));
  final thisWeek = monday(0);

  // Four finished weeks of 40 minutes each, nothing yet this week.
  final fourWeeks = [for (var w = 1; w <= 4; w++) run(at: monday(w).add(const Duration(hours: 9)), seconds: 2400)];

  group('changing the target', () {
    test('raising it does not undo the weeks already earned', () {
      final profile = const Profile(streakGoal: StreakGoal(target: 30))
          .withStreakGoal(const StreakGoal(target: 135), thisWeek: thisWeek);

      final status = StatsService.streak(fourWeeks, profile.streakTargets, now: wednesday);
      expect(status.weeks, 4, reason: 'those weeks met 30 min, the target they had');
      expect(status.target, 135, reason: 'this week is measured against the new target');
      expect(status.recentWeeks.reversed.skip(1).take(4), everyElement(isTrue));

      // The old behaviour, for contrast: every week against 135.
      expect(StatsService.streak(fourWeeks, const StreakGoal(target: 135), now: wednesday).weeks, 0);
    });

    test('a week is judged against its own target, so a higher one can be missed', () {
      // Raised to 60 three weeks ago: those 40-minute weeks no longer met it.
      final profile = const Profile(streakGoal: StreakGoal(target: 30))
          .withStreakGoal(const StreakGoal(target: 60), thisWeek: monday(3));

      final status = StatsService.streak(fourWeeks, profile.streakTargets, now: wednesday);
      expect(status.weeks, 0, reason: 'last week missed 60 min');
      expect(status.longestWeeks, 1, reason: 'only the week before the change met its target');
    });

    test('changing the unit judges older weeks in the old unit', () {
      final profile = const Profile(streakGoal: StreakGoal(target: 30))
          .withStreakGoal(const StreakGoal(metric: StreakMetric.kilometres, target: 5), thisWeek: monday(1));
      final runs = [
        run(at: monday(2).add(const Duration(hours: 9)), seconds: 2400, meters: 2000), // 40 min, 2 km
        run(at: monday(1).add(const Duration(hours: 9)), seconds: 1200, meters: 6000), // 20 min, 6 km
      ];
      expect(StatsService.streak(runs, profile.streakTargets, now: wednesday).weeks, 2);
    });

    test('lifetime stats — and so the streak achievements — use the same rule', () {
      final profile = const Profile(streakGoal: StreakGoal(target: 30))
          .withStreakGoal(const StreakGoal(target: 135), thisWeek: thisWeek);
      final stats = StatsService.lifetime(fourWeeks, profile.streakTargets, now: wednesday);
      expect(stats.currentStreakWeeks, 4);
      expect(stats.longestStreakWeeks, 4);
    });
  });

  group('recording changes', () {
    test('the first change also records what applied before it', () {
      final p = const Profile(streakGoal: StreakGoal(target: 30))
          .withStreakGoal(const StreakGoal(target: 45), thisWeek: thisWeek);
      expect(p.streakGoalChanges.map((c) => c.goal.target), [30, 45]);
      expect(p.streakTargets.goalFor(monday(10)).target, 30);
      expect(p.streakTargets.goalFor(thisWeek).target, 45);
    });

    test('several presses in one week are one change, and changing back undoes it', () {
      var p = const Profile(streakGoal: StreakGoal(target: 30));
      for (var t = 35.0; t <= 135; t += 5) {
        p = p.withStreakGoal(StreakGoal(target: t), thisWeek: thisWeek);
      }
      expect(p.streakGoalChanges, hasLength(2), reason: '21 presses, one week: one change');
      expect(p.streakGoal.target, 135);

      p = p.withStreakGoal(const StreakGoal(target: 30), thisWeek: thisWeek);
      expect(p.streakGoalChanges.map((c) => c.goal.target), [30], reason: 'back where it started');
      expect(p.streakTargets.goalFor(thisWeek).target, 30);
    });

    test('an unchanged target records nothing', () {
      final p = const Profile().withStreakGoal(const StreakGoal(), thisWeek: thisWeek);
      expect(p.streakGoalChanges, isEmpty);
    });

    test('survives a save and load, and skips a malformed entry', () {
      final p = const Profile(streakGoal: StreakGoal(target: 30))
          .withStreakGoal(const StreakGoal(target: 60), thisWeek: monday(2));
      final json = p.toJson();
      (json['streakGoalChanges'] as List).add({'from': 'not a date'});

      final loaded = Profile.fromJson(json);
      expect(loaded.streakGoalChanges.map((c) => (c.from, c.goal.target)), [(DateTime(2000), 30), (monday(2), 60)]);
      expect(loaded.streakTargets.goalFor(monday(3)).target, 30);
      expect(loaded.streakTargets.goalFor(monday(1)).target, 60);
    });

    test('a profile from before changes were recorded judges every week as before', () {
      final loaded = Profile.fromJson({'streakGoal': {'metric': 'minutes', 'target': 45}});
      expect(loaded.streakGoalChanges, isEmpty);
      expect(loaded.streakTargets.goalFor(monday(30)).target, 45);
    });
  });
}
