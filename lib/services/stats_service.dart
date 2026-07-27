import 'dart:math';

import '../models/profile.dart';
import '../models/run_record.dart';
import '../models/stats.dart';

/// Every derived number in the app is computed here, from the run log alone.
///
/// All functions are pure: given the same runs they return the same stats.
/// That is what lets the achievement wall be recomputed from scratch at any
/// time instead of maintaining counters that can drift.
abstract final class StatsService {
  /// Monday 00:00 local time for the week containing [d].
  static DateTime weekStart(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static DateTime monthStart(DateTime d) => DateTime(d.year, d.month);

  static DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Aggregates every scoring run in `[from, to)`.
  static PeriodStats period(
    List<RunRecord> runs, {
    required String label,
    required DateTime from,
    required DateTime to,
  }) {
    final inWindow = runs
        .where((r) => r.countsForStats && !r.startedAt.isBefore(from) && r.startedAt.isBefore(to))
        .toList();

    final buckets = <DateTime, DayBucket>{};
    for (var day = dayStart(from); day.isBefore(to); day = _nextDay(day)) {
      buckets[day] = DayBucket(day, 0, 0, 0);
    }
    for (final run in inWindow) {
      final key = dayStart(run.startedAt);
      final b = buckets[key];
      if (b == null) continue;
      buckets[key] = DayBucket(
        key,
        b.distanceMeters + run.distanceMeters,
        b.seconds + run.elapsedSeconds,
        b.runs + 1,
      );
    }

    return PeriodStats(
      label: label,
      runs: inWindow.length,
      missions: inWindow.where((r) => r.isMission && r.isSuccess).length,
      distanceMeters: inWindow.fold(0.0, (s, r) => s + r.distanceMeters),
      seconds: inWindow.fold(0.0, (s, r) => s + r.elapsedSeconds),
      calories: inWindow.fold(0.0, (s, r) => s + r.calories),
      perDay: buckets.values.toList()..sort((a, b) => a.day.compareTo(b.day)),
    );
  }

  /// Rolling window ending now — "the last 7 days", not "since Monday".
  static PeriodStats lastDays(List<RunRecord> runs, int days, {required String label, DateTime? now}) {
    final end = _nextDay(dayStart(now ?? DateTime.now()));
    return period(runs, label: label, from: end.subtract(Duration(days: days)), to: end);
  }

  static LifetimeStats lifetime(List<RunRecord> runs, StreakGoal goal, {DateTime? now}) {
    final scoring = runs.where((r) => r.countsForStats).toList();
    if (scoring.isEmpty) return LifetimeStats.empty;

    var bestPace = 0.0;
    for (final r in scoring) {
      // Only runs of 3 km+ qualify — a 400 m sprint is not a pace record.
      if (r.distanceMeters >= 3000 && r.paceSecondsPerKm > 0) {
        bestPace = bestPace == 0 ? r.paceSecondsPerKm : min(bestPace, r.paceSecondsPerKm);
      }
    }

    final weekly = _weeklyTotals(scoring);
    final streak = _streakWeeks(weekly, goal, now: now ?? DateTime.now());

    final sortedByDate = List<RunRecord>.from(scoring)..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    return LifetimeStats(
      totalRuns: scoring.length,
      totalDistanceMeters: scoring.fold(0.0, (s, r) => s + r.distanceMeters),
      totalSeconds: scoring.fold(0.0, (s, r) => s + r.elapsedSeconds),
      totalCalories: scoring.fold(0.0, (s, r) => s + r.calories),
      missionsCompleted: scoring.where((r) => r.isMission && r.isSuccess).map((r) => r.missionId).toSet().length,
      missionsAttempted: scoring.where((r) => r.isMission).map((r) => r.missionId).toSet().length,
      chasesTotal: scoring.fold(0, (s, r) => s + r.chasesTotal),
      chasesEvaded: scoring.fold(0, (s, r) => s + r.chasesEvaded),
      beatsHeard: scoring.fold(0, (s, r) => s + r.beatsHeard),
      longestRunMeters: scoring.fold(0.0, (s, r) => max(s, r.distanceMeters)),
      longestRunSeconds: scoring.fold(0.0, (s, r) => max(s, r.elapsedSeconds)),
      bestPaceSecondsPerKm: bestPace,
      bestWeekMeters: weekly.values.fold(0.0, (s, w) => max(s, w.distanceMeters)),
      currentStreakWeeks: streak.$1,
      longestStreakWeeks: streak.$2,
      nightRuns: scoring.where((r) => _isNight(r.startedAt)).length,
      dawnRuns: scoring.where((r) => _isDawn(r.startedAt)).length,
      distinctDays: scoring.map((r) => dayStart(r.startedAt)).toSet().length,
      perfectMissions: scoring
          .where((r) => r.isMission && r.isSuccess && r.chasesTotal > 0 && r.chasesEvaded == r.chasesTotal)
          .map((r) => r.missionId)
          .toSet()
          .length,
      firstRunAt: sortedByDate.first.startedAt,
      lastRunAt: sortedByDate.last.startedAt,
    );
  }

  static StreakStatus streak(List<RunRecord> runs, StreakGoal goal, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final weekly = _weeklyTotals(runs.where((r) => r.countsForStats).toList());
    final (current, longest) = _streakWeeks(weekly, goal, now: at);

    final thisWeek = weekStart(at);
    final currentValue = _valueFor(weekly[thisWeek], goal);
    final nextWeek = thisWeek.add(const Duration(days: 7));

    final recent = <bool>[];
    for (var i = 11; i >= 0; i--) {
      final week = thisWeek.subtract(Duration(days: 7 * i));
      recent.add(_valueFor(weekly[week], goal) >= goal.target);
    }

    return StreakStatus(
      weeks: current,
      longestWeeks: longest,
      currentValue: currentValue,
      target: goal.target,
      unitLabel: goal.unitLabel,
      weekEndsIn: nextWeek.difference(at),
      recentWeeks: recent,
    );
  }

  // -- internals ------------------------------------------------------------

  static DateTime _nextDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);

  static bool _isNight(DateTime d) => d.hour >= 22 || d.hour < 5;
  static bool _isDawn(DateTime d) => d.hour >= 4 && d.hour < 7;

  static Map<DateTime, _WeekTotal> _weeklyTotals(List<RunRecord> runs) {
    final out = <DateTime, _WeekTotal>{};
    for (final run in runs) {
      final key = weekStart(run.startedAt);
      final w = out[key] ?? const _WeekTotal(0, 0, 0);
      out[key] = _WeekTotal(
        w.seconds + run.elapsedSeconds,
        w.distanceMeters + run.distanceMeters,
        w.missions + (run.isMission && run.isSuccess ? 1 : 0),
      );
    }
    return out;
  }

  static double _valueFor(_WeekTotal? week, StreakGoal goal) {
    if (week == null) return 0;
    return switch (goal.metric) {
      StreakMetric.minutes => week.seconds / 60.0,
      StreakMetric.kilometres => week.distanceMeters / 1000.0,
      StreakMetric.missions => week.missions.toDouble(),
    };
  }

  /// Returns (current streak, longest streak) in weeks.
  ///
  /// The current week is only *counted* once its target is met, but a week
  /// still in progress never breaks the streak — otherwise every Monday
  /// morning would wipe out months of work.
  static (int, int) _streakWeeks(Map<DateTime, _WeekTotal> weekly, StreakGoal goal, {required DateTime now}) {
    final thisWeek = weekStart(now);

    var current = 0;
    var cursor = thisWeek;
    if (_valueFor(weekly[cursor], goal) >= goal.target) {
      current = 1;
    }
    cursor = cursor.subtract(const Duration(days: 7));
    while (_valueFor(weekly[cursor], goal) >= goal.target) {
      current++;
      cursor = cursor.subtract(const Duration(days: 7));
    }

    if (weekly.isEmpty) return (current, current);

    final weeks = weekly.keys.toList()..sort();
    var longest = 0;
    var run = 0;
    var week = weeks.first;
    while (!week.isAfter(thisWeek)) {
      if (_valueFor(weekly[week], goal) >= goal.target) {
        run++;
        longest = max(longest, run);
      } else {
        run = 0;
      }
      week = week.add(const Duration(days: 7));
    }

    return (current, max(longest, current));
  }
}

class _WeekTotal {
  const _WeekTotal(this.seconds, this.distanceMeters, this.missions);

  final double seconds;
  final double distanceMeters;
  final int missions;
}
