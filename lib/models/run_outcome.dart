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
    this.codexLost = const [],
    this.missionUnlocked,
  });

  final RunRecord record;

  /// Earned by this run, in wall order.
  final List<AchievementDef> newAchievements;

  /// Codex entries this run unlocked for the first time. Only a successful
  /// run recovers anything; a replayed mission hears the same lines again, and
  /// those are not recoveries either.
  final List<CodexEntry> codexRecovered;

  /// Entries heard on a run that did not succeed — intercepted, not banked.
  /// Named, because the runner already heard them; the reason to go back.
  final List<CodexEntry> codexLost;

  /// Codename of the mission this run just unlocked, if any.
  final String? missionUnlocked;

  bool get hasUnlocks => newAchievements.isNotEmpty || codexRecovered.isNotEmpty || missionUnlocked != null;
}
