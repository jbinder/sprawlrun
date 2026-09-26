import '../models/mission.dart';
import '../models/profile.dart';
import '../models/run_record.dart';

/// A signal placed at a moment in the future, ready to be handed to the
/// platform scheduler.
class PlannedSignal {
  const PlannedSignal({
    required this.id,
    required this.at,
    required this.kind,
    required this.from,
    required this.text,
  });

  /// Stable within its reserved range, so a reschedule replaces its own work
  /// and never touches the run notice.
  final int id;

  final DateTime at;
  final SignalKind kind;
  final String from;
  final String text;
}

enum SignalKind { reminder, ambient }

/// Decides which signals to send and when.
///
/// Pure, and deliberately so: the text of a notification is fixed when it is
/// scheduled, not when it fires — no Dart runs at fire time — so everything
/// interesting happens here and can be tested without a device.
///
/// Nothing in this file speaks. A [PlannedSignal] carries text for a
/// notification and never reaches the narrator.
abstract final class SignalPlanner {
  /// Reminder ids live in `[reminderBase, reminderBase + 100)`, ambient in the
  /// hundred above. The run notice is 75416 and must not be disturbed.
  static const int reminderBase = 7000;
  static const int ambientBase = 7100;

  /// How far ahead to schedule. The app re-plans on every launch, on every
  /// settings change and after every run, so a week is ample slack for a
  /// runner who opens the app rarely.
  static const Duration horizon = Duration(days: 7);

  /// Ambient signals stay out of these hours. Reminders do not: the runner
  /// picked their time on purpose.
  static const int quietFromHour = 22;
  static const int quietUntilHour = 7;

  static List<PlannedSignal> plan({
    required DateTime now,
    required SignalSettings settings,
    required List<RunRecord> runLog,
    MissionPack? pack,
    Mission? nextMission,
  }) {
    return [
      ..._reminders(now: now, settings: settings, runLog: runLog, pack: pack, nextMission: nextMission),
    ];
  }

  static List<PlannedSignal> _reminders({
    required DateTime now,
    required SignalSettings settings,
    required List<RunRecord> runLog,
    MissionPack? pack,
    Mission? nextMission,
  }) {
    if (!settings.remindersEnabled || settings.weekdays.isEmpty) return const [];

    // Both pools, not one or the other: the generic lines are what stop a
    // runner who goes out daily from seeing the same two messages all week.
    // A finished campaign simply has no mission half left.
    final pool = [...?nextMission?.signals.reminder, ...?pack?.signals.reminder];
    if (pool.isEmpty) return const [];

    final out = <PlannedSignal>[];
    final today = DateTime(now.year, now.month, now.day);

    for (var day = 0; day < horizon.inDays; day++) {
      final date = DateTime(today.year, today.month, today.day + day);
      if (!settings.weekdays.contains(date.weekday)) continue;

      final at = date.add(Duration(minutes: settings.minutesFromMidnight));
      if (!at.isAfter(now)) continue;
      // Already been out today; no need to be asked again.
      if (_ranOn(runLog, date)) continue;

      final signal = pool[_indexFor(date, pool.length)];
      out.add(
        PlannedSignal(
          id: reminderBase + day,
          at: at,
          kind: SignalKind.reminder,
          from: signal.from,
          text: signal.text,
        ),
      );
    }
    return out;
  }

  static bool _ranOn(List<RunRecord> runLog, DateTime date) => runLog.any(
    (r) =>
        r.countsForStats &&
        r.startedAt.year == date.year &&
        r.startedAt.month == date.month &&
        r.startedAt.day == date.day,
  );

  /// Which line a given day gets.
  ///
  /// Seeded by the date rather than drawn at random, so re-planning never
  /// changes the message already pencilled in for Thursday, while consecutive
  /// days still differ.
  static int _indexFor(DateTime date, int length) {
    final ordinal = date.difference(DateTime(2020)).inDays;
    // Odd stride, so a pool of any size cycles through all of it rather than
    // landing on the same few entries.
    return (ordinal * 7) % length;
  }
}
