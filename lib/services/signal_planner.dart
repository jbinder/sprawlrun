import '../models/mission.dart';
import '../models/profile.dart';
import '../models/run_record.dart';
import '../models/signal_log.dart';
import '../models/stats.dart';

export '../models/signal_log.dart' show SignalKind, SignalFigures;

/// A signal placed at a moment in the future, ready to be handed to the
/// platform scheduler.
class PlannedSignal {
  const PlannedSignal({
    required this.id,
    required this.at,
    required this.kind,
    required this.from,
    required this.text,
    required this.ref,
    this.figures,
  });

  /// Stable within its reserved range, so a reschedule replaces its own work
  /// and never touches the run notice.
  final int id;

  final DateTime at;
  final SignalKind kind;
  final String from;

  /// The full text the notification shows.
  final String text;

  /// What the archive stores instead of [text]: a reference to the authored
  /// line, plus the [figures] for a debrief, which nobody authored.
  final String ref;
  final SignalFigures? figures;

  /// The same signal under another notification id — see
  /// `SignalScheduler.sparingShown`.
  PlannedSignal withId(int newId) =>
      PlannedSignal(id: newId, at: at, kind: kind, from: from, text: text, ref: ref, figures: figures);
}


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
  static const int debriefBase = 7200;

  /// When the weekly readout lands: Sunday evening, while the week can still be
  /// saved. A debrief that arrives on Monday is a post-mortem; this one is a
  /// last call, which is the more useful of the two.
  static const int debriefHour = 19;

  /// How far ahead to schedule. The app re-plans on every launch, on every
  /// settings change and after every run, so a week is ample slack for a
  /// runner who opens the app rarely.
  static const Duration horizon = Duration(days: 7);

  /// Ambient signals stay out of these hours. Reminders do not: the runner
  /// picked their time on purpose.
  static const int quietFromHour = 22;
  static const int quietUntilHour = 7;

  /// What ambient slots are counted from. Any fixed past date does; this one is
  /// before the app existed, so no slot number is ever negative.
  static final DateTime _epoch = DateTime(2020);

  /// The same day read as UTC, for counting whole days without a
  /// daylight-saving change making one of them 23 hours long.
  static final DateTime _epochDay = DateTime.utc(_epoch.year, _epoch.month, _epoch.day);

  static List<PlannedSignal> plan({
    required DateTime now,
    required SignalSettings settings,
    required List<RunRecord> runLog,
    MissionPack? pack,
    Mission? nextMission,
    StreakStatus? streak,
  }) {
    return [
      ..._reminders(now: now, settings: settings, runLog: runLog, pack: pack, nextMission: nextMission),
      ..._ambient(now: now, settings: settings, pack: pack, nextMission: nextMission),
      ..._debrief(now: now, settings: settings, pack: pack, streak: streak),
    ];
  }

  /// The week's readout, for the Sunday evening of the week [now] falls in.
  ///
  /// Exactly one Sunday is always inside the seven-day horizon, so this plans
  /// one or nothing. The text is fixed when it is scheduled rather than when it
  /// fires — no Dart runs then — which is accurate because finishing a run
  /// re-plans, so the figures are always as of the runner's last run.
  static List<PlannedSignal> _debrief({
    required DateTime now,
    required SignalSettings settings,
    MissionPack? pack,
    StreakStatus? streak,
  }) {
    if (!settings.debriefEnabled || streak == null) return const [];

    final figures = SignalFigures(
      value: streak.currentValue,
      target: streak.target,
      unit: streak.unitLabel,
      weeks: streak.weeks,
    );
    final outcome = figures.outcome;

    final pool = pack?.signals.debrief.forOutcome(outcome) ?? const [];
    if (pool.isEmpty) return const [];

    // Sunday of the current week, counting from Monday as the stats do.
    final today = DateTime(now.year, now.month, now.day);
    final sunday = today.add(Duration(days: DateTime.sunday - today.weekday));
    final at = DateTime(sunday.year, sunday.month, sunday.day, debriefHour);
    if (!at.isAfter(now)) return const [];

    final signal = pool[_indexFor(at, pool.length)];
    return [
      PlannedSignal(
        id: debriefBase,
        at: at,
        kind: SignalKind.debrief,
        from: signal.from,
        text: '${signal.text} ${figures.sentence}',
        ref: signalRef(signal.text),
        figures: figures,
      ),
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
          ref: signalRef(signal.text),
        ),
      );
    }
    return out;
  }

  /// Unprompted traffic: the city talking whether or not the runner is
  /// listening.
  ///
  /// Spread across the week rather than bunched, kept out of the small hours,
  /// and — unlike a reminder — sent whether or not the runner has been out.
  /// Going for a run is not a reason for the world to fall silent.
  static List<PlannedSignal> _ambient({
    required DateTime now,
    required SignalSettings settings,
    MissionPack? pack,
    Mission? nextMission,
  }) {
    if (settings.ambientPerWeek <= 0) return const [];

    final pool = [...?nextMission?.signals.ambient, ...?pack?.signals.ambient];
    if (pool.isEmpty) return const [];

    final out = <PlannedSignal>[];
    // Slots are measured in waking minutes, not wall-clock ones, so the quiet
    // hours are skipped over rather than folded into. Folding was worse than it
    // looks: seven of the twelve hours in a night slot are quiet, so at two a
    // day more than half of them were shoved to 07:00 and arrived as a clump.
    const horizonWaking = 7 * _wakingMinutesPerDay;
    final slot = horizonWaking ~/ settings.ambientPerWeek;
    final stride = _stride(pool.length);

    // Counted from a fixed epoch, not from today. Anchoring to the moment of
    // planning slides the whole schedule forward on every launch; anchoring to
    // today's midnight is nearly as bad, because it re-rolls every slot each day
    // and a slot whose turn has passed is dropped — asking for two a day
    // delivered one. From an epoch a slot always resolves to the same instant,
    // so re-planning leaves whatever is already pencilled in where it was.
    final nowWaking = _wakingMinutesAt(now);
    final horizonEnd = now.add(horizon);

    for (var k = nowWaking ~/ slot; k <= (nowWaking + horizonWaking) ~/ slot; k++) {
      // A fixed point inside the slot rather than a random one, derived from the
      // slot number so it never moves. The multiplier is odd and large, which
      // keeps successive slots from landing at the same time of day.
      final within = ((k * 2654435761 + 1013904223) & 0x7fffffff) % slot;
      final at = _wallClock(k * slot + within);
      if (!at.isAfter(now) || !at.isBefore(horizonEnd)) continue;

      final signal = pool[(k * stride) % pool.length];
      out.add(
        PlannedSignal(
          // Slots per horizon never approach a hundred, so the low two digits
          // are unique across everything planned at once.
          id: ambientBase + k % 100,
          at: at,
          kind: SignalKind.ambient,
          from: signal.from,
          text: signal.text,
          ref: signalRef(signal.text),
        ),
      );
    }
    return out;
  }

  /// Minutes of waking time in a day: the span the quiet hours leave.
  static const int _wakingMinutesPerDay = (quietFromHour - quietUntilHour) * 60;

  /// The instant that falls [minutes] of waking time after [_epoch].
  ///
  /// Quiet hours do not exist on this clock, which is what makes an even spread
  /// across a week an even spread across the hours a runner is actually awake.
  static DateTime _wallClock(int minutes) => DateTime(
    _epoch.year,
    _epoch.month,
    _epoch.day + minutes ~/ _wakingMinutesPerDay,
    quietUntilHour,
    minutes % _wakingMinutesPerDay,
  );

  /// The same clock read backwards. An instant inside the quiet hours reads as
  /// the moment the next waking day opens, so nothing is ever placed in them.
  static int _wakingMinutesAt(DateTime at) {
    final day = DateTime.utc(at.year, at.month, at.day).difference(_epochDay).inDays;
    final into = at.hour * 60 + at.minute - quietUntilHour * 60;
    if (into < 0) return day * _wakingMinutesPerDay;
    if (into >= _wakingMinutesPerDay) return (day + 1) * _wakingMinutesPerDay;
    return day * _wakingMinutesPerDay + into;
  }

  static bool _ranOn(List<RunRecord> runLog, DateTime date) => runLog.any(
    (r) =>
        r.countsForStats &&
        r.startedAt.year == date.year &&
        r.startedAt.month == date.month &&
        r.startedAt.day == date.day,
  );

  /// A step through the pool that is coprime with its length, so stepping by it
  /// visits every line before revisiting one.
  ///
  /// This is what stops the noise being noticed as a loop: nothing repeats until
  /// the pool is exhausted, for a pool of any size. Roughly six-tenths of the
  /// way along keeps consecutive picks far apart rather than adjacent.
  static int _stride(int length) {
    for (var s = (length * 0.618).floor(); s > 1; s--) {
      if (_gcd(s, length) == 1) return s;
    }
    return 1;
  }

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

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
