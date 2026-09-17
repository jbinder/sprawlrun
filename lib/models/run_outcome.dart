import 'achievement.dart';
import 'mission.dart';
import 'run_record.dart';

/// A single run plus everything it earned, handed to the summary screen.
///
/// Carries the full definitions rather than titles: the reveal needs tier,
/// category and description to give a LEGEND a different moment from a STREET.
class RunOutcomeReport {
  const RunOutcomeReport({
    required this.record,
    this.newAchievements = const [],
    this.codexRecovered = const [],
    this.missionUnlocked,
  });

  final RunRecord record;

  /// Earned by this run, in wall order.
  final List<AchievementDef> newAchievements;

  /// Codex entries this run unlocked for the first time. A replayed mission
  /// hears the same lines again; those are not recoveries.
  final List<CodexEntry> codexRecovered;

  /// Codename of the mission this run just unlocked, if any.
  final String? missionUnlocked;

  bool get hasUnlocks => newAchievements.isNotEmpty || codexRecovered.isNotEmpty || missionUnlocked != null;
}
