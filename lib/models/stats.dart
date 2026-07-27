import 'run_record.dart';

/// Aggregates for one window of time (this week, this month, ...).
class PeriodStats {
  const PeriodStats({
    required this.label,
    required this.runs,
    required this.missions,
    required this.distanceMeters,
    required this.seconds,
    required this.calories,
    required this.perDay,
  });

  final String label;
  final int runs;
  final int missions;
  final double distanceMeters;
  final double seconds;
  final double calories;

  /// Distance per calendar day, oldest first — drives the bar chart.
  final List<DayBucket> perDay;

  double get km => distanceMeters / 1000;
  double get minutes => seconds / 60;
  double get paceSecondsPerKm => distanceMeters < 100 ? 0 : seconds / (distanceMeters / 1000);

  static const PeriodStats empty = PeriodStats(
    label: '',
    runs: 0,
    missions: 0,
    distanceMeters: 0,
    seconds: 0,
    calories: 0,
    perDay: [],
  );
}

class DayBucket {
  const DayBucket(this.day, this.distanceMeters, this.seconds, this.runs);

  final DateTime day;
  final double distanceMeters;
  final double seconds;
  final int runs;
}

/// Everything the achievement engine and the dashboard need to know about the
/// runner's whole history, computed once per change to the run log.
class LifetimeStats {
  const LifetimeStats({
    this.totalRuns = 0,
    this.totalDistanceMeters = 0,
    this.totalSeconds = 0,
    this.totalCalories = 0,
    this.missionsCompleted = 0,
    this.missionsAttempted = 0,
    this.chasesTotal = 0,
    this.chasesEvaded = 0,
    this.beatsHeard = 0,
    this.longestRunMeters = 0,
    this.longestRunSeconds = 0,
    this.bestPaceSecondsPerKm = 0,
    this.bestWeekMeters = 0,
    this.currentStreakWeeks = 0,
    this.longestStreakWeeks = 0,
    this.nightRuns = 0,
    this.dawnRuns = 0,
    this.distinctDays = 0,
    this.perfectMissions = 0,
    this.firstRunAt,
    this.lastRunAt,
  });

  final int totalRuns;
  final double totalDistanceMeters;
  final double totalSeconds;
  final double totalCalories;

  final int missionsCompleted;
  final int missionsAttempted;

  final int chasesTotal;
  final int chasesEvaded;
  final int beatsHeard;

  final double longestRunMeters;
  final double longestRunSeconds;

  /// Best average pace over any run of at least 3 km. 0 when none qualify.
  final double bestPaceSecondsPerKm;

  final double bestWeekMeters;
  final int currentStreakWeeks;
  final int longestStreakWeeks;

  /// Runs started between 22:00 and 05:00 / between 04:00 and 07:00.
  final int nightRuns;
  final int dawnRuns;

  final int distinctDays;

  /// Missions completed without being caught in a single chase.
  final int perfectMissions;

  final DateTime? firstRunAt;
  final DateTime? lastRunAt;

  double get totalKm => totalDistanceMeters / 1000;
  double get totalHours => totalSeconds / 3600;

  static const LifetimeStats empty = LifetimeStats();
}

/// Where the runner stands against their weekly commitment right now.
class StreakStatus {
  const StreakStatus({
    required this.weeks,
    required this.longestWeeks,
    required this.currentValue,
    required this.target,
    required this.unitLabel,
    required this.weekEndsIn,
    required this.recentWeeks,
  });

  final int weeks;
  final int longestWeeks;

  /// Progress toward this week's target, in the streak goal's own unit.
  final double currentValue;
  final double target;
  final String unitLabel;
  final Duration weekEndsIn;

  /// Last 12 weeks, oldest first: true where the goal was met.
  final List<bool> recentWeeks;

  bool get metThisWeek => currentValue >= target;
  double get progress => target <= 0 ? 1 : (currentValue / target).clamp(0.0, 1.0);

  static const StreakStatus empty = StreakStatus(
    weeks: 0,
    longestWeeks: 0,
    currentValue: 0,
    target: 30,
    unitLabel: 'MIN',
    weekEndsIn: Duration.zero,
    recentWeeks: [],
  );
}

/// A single run plus its context, handed to the summary screen.
class RunOutcomeReport {
  const RunOutcomeReport({required this.record, required this.newAchievements, required this.missionUnlocked});

  final RunRecord record;
  final List<String> newAchievements;

  /// Codename of the mission this run just unlocked, if any.
  final String? missionUnlocked;
}
