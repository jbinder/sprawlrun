import '../models/achievement.dart';
import '../models/stats.dart';

/// Turns lifetime stats into the achievement wall.
///
/// Nothing here is stateful. The profile stores only *when* each achievement
/// was first earned, for display; whether it is earned is always re-derived,
/// so a fixed stats bug or a deleted run corrects the wall automatically.
abstract final class AchievementEngine {
  /// Ids earned by [stats] that are not already in [alreadyEarned].
  static List<AchievementDef> newlyEarned(LifetimeStats stats, Set<String> alreadyEarned) =>
      kAchievements.where((a) => !alreadyEarned.contains(a.id) && a.isEarned(stats)).toList();

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

    views.sort((a, b) {
      if (a.earned != b.earned) return a.earned ? -1 : 1;
      if (a.earned) {
        final at = a.earnedAt, bt = b.earnedAt;
        if (at != null && bt != null) return bt.compareTo(at);
        return a.def.tier.index.compareTo(b.def.tier.index);
      }
      return b.progress.compareTo(a.progress);
    });
    return views;
  }

  static int earnedCount(LifetimeStats stats) => kAchievements.where((a) => a.isEarned(stats)).length;

  /// The handful of near-misses worth surfacing on the dashboard.
  static List<AchievementView> nextUp(LifetimeStats stats, {int take = 3}) =>
      wall(stats, const {}).where((v) => !v.earned && v.progress > 0).take(take).toList();
}
