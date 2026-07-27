import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/services/stats_service.dart';

import 'support/fakes.dart';

void main() {
  // A Wednesday, so week boundaries are unambiguous in every assertion below.
  final wednesday = DateTime(2026, 7, 22, 18, 0);
  DateTime monday(int weeksAgo) =>
      DateTime(2026, 7, 20).subtract(Duration(days: 7 * weeksAgo));

  group('week boundaries', () {
    test('weeks start on Monday at midnight local time', () {
      expect(StatsService.weekStart(wednesday), DateTime(2026, 7, 20));
      expect(StatsService.weekStart(DateTime(2026, 7, 20, 0, 0)), DateTime(2026, 7, 20));
      // Sunday belongs to the week that started six days earlier.
      expect(StatsService.weekStart(DateTime(2026, 7, 26, 23, 59)), DateTime(2026, 7, 20));
      expect(StatsService.weekStart(DateTime(2026, 7, 27, 0, 1)), DateTime(2026, 7, 27));
    });
  });

  group('period aggregation', () {
    test('sums only runs inside the window', () {
      final runs = [
        run(at: wednesday, meters: 5000, seconds: 1800, calories: 400),
        run(at: wednesday.subtract(const Duration(days: 3)), meters: 3000, seconds: 1200, calories: 250),
        // 40 days back: inside the month window? No — outside both.
        run(at: wednesday.subtract(const Duration(days: 40)), meters: 9000, seconds: 3600),
      ];

      final week = StatsService.lastDays(runs, 7, label: 'W', now: wednesday);
      expect(week.runs, 2);
      expect(week.distanceMeters, 8000);
      expect(week.seconds, 3000);
      expect(week.calories, 650);

      final month = StatsService.lastDays(runs, 30, label: 'M', now: wednesday);
      expect(month.runs, 2, reason: 'the 40-day-old run is outside a 30 day window');
    });

    test('discarded runs never reach the stats', () {
      final runs = [
        run(at: wednesday, meters: 5000),
        run(at: wednesday, meters: 30, seconds: 20, outcome: RunOutcome.discarded),
      ];
      final week = StatsService.lastDays(runs, 7, label: 'W', now: wednesday);
      expect(week.runs, 1);
      expect(week.distanceMeters, 5000);
    });

    test('failed runs still count toward distance and time', () {
      final runs = [run(at: wednesday, meters: 4000, seconds: 1500, outcome: RunOutcome.failed)];
      final week = StatsService.lastDays(runs, 7, label: 'W', now: wednesday);
      expect(week.distanceMeters, 4000);
      expect(week.missions, 0, reason: 'a failed mission is not a cleared mission');
    });

    test('daily buckets cover every day in the window, including empty ones', () {
      final week = StatsService.lastDays([run(at: wednesday)], 7, label: 'W', now: wednesday);
      expect(week.perDay.length, 7);
      expect(week.perDay.where((d) => d.runs > 0).length, 1);
    });
  });

  group('streaks', () {
    const minutesGoal = StreakGoal(target: 30);

    test('counts consecutive weeks that met the target', () {
      final runs = [
        for (var w = 0; w < 4; w++) run(at: monday(w).add(const Duration(hours: 9)), seconds: 2400),
      ];
      final status = StatsService.streak(runs, minutesGoal, now: wednesday);
      expect(status.weeks, 4);
      expect(status.metThisWeek, isTrue);
    });

    test('a week still in progress does not break the streak', () {
      // Three past weeks are complete; this week has nothing logged yet.
      final runs = [
        for (var w = 1; w <= 3; w++) run(at: monday(w).add(const Duration(hours: 9)), seconds: 2400),
      ];
      final status = StatsService.streak(runs, minutesGoal, now: wednesday);
      expect(status.weeks, 3, reason: 'the current week has not ended, so it cannot have failed yet');
      expect(status.metThisWeek, isFalse);
      expect(status.currentValue, 0);
    });

    test('a completed week below target resets the streak', () {
      final runs = [
        run(at: monday(1).add(const Duration(hours: 9)), seconds: 600), // 10 min — short
        for (var w = 2; w <= 4; w++) run(at: monday(w).add(const Duration(hours: 9)), seconds: 2400),
      ];
      final status = StatsService.streak(runs, minutesGoal, now: wednesday);
      expect(status.weeks, 0);
      expect(status.longestWeeks, 3, reason: 'the three good weeks before the gap are still the record');
    });

    test('multiple runs in a week accumulate toward the target', () {
      final runs = [
        run(at: monday(0).add(const Duration(hours: 9)), seconds: 900),
        run(at: monday(0).add(const Duration(days: 2, hours: 9)), seconds: 900),
      ];
      final status = StatsService.streak(runs, minutesGoal, now: wednesday);
      expect(status.currentValue, 30);
      expect(status.metThisWeek, isTrue);
      expect(status.weeks, 1);
    });

    test('respects a kilometre-based goal', () {
      const goal = StreakGoal(metric: StreakMetric.kilometres, target: 10);
      final runs = [run(at: monday(0).add(const Duration(hours: 9)), meters: 12000, seconds: 600)];
      final status = StatsService.streak(runs, goal, now: wednesday);
      expect(status.currentValue, closeTo(12, 0.001));
      expect(status.metThisWeek, isTrue);
      expect(status.unitLabel, 'KM');
    });

    test('respects a mission-count goal, and failed missions do not count', () {
      const goal = StreakGoal(metric: StreakMetric.missions, target: 2);
      final base = monday(0).add(const Duration(hours: 9));
      final runs = [
        run(at: base, missionId: 'sp01'),
        run(at: base.add(const Duration(days: 1)), missionId: 'sp02', outcome: RunOutcome.failed),
      ];
      final status = StatsService.streak(runs, goal, now: wednesday);
      expect(status.currentValue, 1);
      expect(status.metThisWeek, isFalse);
    });

    test('reports the last twelve weeks for the history strip', () {
      final runs = [run(at: monday(0).add(const Duration(hours: 9)), seconds: 2400)];
      final status = StatsService.streak(runs, minutesGoal, now: wednesday);
      expect(status.recentWeeks.length, 12);
      expect(status.recentWeeks.last, isTrue, reason: 'the last entry is the current week');
      expect(status.recentWeeks.first, isFalse);
    });
  });

  group('lifetime', () {
    test('aggregates totals, records and counts', () {
      final runs = [
        run(at: wednesday, meters: 10000, seconds: 3000, missionId: 'sp01', chasesTotal: 2, chasesEvaded: 2),
        run(at: wednesday.subtract(const Duration(days: 2)), meters: 4000, seconds: 1500, chasesTotal: 1),
        run(at: wednesday.subtract(const Duration(days: 2, hours: 3)), meters: 100, seconds: 60),
      ];
      final stats = StatsService.lifetime(runs, const StreakGoal());

      expect(stats.totalRuns, 3);
      expect(stats.totalDistanceMeters, 14100);
      expect(stats.longestRunMeters, 10000);
      expect(stats.missionsCompleted, 1);
      expect(stats.chasesEvaded, 2);
      expect(stats.chasesTotal, 3);
      expect(stats.perfectMissions, 1);
      expect(stats.distinctDays, 2, reason: 'two of the runs are on the same calendar day');
    });

    test('best pace ignores runs shorter than 3 km', () {
      final runs = [
        // 1 km in 3 minutes — a very fast pace over too short a distance.
        run(at: wednesday, meters: 1000, seconds: 180),
        // 5 km in 30 minutes — 6:00/km, and the only qualifying run.
        run(at: wednesday.subtract(const Duration(days: 1)), meters: 5000, seconds: 1800),
      ];
      final stats = StatsService.lifetime(runs, const StreakGoal());
      expect(stats.bestPaceSecondsPerKm, closeTo(360, 0.001));
    });

    test('counts night and dawn starts', () {
      final runs = [
        run(at: DateTime(2026, 7, 22, 23, 30)), // night
        run(at: DateTime(2026, 7, 21, 3, 0)), // night
        run(at: DateTime(2026, 7, 20, 5, 30)), // dawn
        run(at: DateTime(2026, 7, 19, 13, 0)), // neither
      ];
      final stats = StatsService.lifetime(runs, const StreakGoal());
      expect(stats.nightRuns, 2);
      expect(stats.dawnRuns, 1);
    });

    test('a mission run with no chases is not a perfect mission', () {
      final runs = [run(at: wednesday, missionId: 'sp01')];
      final stats = StatsService.lifetime(runs, const StreakGoal());
      expect(stats.missionsCompleted, 1);
      expect(stats.perfectMissions, 0);
    });

    test('replaying the same mission counts it once', () {
      final runs = [
        run(at: wednesday, missionId: 'sp01'),
        run(at: wednesday.subtract(const Duration(days: 1)), missionId: 'sp01'),
      ];
      expect(StatsService.lifetime(runs, const StreakGoal()).missionsCompleted, 1);
    });

    test('empty history is empty, not an error', () {
      expect(StatsService.lifetime(const [], const StreakGoal()).totalRuns, 0);
      expect(StatsService.streak(const [], const StreakGoal()).weeks, 0);
    });
  });
}
