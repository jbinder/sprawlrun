import '../models/achievement.dart';
import '../models/mission.dart';
import '../models/profile.dart';
import '../models/run_record.dart';
import '../models/signal_log.dart';

/// What happened at a moment on the timeline.
enum TimelineKind { signal, run, achievement, codex }

/// One line of the timeline.
class TimelineEntry {
  const TimelineEntry({
    required this.at,
    required this.kind,
    required this.title,
    this.body,
    this.signalKind,
    this.run,
    this.cleared = false,
  });

  final DateTime at;
  final TimelineKind kind;

  /// The speaker for a signal; otherwise what kind of moment this was.
  final String title;
  final String? body;

  /// Set for [TimelineKind.signal] only.
  final SignalKind? signalKind;

  /// Set for [TimelineKind.run] only.
  final RunRecord? run;

  /// For a run: whether this was the run that first cleared its operation.
  final bool cleared;
}

/// The runner's life in the Sprawl, in order.
///
/// Built when it is shown, never stored. Only the signals come from a file of
/// their own — they have no other record — while runs, cleared operations,
/// achievements and codex entries are all already dated in the run log and
/// the profile. Storing them again would be a second copy free to drift from
/// the first.
abstract final class Timeline {
  static List<TimelineEntry> build({
    required List<SignalLogEntry> signals,
    required List<RunRecord> runs,
    required Profile profile,
    required List<MissionPack> packs,
  }) {
    final entries = <TimelineEntry>[
      for (final s in signals)
        TimelineEntry(at: s.at, kind: TimelineKind.signal, title: s.from, body: s.text, signalKind: s.kind),
    ];

    // Oldest first, so "the first success" and "the first mention" are found by
    // walking forward rather than by searching.
    final counted = runs.where((r) => r.countsForStats).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    final codexTitles = {
      for (final pack in packs)
        for (final mission in pack.missions)
          for (final entry in mission.codex) entry.id: entry.title,
    };

    final clearedMissions = <String>{};
    final seenCodex = <String>{};
    for (final run in counted) {
      final id = run.missionId;
      final cleared = id != null && run.outcome == RunOutcome.success && clearedMissions.add(id);
      entries.add(
        TimelineEntry(at: run.startedAt, kind: TimelineKind.run, title: _runTitle(run, cleared), run: run, cleared: cleared),
      );

      // Intel is banked only by a successful operation — a failed run hears the
      // lines and loses them, exactly as `AppState.completeRun` files it. So
      // only a success's mentions count, and only for entries the profile
      // actually holds; a mention alone is not an unlock.
      if (run.outcome != RunOutcome.success) continue;
      for (final event in run.story) {
        final ref = event.ref;
        if (event.kind != StoryEventKind.codex || ref == null) continue;
        if (!profile.unlockedCodex.contains(ref) || !seenCodex.add(ref)) continue;
        final title = codexTitles[ref];
        // An entry from a pack that has since been removed has no title to
        // show; leaving it out beats a line that reads as an id.
        if (title == null) continue;
        entries.add(
          TimelineEntry(
            at: run.startedAt.add(Duration(milliseconds: (event.atSeconds * 1000).round())),
            kind: TimelineKind.codex,
            title: 'INTEL INTERCEPTED',
            body: title,
          ),
        );
      }
    }

    final catalogue = {for (final a in kAchievements) a.id: a};
    profile.unlockedAchievements.forEach((id, at) {
      final def = catalogue[id];
      if (def == null) return;
      entries.add(TimelineEntry(at: at, kind: TimelineKind.achievement, title: 'UNLOCKED', body: def.title));
    });

    entries.sort((a, b) => b.at.compareTo(a.at));
    return entries;
  }

  static String _runTitle(RunRecord run, bool cleared) {
    final codename = run.missionCodename;
    if (codename == null) return 'FREE RUN';
    if (cleared) return 'CLEARED — $codename';
    return switch (run.outcome) {
      RunOutcome.success => 'OPERATION — $codename',
      _ => 'ATTEMPT — $codename',
    };
  }
}
