import 'package:flutter/material.dart';

import '../theme/cyber_palette.dart';
import 'stats.dart';

/// Rarity bands, named after street-tech grades rather than metals.
enum AchTier { street, chrome, ice, legend }

extension AchTierStyle on AchTier {
  String get label => switch (this) {
    AchTier.street => 'STREET',
    AchTier.chrome => 'CHROME',
    AchTier.ice => 'ICE',
    AchTier.legend => 'LEGEND',
  };

  Color get color => switch (this) {
    AchTier.street => Cy.inkDim,
    AchTier.chrome => Cy.cyan,
    AchTier.ice => Cy.magenta,
    AchTier.legend => Cy.amber,
  };
}

enum AchCategory { distance, endurance, missions, pursuit, discipline, anomaly }

extension AchCategoryLabel on AchCategory {
  String get label => switch (this) {
    AchCategory.distance => 'DISTANCE',
    AchCategory.endurance => 'ENDURANCE',
    AchCategory.missions => 'OPERATIONS',
    AchCategory.pursuit => 'PURSUIT',
    AchCategory.discipline => 'DISCIPLINE',
    AchCategory.anomaly => 'ANOMALY',
  };

  IconData get icon => switch (this) {
    AchCategory.distance => Icons.route_outlined,
    AchCategory.endurance => Icons.timer_outlined,
    AchCategory.missions => Icons.hexagon_outlined,
    AchCategory.pursuit => Icons.radar_outlined,
    AchCategory.discipline => Icons.local_fire_department_outlined,
    AchCategory.anomaly => Icons.blur_on_outlined,
  };
}

/// A single unlockable. Progress is a pure function of [LifetimeStats], so the
/// entire wall can be recomputed from the run log at any time — no achievement
/// state can drift out of sync with reality.
class AchievementDef {
  const AchievementDef({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.tier,
    required this.target,
    required this.metric,
    required this.format,
  });

  final String id;
  final String title;
  final String description;
  final AchCategory category;
  final AchTier tier;
  final double target;
  final double Function(LifetimeStats) metric;
  final String Function(double value) format;

  double progressOf(LifetimeStats s) => target <= 0 ? 0 : (metric(s) / target).clamp(0.0, 1.0);
  bool isEarned(LifetimeStats s) => metric(s) >= target;
  String progressLabel(LifetimeStats s) => '${format(metric(s).clamp(0, target))} / ${format(target)}';
}

/// An [AchievementDef] paired with the runner's state.
class AchievementView {
  const AchievementView({required this.def, required this.earned, required this.progress, this.earnedAt});

  final AchievementDef def;
  final bool earned;
  final double progress;
  final DateTime? earnedAt;
}

String _km(double v) => '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)} km';
String _hours(double v) => '${(v / 3600).toStringAsFixed(v >= 36000 ? 0 : 1)} h';
String _count(double v) => v.round().toString();
String _minutes(double v) => '${(v / 60).round()} min';
String _kcal(double v) => '${v.round()} kcal';

/// Pace metrics count *down*, so they are inverted into "seconds saved under
/// the threshold" to keep every metric monotonically increasing.
double _paceUnder(LifetimeStats s, double thresholdSecPerKm) {
  if (s.bestPaceSecondsPerKm <= 0) return 0;
  return s.bestPaceSecondsPerKm <= thresholdSecPerKm ? 1 : 0;
}

/// The full wall. Ordered roughly by how early a runner will see them.
const List<AchievementDef> kAchievements = [
  // ---- Distance -----------------------------------------------------------
  AchievementDef(
    id: 'dist_5k',
    title: 'First Kilometres',
    description: 'Cover 5 km across all runs.',
    category: AchCategory.distance,
    tier: AchTier.street,
    target: 5000,
    metric: _totalDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'dist_25k',
    title: 'Ward Walker',
    description: 'Cover 25 km across all runs.',
    category: AchCategory.distance,
    tier: AchTier.street,
    target: 25000,
    metric: _totalDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'dist_50k',
    title: 'Sector Sweep',
    description: 'Cover 50 km across all runs.',
    category: AchCategory.distance,
    tier: AchTier.chrome,
    target: 50000,
    metric: _totalDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'dist_100k',
    title: 'Sprawl Native',
    description: 'Cover 100 km across all runs.',
    category: AchCategory.distance,
    tier: AchTier.chrome,
    target: 100000,
    metric: _totalDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'dist_250k',
    title: 'Arterial',
    description: 'Cover 250 km across all runs.',
    category: AchCategory.distance,
    tier: AchTier.ice,
    target: 250000,
    metric: _totalDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'dist_500k',
    title: 'BAMA Corridor',
    description: 'Cover 500 km across all runs.',
    category: AchCategory.distance,
    tier: AchTier.ice,
    target: 500000,
    metric: _totalDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'dist_1000k',
    title: 'Orbital Distance',
    description: 'Cover 1000 km across all runs.',
    category: AchCategory.distance,
    tier: AchTier.legend,
    target: 1000000,
    metric: _totalDistance,
    format: _km,
  ),

  // ---- Endurance ----------------------------------------------------------
  AchievementDef(
    id: 'time_1h',
    title: 'Clocked In',
    description: 'One hour of total running time.',
    category: AchCategory.endurance,
    tier: AchTier.street,
    target: 3600,
    metric: _totalSeconds,
    format: _hours,
  ),
  AchievementDef(
    id: 'time_10h',
    title: 'Ten Hours Deep',
    description: 'Ten hours of total running time.',
    category: AchCategory.endurance,
    tier: AchTier.chrome,
    target: 36000,
    metric: _totalSeconds,
    format: _hours,
  ),
  AchievementDef(
    id: 'time_25h',
    title: 'Wetware Tuned',
    description: 'Twenty-five hours of total running time.',
    category: AchCategory.endurance,
    tier: AchTier.chrome,
    target: 90000,
    metric: _totalSeconds,
    format: _hours,
  ),
  AchievementDef(
    id: 'time_50h',
    title: 'Overclocked',
    description: 'Fifty hours of total running time.',
    category: AchCategory.endurance,
    tier: AchTier.ice,
    target: 180000,
    metric: _totalSeconds,
    format: _hours,
  ),
  AchievementDef(
    id: 'time_100h',
    title: 'Ghost In The Legs',
    description: 'One hundred hours of total running time.',
    category: AchCategory.endurance,
    tier: AchTier.legend,
    target: 360000,
    metric: _totalSeconds,
    format: _hours,
  ),
  AchievementDef(
    id: 'single_5k',
    title: 'Five Clean',
    description: 'Run 5 km in a single session.',
    category: AchCategory.endurance,
    tier: AchTier.street,
    target: 5000,
    metric: _longestDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'single_10k',
    title: 'Ten Clean',
    description: 'Run 10 km in a single session.',
    category: AchCategory.endurance,
    tier: AchTier.chrome,
    target: 10000,
    metric: _longestDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'single_half',
    title: 'Long Haul',
    description: 'Run 21.1 km in a single session.',
    category: AchCategory.endurance,
    tier: AchTier.ice,
    target: 21100,
    metric: _longestDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'single_60m',
    title: 'The Long Hour',
    description: 'Keep moving for 60 minutes in one session.',
    category: AchCategory.endurance,
    tier: AchTier.chrome,
    target: 3600,
    metric: _longestSeconds,
    format: _minutes,
  ),
  AchievementDef(
    id: 'single_90m',
    title: 'No Off Switch',
    description: 'Keep moving for 90 minutes in one session.',
    category: AchCategory.endurance,
    tier: AchTier.ice,
    target: 5400,
    metric: _longestSeconds,
    format: _minutes,
  ),

  // ---- Operations ---------------------------------------------------------
  AchievementDef(
    id: 'mission_1',
    title: 'Made Contact',
    description: 'Complete your first mission.',
    category: AchCategory.missions,
    tier: AchTier.street,
    target: 1,
    metric: _missions,
    format: _count,
  ),
  AchievementDef(
    id: 'mission_3',
    title: 'On The Payroll',
    description: 'Complete three missions.',
    category: AchCategory.missions,
    tier: AchTier.street,
    target: 3,
    metric: _missions,
    format: _count,
  ),
  AchievementDef(
    id: 'mission_5',
    title: 'Halfway To Freeside',
    description: 'Complete five missions.',
    category: AchCategory.missions,
    tier: AchTier.chrome,
    target: 5,
    metric: _missions,
    format: _count,
  ),
  AchievementDef(
    id: 'mission_10',
    title: 'Kuang Complete',
    description: 'Complete all ten missions of SPRAWL PRIME.',
    category: AchCategory.missions,
    tier: AchTier.legend,
    target: 10,
    metric: _missions,
    format: _count,
  ),
  AchievementDef(
    id: 'beats_100',
    title: 'Signal Discipline',
    description: 'Hear 100 story transmissions.',
    category: AchCategory.missions,
    tier: AchTier.chrome,
    target: 100,
    metric: _beats,
    format: _count,
  ),
  AchievementDef(
    id: 'perfect_1',
    title: 'Untouched',
    description: 'Finish a mission without being caught once.',
    category: AchCategory.missions,
    tier: AchTier.chrome,
    target: 1,
    metric: _perfect,
    format: _count,
  ),
  AchievementDef(
    id: 'perfect_5',
    title: 'Never Was There',
    description: 'Finish five missions without being caught once.',
    category: AchCategory.missions,
    tier: AchTier.ice,
    target: 5,
    metric: _perfect,
    format: _count,
  ),

  // ---- Pursuit ------------------------------------------------------------
  AchievementDef(
    id: 'chase_5',
    title: 'Light Feet',
    description: 'Escape 5 pursuits.',
    category: AchCategory.pursuit,
    tier: AchTier.street,
    target: 5,
    metric: _evaded,
    format: _count,
  ),
  AchievementDef(
    id: 'chase_25',
    title: 'Hard To Tag',
    description: 'Escape 25 pursuits.',
    category: AchCategory.pursuit,
    tier: AchTier.chrome,
    target: 25,
    metric: _evaded,
    format: _count,
  ),
  AchievementDef(
    id: 'chase_100',
    title: 'Unscannable',
    description: 'Escape 100 pursuits.',
    category: AchCategory.pursuit,
    tier: AchTier.ice,
    target: 100,
    metric: _evaded,
    format: _count,
  ),
  AchievementDef(
    id: 'pace_600',
    title: 'Moving With Purpose',
    description: 'Average under 6:00 / km over a run of 3 km or more.',
    category: AchCategory.pursuit,
    tier: AchTier.street,
    target: 1,
    metric: _paceUnder600,
    format: _count,
  ),
  AchievementDef(
    id: 'pace_530',
    title: 'Razor Quick',
    description: 'Average under 5:30 / km over a run of 3 km or more.',
    category: AchCategory.pursuit,
    tier: AchTier.chrome,
    target: 1,
    metric: _paceUnder530,
    format: _count,
  ),
  AchievementDef(
    id: 'pace_500',
    title: 'Panther Modern',
    description: 'Average under 5:00 / km over a run of 3 km or more.',
    category: AchCategory.pursuit,
    tier: AchTier.ice,
    target: 1,
    metric: _paceUnder500,
    format: _count,
  ),
  AchievementDef(
    id: 'pace_430',
    title: 'Simstim Speed',
    description: 'Average under 4:30 / km over a run of 3 km or more.',
    category: AchCategory.pursuit,
    tier: AchTier.legend,
    target: 1,
    metric: _paceUnder430,
    format: _count,
  ),

  // ---- Discipline ---------------------------------------------------------
  AchievementDef(
    id: 'streak_2',
    title: 'Two Weeks Standing',
    description: 'Hit your weekly target two weeks running.',
    category: AchCategory.discipline,
    tier: AchTier.street,
    target: 2,
    metric: _longestStreak,
    format: _count,
  ),
  AchievementDef(
    id: 'streak_4',
    title: 'A Month Of It',
    description: 'Hit your weekly target four weeks running.',
    category: AchCategory.discipline,
    tier: AchTier.street,
    target: 4,
    metric: _longestStreak,
    format: _count,
  ),
  AchievementDef(
    id: 'streak_12',
    title: 'Quarterly Contract',
    description: 'Hit your weekly target twelve weeks running.',
    category: AchCategory.discipline,
    tier: AchTier.chrome,
    target: 12,
    metric: _longestStreak,
    format: _count,
  ),
  AchievementDef(
    id: 'streak_26',
    title: 'Half A Year Wired',
    description: 'Hit your weekly target twenty-six weeks running.',
    category: AchCategory.discipline,
    tier: AchTier.ice,
    target: 26,
    metric: _longestStreak,
    format: _count,
  ),
  AchievementDef(
    id: 'streak_52',
    title: 'Full Rotation',
    description: 'Hit your weekly target fifty-two weeks running.',
    category: AchCategory.discipline,
    tier: AchTier.legend,
    target: 52,
    metric: _longestStreak,
    format: _count,
  ),
  AchievementDef(
    id: 'runs_10',
    title: 'Regular',
    description: 'Log 10 runs.',
    category: AchCategory.discipline,
    tier: AchTier.street,
    target: 10,
    metric: _runs,
    format: _count,
  ),
  AchievementDef(
    id: 'runs_50',
    title: 'Known Quantity',
    description: 'Log 50 runs.',
    category: AchCategory.discipline,
    tier: AchTier.chrome,
    target: 50,
    metric: _runs,
    format: _count,
  ),
  AchievementDef(
    id: 'runs_200',
    title: 'Institution',
    description: 'Log 200 runs.',
    category: AchCategory.discipline,
    tier: AchTier.legend,
    target: 200,
    metric: _runs,
    format: _count,
  ),
  AchievementDef(
    id: 'days_30',
    title: 'Thirty Separate Nights',
    description: 'Run on 30 different days.',
    category: AchCategory.discipline,
    tier: AchTier.chrome,
    target: 30,
    metric: _days,
    format: _count,
  ),

  // ---- Anomaly ------------------------------------------------------------
  AchievementDef(
    id: 'night_5',
    title: 'Nocturne',
    description: 'Start five runs between 22:00 and 05:00.',
    category: AchCategory.anomaly,
    tier: AchTier.street,
    target: 5,
    metric: _night,
    format: _count,
  ),
  AchievementDef(
    id: 'night_25',
    title: 'The City Never Sleeps',
    description: 'Start twenty-five runs between 22:00 and 05:00.',
    category: AchCategory.anomaly,
    tier: AchTier.ice,
    target: 25,
    metric: _night,
    format: _count,
  ),
  AchievementDef(
    id: 'dawn_5',
    title: 'Grey Hours',
    description: 'Start five runs between 04:00 and 07:00.',
    category: AchCategory.anomaly,
    tier: AchTier.street,
    target: 5,
    metric: _dawn,
    format: _count,
  ),
  AchievementDef(
    id: 'kcal_10k',
    title: 'Metabolic Debt',
    description: 'Burn 10,000 kcal.',
    category: AchCategory.anomaly,
    tier: AchTier.chrome,
    target: 10000,
    metric: _calories,
    format: _kcal,
  ),
  AchievementDef(
    id: 'kcal_50k',
    title: 'Furnace',
    description: 'Burn 50,000 kcal.',
    category: AchCategory.anomaly,
    tier: AchTier.legend,
    target: 50000,
    metric: _calories,
    format: _kcal,
  ),
  AchievementDef(
    id: 'week_30k',
    title: 'Heavy Week',
    description: 'Cover 30 km inside a single week.',
    category: AchCategory.anomaly,
    tier: AchTier.ice,
    target: 30000,
    metric: _bestWeek,
    format: _km,
  ),
];

// Top-level metric accessors — const list entries cannot hold closures.
double _totalDistance(LifetimeStats s) => s.totalDistanceMeters;
double _totalSeconds(LifetimeStats s) => s.totalSeconds;
double _longestDistance(LifetimeStats s) => s.longestRunMeters;
double _longestSeconds(LifetimeStats s) => s.longestRunSeconds;
double _missions(LifetimeStats s) => s.missionsCompleted.toDouble();
double _beats(LifetimeStats s) => s.beatsHeard.toDouble();
double _perfect(LifetimeStats s) => s.perfectMissions.toDouble();
double _evaded(LifetimeStats s) => s.chasesEvaded.toDouble();
double _runs(LifetimeStats s) => s.totalRuns.toDouble();
double _days(LifetimeStats s) => s.distinctDays.toDouble();
double _night(LifetimeStats s) => s.nightRuns.toDouble();
double _dawn(LifetimeStats s) => s.dawnRuns.toDouble();
double _calories(LifetimeStats s) => s.totalCalories;
double _bestWeek(LifetimeStats s) => s.bestWeekMeters;
double _longestStreak(LifetimeStats s) => s.longestStreakWeeks.toDouble();
double _paceUnder600(LifetimeStats s) => _paceUnder(s, 360);
double _paceUnder530(LifetimeStats s) => _paceUnder(s, 330);
double _paceUnder500(LifetimeStats s) => _paceUnder(s, 300);
double _paceUnder430(LifetimeStats s) => _paceUnder(s, 270);
