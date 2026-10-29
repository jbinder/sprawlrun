import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/cyber_palette.dart';
import 'stats.dart';

/// Rarity bands, named after street-tech grades rather than metals.
enum AchTier { street, chrome, ice, legend }

extension AchTierStyle on AchTier {
  String get label => switch (this) {
    AchTier.street => l10n.tierStreet,
    AchTier.chrome => l10n.tierChrome,
    AchTier.ice => l10n.tierIce,
    AchTier.legend => l10n.tierLegend,
  };

  Color get color => switch (this) {
    AchTier.street => Cy.inkDim,
    AchTier.chrome => Cy.cyan,
    AchTier.ice => Cy.magenta,
    AchTier.legend => Cy.amber,
  };
}

enum AchCategory { distance, endurance, missions, pursuit, discipline, anomaly, seasonal, walking }

extension AchCategoryLabel on AchCategory {
  String get label => switch (this) {
    AchCategory.distance => l10n.achCategoryDistance,
    AchCategory.endurance => l10n.achCategoryEndurance,
    AchCategory.missions => l10n.achCategoryOperations,
    AchCategory.pursuit => l10n.achCategoryPursuit,
    AchCategory.discipline => l10n.achCategoryDiscipline,
    AchCategory.anomaly => l10n.achCategoryAnomaly,
    AchCategory.seasonal => l10n.achCategorySeasonal,
    AchCategory.walking => l10n.achCategoryWalking,
  };

  IconData get icon => switch (this) {
    AchCategory.distance => Icons.route_outlined,
    AchCategory.endurance => Icons.timer_outlined,
    AchCategory.missions => Icons.hexagon_outlined,
    AchCategory.pursuit => Icons.radar_outlined,
    AchCategory.discipline => Icons.local_fire_department_outlined,
    AchCategory.anomaly => Icons.blur_on_outlined,
    AchCategory.seasonal => Icons.nights_stay_outlined,
    AchCategory.walking => Icons.directions_walk,
  };
}

/// A single unlockable. Progress is a pure function of [LifetimeStats], so the
/// entire wall can be recomputed from the run log at any time — no achievement
/// state can drift out of sync with reality.
class AchievementDef {
  const AchievementDef({
    required this.id,
    required this.category,
    required this.tier,
    required this.target,
    required this.metric,
    required this.format,
  });

  final String id;

  /// In the language on screen; the English is in `app_en.arb`, keyed by [id].
  String get title => achievementTitle(l10n, id);
  String get description => achievementDescription(l10n, id);
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
    category: AchCategory.distance,
    tier: AchTier.street,
    target: 5000,
    metric: _totalDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'dist_25k',
    category: AchCategory.distance,
    tier: AchTier.street,
    target: 25000,
    metric: _totalDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'dist_50k',
    category: AchCategory.distance,
    tier: AchTier.chrome,
    target: 50000,
    metric: _totalDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'dist_100k',
    category: AchCategory.distance,
    tier: AchTier.chrome,
    target: 100000,
    metric: _totalDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'dist_150k',
    category: AchCategory.distance,
    tier: AchTier.chrome,
    target: 150000,
    metric: _totalDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'dist_250k',
    category: AchCategory.distance,
    tier: AchTier.ice,
    target: 250000,
    metric: _totalDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'dist_500k',
    category: AchCategory.distance,
    tier: AchTier.ice,
    target: 500000,
    metric: _totalDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'dist_1000k',
    category: AchCategory.distance,
    tier: AchTier.legend,
    target: 1000000,
    metric: _totalDistance,
    format: _km,
  ),

  // ---- Endurance ----------------------------------------------------------
  AchievementDef(
    id: 'time_1h',
    category: AchCategory.endurance,
    tier: AchTier.street,
    target: 3600,
    metric: _totalSeconds,
    format: _hours,
  ),
  AchievementDef(
    id: 'time_5h',
    category: AchCategory.endurance,
    tier: AchTier.street,
    target: 18000,
    metric: _totalSeconds,
    format: _hours,
  ),
  AchievementDef(
    id: 'time_10h',
    category: AchCategory.endurance,
    tier: AchTier.chrome,
    target: 36000,
    metric: _totalSeconds,
    format: _hours,
  ),
  AchievementDef(
    id: 'time_25h',
    category: AchCategory.endurance,
    tier: AchTier.chrome,
    target: 90000,
    metric: _totalSeconds,
    format: _hours,
  ),
  AchievementDef(
    id: 'time_50h',
    category: AchCategory.endurance,
    tier: AchTier.ice,
    target: 180000,
    metric: _totalSeconds,
    format: _hours,
  ),
  AchievementDef(
    id: 'time_100h',
    category: AchCategory.endurance,
    tier: AchTier.legend,
    target: 360000,
    metric: _totalSeconds,
    format: _hours,
  ),
  AchievementDef(
    id: 'single_5k',
    category: AchCategory.endurance,
    tier: AchTier.street,
    target: 5000,
    metric: _longestDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'single_10k',
    category: AchCategory.endurance,
    tier: AchTier.chrome,
    target: 10000,
    metric: _longestDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'single_15k',
    category: AchCategory.distance,
    tier: AchTier.ice,
    target: 15000,
    metric: _longestDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'single_half',
    category: AchCategory.endurance,
    tier: AchTier.ice,
    target: 21100,
    metric: _longestDistance,
    format: _km,
  ),
  AchievementDef(
    id: 'single_30m',
    category: AchCategory.endurance,
    tier: AchTier.street,
    target: 1800,
    metric: _longestSeconds,
    format: _minutes,
  ),
  AchievementDef(
    id: 'single_45m',
    category: AchCategory.endurance,
    tier: AchTier.street,
    target: 2700,
    metric: _longestSeconds,
    format: _minutes,
  ),
  AchievementDef(
    id: 'single_60m',
    category: AchCategory.endurance,
    tier: AchTier.chrome,
    target: 3600,
    metric: _longestSeconds,
    format: _minutes,
  ),
  AchievementDef(
    id: 'single_90m',
    category: AchCategory.endurance,
    tier: AchTier.ice,
    target: 5400,
    metric: _longestSeconds,
    format: _minutes,
  ),
  AchievementDef(
    id: 'single_120m',
    category: AchCategory.endurance,
    tier: AchTier.ice,
    target: 7200,
    metric: _longestSeconds,
    format: _minutes,
  ),

  // ---- Operations ---------------------------------------------------------
  AchievementDef(
    id: 'mission_1',
    category: AchCategory.missions,
    tier: AchTier.street,
    target: 1,
    metric: _missions,
    format: _count,
  ),
  AchievementDef(
    id: 'mission_3',
    category: AchCategory.missions,
    tier: AchTier.street,
    target: 3,
    metric: _missions,
    format: _count,
  ),
  AchievementDef(
    id: 'mission_5',
    category: AchCategory.missions,
    tier: AchTier.chrome,
    target: 5,
    metric: _missions,
    format: _count,
  ),
  AchievementDef(
    id: 'mission_10',
    category: AchCategory.missions,
    tier: AchTier.legend,
    target: 10,
    metric: _sprawlPrimeMissions,
    format: _count,
  ),
  AchievementDef(
    id: 'nt_1',
    category: AchCategory.missions,
    tier: AchTier.street,
    target: 1,
    metric: _nullTideMissions,
    format: _count,
  ),
  AchievementDef(
    id: 'nt_5',
    category: AchCategory.missions,
    tier: AchTier.chrome,
    target: 5,
    metric: _nullTideMissions,
    format: _count,
  ),
  AchievementDef(
    id: 'nt_10',
    category: AchCategory.missions,
    tier: AchTier.legend,
    target: 10,
    metric: _nullTideMissions,
    format: _count,
  ),
  AchievementDef(
    id: 'mission_20',
    category: AchCategory.missions,
    tier: AchTier.ice,
    target: 20,
    metric: _missions,
    format: _count,
  ),
  AchievementDef(
    id: 'beats_100',
    category: AchCategory.missions,
    tier: AchTier.chrome,
    target: 100,
    metric: _beats,
    format: _count,
  ),
  AchievementDef(
    id: 'perfect_1',
    category: AchCategory.missions,
    tier: AchTier.chrome,
    target: 1,
    metric: _perfect,
    format: _count,
  ),
  AchievementDef(
    id: 'perfect_5',
    category: AchCategory.missions,
    tier: AchTier.ice,
    target: 5,
    metric: _perfect,
    format: _count,
  ),

  // ---- Pursuit ------------------------------------------------------------
  AchievementDef(
    id: 'chase_5',
    category: AchCategory.pursuit,
    tier: AchTier.street,
    target: 5,
    metric: _evaded,
    format: _count,
  ),
  AchievementDef(
    id: 'chase_25',
    category: AchCategory.pursuit,
    tier: AchTier.chrome,
    target: 25,
    metric: _evaded,
    format: _count,
  ),
  AchievementDef(
    id: 'chase_100',
    category: AchCategory.pursuit,
    tier: AchTier.ice,
    target: 100,
    metric: _evaded,
    format: _count,
  ),
  AchievementDef(
    id: 'pace_600',
    category: AchCategory.pursuit,
    tier: AchTier.street,
    target: 1,
    metric: _paceUnder600,
    format: _count,
  ),
  AchievementDef(
    id: 'pace_530',
    category: AchCategory.pursuit,
    tier: AchTier.chrome,
    target: 1,
    metric: _paceUnder530,
    format: _count,
  ),
  AchievementDef(
    id: 'pace_500',
    category: AchCategory.pursuit,
    tier: AchTier.ice,
    target: 1,
    metric: _paceUnder500,
    format: _count,
  ),
  AchievementDef(
    id: 'pace_430',
    category: AchCategory.pursuit,
    tier: AchTier.legend,
    target: 1,
    metric: _paceUnder430,
    format: _count,
  ),

  // ---- Discipline ---------------------------------------------------------
  // The rungs are close together early on purpose: the first weeks are when a
  // streak is easiest to abandon, and the gap from four weeks to twelve used to
  // be two months with nothing in it.
  AchievementDef(
    id: 'streak_1',
    category: AchCategory.discipline,
    tier: AchTier.street,
    target: 1,
    metric: _longestStreak,
    format: _count,
  ),
  AchievementDef(
    id: 'streak_2',
    category: AchCategory.discipline,
    tier: AchTier.street,
    target: 2,
    metric: _longestStreak,
    format: _count,
  ),
  AchievementDef(
    id: 'streak_3',
    category: AchCategory.discipline,
    tier: AchTier.street,
    target: 3,
    metric: _longestStreak,
    format: _count,
  ),
  AchievementDef(
    id: 'streak_4',
    category: AchCategory.discipline,
    tier: AchTier.street,
    target: 4,
    metric: _longestStreak,
    format: _count,
  ),
  AchievementDef(
    id: 'streak_6',
    category: AchCategory.discipline,
    tier: AchTier.chrome,
    target: 6,
    metric: _longestStreak,
    format: _count,
  ),
  AchievementDef(
    id: 'streak_8',
    category: AchCategory.discipline,
    tier: AchTier.chrome,
    target: 8,
    metric: _longestStreak,
    format: _count,
  ),
  AchievementDef(
    id: 'streak_12',
    category: AchCategory.discipline,
    tier: AchTier.chrome,
    target: 12,
    metric: _longestStreak,
    format: _count,
  ),
  AchievementDef(
    id: 'streak_26',
    category: AchCategory.discipline,
    tier: AchTier.ice,
    target: 26,
    metric: _longestStreak,
    format: _count,
  ),
  AchievementDef(
    id: 'streak_52',
    category: AchCategory.discipline,
    tier: AchTier.legend,
    target: 52,
    metric: _longestStreak,
    format: _count,
  ),
  AchievementDef(
    id: 'runs_10',
    category: AchCategory.discipline,
    tier: AchTier.street,
    target: 10,
    metric: _runs,
    format: _count,
  ),
  AchievementDef(
    id: 'runs_50',
    category: AchCategory.discipline,
    tier: AchTier.chrome,
    target: 50,
    metric: _runs,
    format: _count,
  ),
  AchievementDef(
    id: 'runs_100',
    category: AchCategory.discipline,
    tier: AchTier.ice,
    target: 100,
    metric: _runs,
    format: _count,
  ),
  AchievementDef(
    id: 'runs_200',
    category: AchCategory.discipline,
    tier: AchTier.legend,
    target: 200,
    metric: _runs,
    format: _count,
  ),
  AchievementDef(
    id: 'days_30',
    category: AchCategory.discipline,
    tier: AchTier.chrome,
    target: 30,
    metric: _days,
    format: _count,
  ),
  AchievementDef(
    id: 'days_100',
    category: AchCategory.discipline,
    tier: AchTier.ice,
    target: 100,
    metric: _days,
    format: _count,
  ),

  // ---- Anomaly ------------------------------------------------------------
  AchievementDef(
    id: 'night_5',
    category: AchCategory.anomaly,
    tier: AchTier.street,
    target: 5,
    metric: _night,
    format: _count,
  ),
  AchievementDef(
    id: 'night_25',
    category: AchCategory.anomaly,
    tier: AchTier.ice,
    target: 25,
    metric: _night,
    format: _count,
  ),
  AchievementDef(
    id: 'dawn_5',
    category: AchCategory.anomaly,
    tier: AchTier.street,
    target: 5,
    metric: _dawn,
    format: _count,
  ),
  AchievementDef(
    id: 'kcal_10k',
    category: AchCategory.anomaly,
    tier: AchTier.chrome,
    target: 10000,
    metric: _calories,
    format: _kcal,
  ),
  AchievementDef(
    id: 'kcal_50k',
    category: AchCategory.anomaly,
    tier: AchTier.legend,
    target: 50000,
    metric: _calories,
    format: _kcal,
  ),
  AchievementDef(
    id: 'week_15k',
    category: AchCategory.anomaly,
    tier: AchTier.chrome,
    target: 15000,
    metric: _bestWeek,
    format: _km,
  ),
  AchievementDef(
    id: 'week_30k',
    category: AchCategory.anomaly,
    tier: AchTier.ice,
    target: 30000,
    metric: _bestWeek,
    format: _km,
  ),
  AchievementDef(
    id: 'week_50k',
    category: AchCategory.anomaly,
    tier: AchTier.legend,
    target: 50000,
    metric: _bestWeek,
    format: _km,
  ),

  // ---- Seasonal -----------------------------------------------------------
  // Earned by the calendar, so they sit on the wall year-round as a reason
  // to come back when the season does.
  AchievementDef(
    id: 'sh_1',
    category: AchCategory.seasonal,
    tier: AchTier.street,
    target: 1,
    metric: _samhainMissions,
    format: _count,
  ),
  AchievementDef(
    id: 'sh_4',
    category: AchCategory.seasonal,
    tier: AchTier.ice,
    target: 4,
    metric: _samhainMissions,
    format: _count,
  ),
  AchievementDef(
    id: 'hallows_eve',
    category: AchCategory.seasonal,
    tier: AchTier.chrome,
    target: 1,
    metric: _hallowsEve,
    format: _count,
  ),
  AchievementDef(
    id: 'samhain_5',
    category: AchCategory.seasonal,
    tier: AchTier.chrome,
    target: 5,
    metric: _samhainRuns,
    format: _count,
  ),
  AchievementDef(
    id: 'samhain_years_2',
    category: AchCategory.seasonal,
    tier: AchTier.legend,
    target: 2,
    metric: _samhainYears,
    format: _count,
  ),

  // ---- Walking ------------------------------------------------------------
  // The only achievements a walk earns; every other one counts runs alone.
  AchievementDef(
    id: 'walk_first',
    category: AchCategory.walking,
    tier: AchTier.street,
    target: 1,
    metric: _walks,
    format: _count,
  ),
  AchievementDef(
    id: 'walk_10k',
    category: AchCategory.walking,
    tier: AchTier.chrome,
    target: 10000,
    metric: _walked,
    format: _km,
  ),
  AchievementDef(
    id: 'walk_50k',
    category: AchCategory.walking,
    tier: AchTier.ice,
    target: 50000,
    metric: _walked,
    format: _km,
  ),
  AchievementDef(
    id: 'walk_100k',
    category: AchCategory.walking,
    tier: AchTier.legend,
    target: 100000,
    metric: _walked,
    format: _km,
  ),
];

// Top-level metric accessors — const list entries cannot hold closures.
double _totalDistance(LifetimeStats s) => s.totalDistanceMeters;
double _totalSeconds(LifetimeStats s) => s.totalSeconds;
double _longestDistance(LifetimeStats s) => s.longestRunMeters;
double _longestSeconds(LifetimeStats s) => s.longestRunSeconds;
double _missions(LifetimeStats s) => s.missionsCompleted.toDouble();
double _sprawlPrimeMissions(LifetimeStats s) => _packMissions(s, 'sprawl_prime');
double _nullTideMissions(LifetimeStats s) => _packMissions(s, 'null_tide');
double _samhainMissions(LifetimeStats s) => _packMissions(s, 'samhain');
double _hallowsEve(LifetimeStats s) => s.hallowsEveRuns.toDouble();
double _samhainRuns(LifetimeStats s) => s.samhainRuns.toDouble();
double _samhainYears(LifetimeStats s) => s.samhainYears.toDouble();
double _walks(LifetimeStats s) => s.walks.toDouble();
double _walked(LifetimeStats s) => s.walkedMeters;

/// Cleared missions belonging to one pack, recognised by the id prefix its
/// missions share. `test/campaign_test.dart` holds every bundled pack to this
/// table, so a pack cannot ship without its achievements matching it.
double _packMissions(LifetimeStats s, String packId) {
  final prefix = kPackMissionPrefixes[packId]!;
  return s.completedMissionIds.where((id) => id.startsWith(prefix)).length.toDouble();
}

/// Mission id prefix per pack, e.g. `sp01` for SPRAWL PRIME.
const Map<String, String> kPackMissionPrefixes = {'sprawl_prime': 'sp', 'null_tide': 'nt', 'samhain': 'sh'};
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

/// An achievement's name by [id], in the language of [l].
String achievementTitle(L l, String id) => switch (id) {
  'dist_5k' => l.achDist5kTitle,
  'dist_25k' => l.achDist25kTitle,
  'dist_50k' => l.achDist50kTitle,
  'dist_100k' => l.achDist100kTitle,
  'dist_150k' => l.achDist150kTitle,
  'dist_250k' => l.achDist250kTitle,
  'dist_500k' => l.achDist500kTitle,
  'dist_1000k' => l.achDist1000kTitle,
  'time_1h' => l.achTime1hTitle,
  'time_5h' => l.achTime5hTitle,
  'time_10h' => l.achTime10hTitle,
  'time_25h' => l.achTime25hTitle,
  'time_50h' => l.achTime50hTitle,
  'time_100h' => l.achTime100hTitle,
  'single_5k' => l.achSingle5kTitle,
  'single_10k' => l.achSingle10kTitle,
  'single_15k' => l.achSingle15kTitle,
  'single_half' => l.achSingleHalfTitle,
  'single_30m' => l.achSingle30mTitle,
  'single_45m' => l.achSingle45mTitle,
  'single_60m' => l.achSingle60mTitle,
  'single_90m' => l.achSingle90mTitle,
  'single_120m' => l.achSingle120mTitle,
  'mission_1' => l.achMission1Title,
  'mission_3' => l.achMission3Title,
  'mission_5' => l.achMission5Title,
  'mission_10' => l.achMission10Title,
  'nt_1' => l.achNt1Title,
  'nt_5' => l.achNt5Title,
  'nt_10' => l.achNt10Title,
  'mission_20' => l.achMission20Title,
  'beats_100' => l.achBeats100Title,
  'perfect_1' => l.achPerfect1Title,
  'perfect_5' => l.achPerfect5Title,
  'chase_5' => l.achChase5Title,
  'chase_25' => l.achChase25Title,
  'chase_100' => l.achChase100Title,
  'pace_600' => l.achPace600Title,
  'pace_530' => l.achPace530Title,
  'pace_500' => l.achPace500Title,
  'pace_430' => l.achPace430Title,
  'streak_1' => l.achStreak1Title,
  'streak_2' => l.achStreak2Title,
  'streak_3' => l.achStreak3Title,
  'streak_4' => l.achStreak4Title,
  'streak_6' => l.achStreak6Title,
  'streak_8' => l.achStreak8Title,
  'streak_12' => l.achStreak12Title,
  'streak_26' => l.achStreak26Title,
  'streak_52' => l.achStreak52Title,
  'runs_10' => l.achRuns10Title,
  'runs_50' => l.achRuns50Title,
  'runs_100' => l.achRuns100Title,
  'runs_200' => l.achRuns200Title,
  'days_30' => l.achDays30Title,
  'days_100' => l.achDays100Title,
  'night_5' => l.achNight5Title,
  'night_25' => l.achNight25Title,
  'dawn_5' => l.achDawn5Title,
  'kcal_10k' => l.achKcal10kTitle,
  'kcal_50k' => l.achKcal50kTitle,
  'week_15k' => l.achWeek15kTitle,
  'week_30k' => l.achWeek30kTitle,
  'week_50k' => l.achWeek50kTitle,
  'sh_1' => l.achSh1Title,
  'sh_4' => l.achSh4Title,
  'hallows_eve' => l.achHallowsEveTitle,
  'samhain_5' => l.achSamhain5Title,
  'samhain_years_2' => l.achSamhainYears2Title,
  'walk_first' => l.achWalkFirstTitle,
  'walk_10k' => l.achWalk10kTitle,
  'walk_50k' => l.achWalk50kTitle,
  'walk_100k' => l.achWalk100kTitle,
  _ => id,
};

/// What an achievement asks for, by [id], in the language of [l].
String achievementDescription(L l, String id) => switch (id) {
  'dist_5k' => l.achDist5kDesc,
  'dist_25k' => l.achDist25kDesc,
  'dist_50k' => l.achDist50kDesc,
  'dist_100k' => l.achDist100kDesc,
  'dist_150k' => l.achDist150kDesc,
  'dist_250k' => l.achDist250kDesc,
  'dist_500k' => l.achDist500kDesc,
  'dist_1000k' => l.achDist1000kDesc,
  'time_1h' => l.achTime1hDesc,
  'time_5h' => l.achTime5hDesc,
  'time_10h' => l.achTime10hDesc,
  'time_25h' => l.achTime25hDesc,
  'time_50h' => l.achTime50hDesc,
  'time_100h' => l.achTime100hDesc,
  'single_5k' => l.achSingle5kDesc,
  'single_10k' => l.achSingle10kDesc,
  'single_15k' => l.achSingle15kDesc,
  'single_half' => l.achSingleHalfDesc,
  'single_30m' => l.achSingle30mDesc,
  'single_45m' => l.achSingle45mDesc,
  'single_60m' => l.achSingle60mDesc,
  'single_90m' => l.achSingle90mDesc,
  'single_120m' => l.achSingle120mDesc,
  'mission_1' => l.achMission1Desc,
  'mission_3' => l.achMission3Desc,
  'mission_5' => l.achMission5Desc,
  'mission_10' => l.achMission10Desc,
  'nt_1' => l.achNt1Desc,
  'nt_5' => l.achNt5Desc,
  'nt_10' => l.achNt10Desc,
  'mission_20' => l.achMission20Desc,
  'beats_100' => l.achBeats100Desc,
  'perfect_1' => l.achPerfect1Desc,
  'perfect_5' => l.achPerfect5Desc,
  'chase_5' => l.achChase5Desc,
  'chase_25' => l.achChase25Desc,
  'chase_100' => l.achChase100Desc,
  'pace_600' => l.achPace600Desc,
  'pace_530' => l.achPace530Desc,
  'pace_500' => l.achPace500Desc,
  'pace_430' => l.achPace430Desc,
  'streak_1' => l.achStreak1Desc,
  'streak_2' => l.achStreak2Desc,
  'streak_3' => l.achStreak3Desc,
  'streak_4' => l.achStreak4Desc,
  'streak_6' => l.achStreak6Desc,
  'streak_8' => l.achStreak8Desc,
  'streak_12' => l.achStreak12Desc,
  'streak_26' => l.achStreak26Desc,
  'streak_52' => l.achStreak52Desc,
  'runs_10' => l.achRuns10Desc,
  'runs_50' => l.achRuns50Desc,
  'runs_100' => l.achRuns100Desc,
  'runs_200' => l.achRuns200Desc,
  'days_30' => l.achDays30Desc,
  'days_100' => l.achDays100Desc,
  'night_5' => l.achNight5Desc,
  'night_25' => l.achNight25Desc,
  'dawn_5' => l.achDawn5Desc,
  'kcal_10k' => l.achKcal10kDesc,
  'kcal_50k' => l.achKcal50kDesc,
  'week_15k' => l.achWeek15kDesc,
  'week_30k' => l.achWeek30kDesc,
  'week_50k' => l.achWeek50kDesc,
  'sh_1' => l.achSh1Desc,
  'sh_4' => l.achSh4Desc,
  'hallows_eve' => l.achHallowsEveDesc,
  'samhain_5' => l.achSamhain5Desc,
  'samhain_years_2' => l.achSamhainYears2Desc,
  'walk_first' => l.achWalkFirstDesc,
  'walk_10k' => l.achWalk10kDesc,
  'walk_50k' => l.achWalk50kDesc,
  'walk_100k' => l.achWalk100kDesc,
  _ => '',
};
