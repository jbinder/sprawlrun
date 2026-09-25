import '../models/achievement.dart';
import '../models/profile.dart';
import '../models/run_record.dart';
import '../models/stats.dart';
import 'stats_service.dart';

/// Turns lifetime stats into the achievement wall.
///
/// Nothing here is stateful. The profile stores only *when* each achievement
/// was first earned, for display; whether it is earned is always re-derived,
/// so a fixed stats bug or a deleted run corrects the wall automatically.
abstract final class AchievementEngine {
  /// Ids earned by [stats] that are not already in [alreadyEarned].
  static List<AchievementDef> newlyEarned(LifetimeStats stats, Set<String> alreadyEarned) =>
      kAchievements.where((a) => !alreadyEarned.contains(a.id) && a.isEarned(stats)).toList();

  /// Unlock dates the run log supports but the profile does not have.
  ///
  /// Two cases, both caused by the catalogue growing after the running did:
  /// an achievement earned before its definition existed has no date at all,
  /// and one swept up by a later run carries that run's date rather than the
  /// date it was really earned.
  ///
  /// The log is replayed run by run and each achievement dated to the run that
  /// crossed its threshold. A recorded date is only ever moved *earlier* —
  /// the replay can prove an achievement was already earned by some run, never
  /// that it was earned later than the runner was told.
  ///
  /// Returns only the changes.
  static Map<String, DateTime> backfill(
    List<RunRecord> runLog,
    StreakGoal goal,
    Map<String, DateTime> recorded,
  ) {
    if (runLog.isEmpty) return const {};

    // Oldest first: the run log is stored newest-first.
    final chronological = List<RunRecord>.from(runLog)..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    // Only achievements the runner has actually earned can be dated, and once
    // the last of them is placed the replay can stop. Without this the loop
    // always walks the entire log looking for achievements that will never be
    // earned, which is quadratic in the number of runs.
    final finalStats = StatsService.lifetime(chronological, goal);
    final out = <String, DateTime>{};
    final pending = kAchievements.where((a) => a.isEarned(finalStats)).toList();
    if (pending.isEmpty) return const {};
    for (var i = 0; i < chronological.length && pending.isNotEmpty; i++) {
      // Stats as they stood once this run was logged.
      final stats = StatsService.lifetime(chronological.sublist(0, i + 1), goal);
      // Dated to the end of the run: that is the moment the threshold was
      // crossed, and it matches what a live unlock would have recorded.
      final at = chronological[i].endedAt;
      pending.removeWhere((def) {
        if (!def.isEarned(stats)) return false;
        final known = recorded[def.id];
        if (known == null || at.isBefore(known)) out[def.id] = at;
        return true;
      });
    }
    return out;
  }

  /// The whole wall, earned first, then closest-to-earned.
  static List<AchievementView> wall(LifetimeStats stats, Map<String, DateTime> earnedAt) {
    final views = kAchievements
        .map(
          (def) => AchievementView(
            def: def,
            earned: def.isEarned(stats),
            progress: def.progressOf(stats),
            earnedAt: earnedAt[def.id],
          ),
        )
        .toList();

    // Ties fall back to catalogue order: `List.sort` is not stable, and on a
    // fresh install every card ties at zero progress.
    final order = {for (var i = 0; i < kAchievements.length; i++) kAchievements[i].id: i};
    views.sort((a, b) {
      if (a.earned != b.earned) return a.earned ? -1 : 1;
      if (a.earned) {
        final at = a.earnedAt, bt = b.earnedAt;
        if (at != null && bt != null && at != bt) return bt.compareTo(at);
        final tier = a.def.tier.index.compareTo(b.def.tier.index);
        if (tier != 0) return tier;
      } else {
        final progress = b.progress.compareTo(a.progress);
        if (progress != 0) return progress;
      }
      return order[a.def.id]!.compareTo(order[b.def.id]!);
    });
    return views;
  }

  static int earnedCount(LifetimeStats stats) => kAchievements.where((a) => a.isEarned(stats)).length;

  /// The handful of near-misses worth surfacing on the dashboard.
  static List<AchievementView> nextUp(LifetimeStats stats, {int take = 3}) =>
      wall(stats, const {}).where((v) => !v.earned && v.progress > 0).take(take).toList();
}
