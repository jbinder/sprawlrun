import '../models/profile.dart';
import '../models/run_record.dart';
import '../services/achievement_engine.dart';

/// One-off repairs to stored data, applied in order on load.
///
/// [Profile.dataVersion] records how far a device has been brought. A profile
/// written before migrations existed reads as 0 and gets every step; a fresh
/// install has nothing to repair but goes through the same path, which is what
/// keeps the two cases from drifting apart.
///
/// A step must be safe to run on data it has already touched — a crash between
/// the migration and the save means it runs again next launch.
abstract final class Migrations {
  /// Bump this and add a step when stored data needs repairing. Steps are
  /// keyed by the version they *produce*, so [current] is the last key.
  static const int current = 1;

  static const Map<int, Profile Function(Profile, List<RunRecord>)> _steps = {
    // 1: achievements added to the catalogue after a runner earned them were
    // credited to whatever run came next, so unlock dates read as a pile on
    // one day. Replay the log and date each to the run that earned it.
    1: _redateAchievements,
  };

  /// The profile brought up to [current], or null when it already is.
  ///
  /// Pure: the caller decides when to persist, so a failure part way leaves
  /// the stored profile untouched and the migration simply runs again.
  static Profile? apply(Profile profile, List<RunRecord> runLog) {
    if (profile.dataVersion >= current) return null;

    var out = profile;
    for (var v = profile.dataVersion + 1; v <= current; v++) {
      final step = _steps[v];
      if (step != null) out = step(out, runLog);
    }
    return out.copyWith(dataVersion: current);
  }

  static Profile _redateAchievements(Profile profile, List<RunRecord> runLog) {
    final earlier = AchievementEngine.backfill(runLog, profile.streakGoal, profile.unlockedAchievements);
    if (earlier.isEmpty) return profile;
    return profile.copyWith(
      unlockedAchievements: {...profile.unlockedAchievements, ...earlier},
    );
  }
}
