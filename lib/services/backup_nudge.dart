import '../models/profile.dart';
import '../models/run_record.dart';

/// Whether to ask the runner to export, and what to tell them.
///
/// Derived, never stored: the number of runs at risk is counted from the log
/// against the last export, so it cannot drift the way a saved counter would.
class BackupNudge {
  const BackupNudge({required this.runsAtRisk, required this.since});

  /// Runs recorded since the last export — the ones that exist only here.
  final int runsAtRisk;

  /// How long since the last export, or since the first run at risk if no
  /// export has ever been made.
  final Duration since;

  /// Enough unsaved runs to be worth interrupting for.
  static const int runsThreshold = 10;

  /// Or enough time, for a runner who goes out rarely but has still built up
  /// something they would miss.
  static const Duration ageThreshold = Duration(days: 28);

  /// What the runner is shown, or null when there is nothing worth saying.
  ///
  /// Silent when nothing is at risk, whatever the calendar says: four quiet
  /// weeks with no runs is not a risk, and being told otherwise teaches a
  /// runner to ignore the panel for the week it matters.
  static BackupNudge? of({
    required Profile profile,
    required List<RunRecord> runLog,
    required DateTime now,
  }) {
    final exported = profile.lastExportAt;
    final atRisk = runLog
        .where((r) => r.countsForStats && (exported == null || r.startedAt.isAfter(exported)))
        .toList();
    if (atRisk.isEmpty) return null;

    // When the runner last bought themselves quiet, by exporting or by
    // dismissing. A dismissal from before the last export has already been
    // answered by it. Dismissing buys the same quiet as exporting — another ten
    // runs, or four weeks — because otherwise the dismiss button would only
    // last until tomorrow.
    final snoozed = profile.backupNudgeSnoozedAt;
    final quietFrom = snoozed != null && (exported == null || snoozed.isAfter(exported))
        ? snoozed
        : exported;

    final int countSince;
    final DateTime measuredFrom;
    if (quietFrom == null) {
      // Nothing has ever been exported or dismissed, so the clock runs from the
      // oldest run that is at risk.
      countSince = atRisk.length;
      measuredFrom = atRisk.map((r) => r.startedAt).reduce((a, b) => a.isBefore(b) ? a : b);
    } else {
      countSince = atRisk.where((r) => r.startedAt.isAfter(quietFrom)).length;
      measuredFrom = quietFrom;
    }

    final age = now.difference(measuredFrom);
    if (countSince < runsThreshold && age < ageThreshold) return null;

    return BackupNudge(runsAtRisk: atRisk.length, since: age);
  }
}
