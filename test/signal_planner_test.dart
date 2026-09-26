import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/mission.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/services/signal_planner.dart';

import 'support/fakes.dart';

void main() {
  // A Monday, mid-morning, so "later today" and "already past" are both
  // reachable from it.
  final monday = DateTime(2026, 9, 28, 10, 0);

  Mission mission({SignalPool signals = const SignalPool()}) => Mission(
    id: 'sp01',
    packId: 'sprawl_prime',
    order: 1,
    codename: 'DEAD DROP',
    title: 'Dead Drop on Ninsei',
    location: '',
    brief: '',
    objective: '',
    debrief: '',
    suggestedGoal: const RunGoal(GoalType.time, 900),
    beats: const [],
    signals: signals,
  );

  MissionPack pack({SignalPool signals = const SignalPool()}) =>
      MissionPack(id: 'sprawl_prime', title: 'SPRAWL PRIME', tagline: '', missions: const [], signals: signals);

  const missionPool = SignalPool(
    reminder: [
      Signal(from: 'KESTREL', text: 'Package is still in the drop on Ninsei.'),
      Signal(from: 'KESTREL', text: 'Courier job is still open.'),
    ],
  );
  const packPool = SignalPool(
    reminder: [Signal(from: 'KESTREL', text: "Work's on the board if you want it.")],
  );

  const everyDay = SignalSettings(
    remindersEnabled: true,
    weekdays: {
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
      DateTime.saturday,
      DateTime.sunday,
    },
    minutesFromMidnight: 7 * 60,
  );

  List<PlannedSignal> planWith({
    SignalSettings settings = everyDay,
    List<dynamic>? runs,
    SignalPool? missionSignals,
    SignalPool? packSignals,
    DateTime? now,
  }) => SignalPlanner.plan(
    now: now ?? monday,
    settings: settings,
    runLog: (runs ?? const []).cast(),
    pack: pack(signals: packSignals ?? packPool),
    nextMission: missionSignals == null ? null : mission(signals: missionSignals),
  );

  group('when reminders are sent', () {
    test('one per enabled weekday, at the chosen time', () {
      const mwf = SignalSettings(
        remindersEnabled: true,
        weekdays: {DateTime.monday, DateTime.wednesday, DateTime.friday},
        minutesFromMidnight: 18 * 60 + 30,
      );
      final planned = planWith(settings: mwf);

      expect(planned.map((p) => p.at.weekday), [DateTime.monday, DateTime.wednesday, DateTime.friday]);
      for (final p in planned) {
        expect(p.at.hour, 18);
        expect(p.at.minute, 30);
        expect(p.kind, SignalKind.reminder);
      }
    });

    test('a time that has already passed today is not scheduled for today', () {
      // 07:00 on a Monday, planned at 10:00 — Monday is gone, the week is not.
      final planned = planWith();
      expect(planned.first.at.day, isNot(monday.day));
      expect(planned.first.at.weekday, DateTime.tuesday);
      expect(planned, hasLength(6), reason: 'the rest of the week');
    });

    test('a time still to come today is scheduled for today', () {
      final planned = planWith(settings: everyDay.copyWith(minutesFromMidnight: 18 * 60));
      expect(planned.first.at.day, monday.day);
      expect(planned, hasLength(7));
    });

    test('nothing is planned when reminders are off, or no day is chosen', () {
      expect(planWith(settings: everyDay.copyWith(remindersEnabled: false)), isEmpty);
      expect(planWith(settings: everyDay.copyWith(weekdays: const {})), isEmpty);
    });

    test('a day already run is left alone', () {
      final planned = planWith(
        settings: everyDay.copyWith(minutesFromMidnight: 18 * 60),
        runs: [run(at: monday.subtract(const Duration(hours: 2)))],
      );
      expect(planned.any((p) => p.at.day == monday.day), isFalse, reason: 'already been out');
      expect(planned, hasLength(6));
    });

    test('a discarded run does not count as having been out', () {
      final planned = planWith(
        settings: everyDay.copyWith(minutesFromMidnight: 18 * 60),
        runs: [run(at: monday.subtract(const Duration(hours: 2)), outcome: RunOutcome.discarded)],
      );
      expect(planned.any((p) => p.at.day == monday.day), isTrue);
    });
  });

  group('what they say', () {
    test('the waiting mission and the generic pool are both drawn on', () {
      // Generic lines are not a fallback here but extra variety, which is what
      // keeps a runner who opens the app daily from seeing the same two lines.
      final planned = planWith(missionSignals: missionPool);
      final said = planned.map((p) => p.text).toSet();

      expect(said, containsAll(missionPool.reminder.map((s) => s.text)));
      expect(said, contains(packPool.reminder.first.text));
    });

    test('a finished campaign falls back to the generic pool', () {
      final planned = planWith();
      expect(planned.map((p) => p.text).toSet(), {packPool.reminder.first.text});
    });

    test('nothing is sent when there is nothing written', () {
      expect(planWith(packSignals: const SignalPool()), isEmpty);
    });

    test('consecutive days differ', () {
      final planned = planWith(missionSignals: missionPool);
      for (var i = 1; i < planned.length; i++) {
        expect(planned[i].text, isNot(planned[i - 1].text), reason: 'day $i repeats the day before');
      }
    });

    test('re-planning never changes what a given day was going to say', () {
      final first = planWith(missionSignals: missionPool);
      // Later the same day, after a settings change or an app restart.
      final second = planWith(missionSignals: missionPool, now: monday.add(const Duration(hours: 5)));

      final byDay = {for (final p in first) p.at.day: p.text};
      for (final p in second) {
        if (byDay.containsKey(p.at.day)) expect(p.text, byDay[p.at.day]);
      }
    });
  });

  test('ids stay inside the reserved range, clear of the run notice', () {
    final planned = planWith(missionSignals: missionPool);
    expect(planned.map((p) => p.id).toSet(), hasLength(planned.length), reason: 'ids collide');
    for (final p in planned) {
      expect(p.id, greaterThanOrEqualTo(SignalPlanner.reminderBase));
      expect(p.id, lessThan(SignalPlanner.ambientBase));
    }
  });

  group('signal noise', () {
    const ambientPool = SignalPool(
      ambient: [
        Signal(from: 'PACHINKO', text: 'Someone is selling your gait signature in the night market.'),
        Signal(from: 'SYSTEM', text: 'Traffic advisory: the Ninsei strip is at capacity.'),
        Signal(from: 'SIX', text: 'Two couriers retired this week.'),
      ],
    );

    List<PlannedSignal> ambientPlan({int perWeek = 5, DateTime? now, SignalPool? pool}) => SignalPlanner.plan(
      now: now ?? monday,
      settings: SignalSettings(ambientPerWeek: perWeek),
      runLog: const [],
      pack: pack(signals: pool ?? ambientPool),
    ).where((p) => p.kind == SignalKind.ambient).toList();

    test('off until asked for', () {
      expect(ambientPlan(perWeek: 0), isEmpty);
    });

    test('as many a week as the runner asked for', () {
      expect(ambientPlan(perWeek: 3), hasLength(3));
      expect(ambientPlan(perWeek: 10), hasLength(10));
    });

    test('never in the small hours', () {
      for (final p in ambientPlan(perWeek: 14)) {
        expect(
          p.at.hour,
          inInclusiveRange(SignalPlanner.quietUntilHour, SignalPlanner.quietFromHour - 1),
          reason: 'fired at ${p.at}',
        );
      }
    });

    test('spread across the week rather than bunched into one day', () {
      final days = ambientPlan(perWeek: 7).map((p) => p.at.day).toSet();
      expect(days.length, greaterThan(3), reason: 'all landed on the same day or two');
    });

    test('sent whether or not the runner has been out', () {
      // Unlike a reminder: going running does not silence the city.
      final withRun = SignalPlanner.plan(
        now: monday,
        settings: const SignalSettings(ambientPerWeek: 5),
        runLog: [run(at: monday.subtract(const Duration(hours: 1)))],
        pack: pack(signals: ambientPool),
      ).where((p) => p.kind == SignalKind.ambient);

      expect(withRun, hasLength(5));
    });

    test('re-planning keeps the same schedule', () {
      final first = ambientPlan();
      final second = ambientPlan();
      expect(second.map((p) => p.at), first.map((p) => p.at));
      expect(second.map((p) => p.text), first.map((p) => p.text));
    });

    test('nothing is sent when nothing is written', () {
      expect(ambientPlan(pool: const SignalPool()), isEmpty);
    });

    test('nothing repeats until the pool is exhausted', () {
      // The reason the copy has to be plentiful: at two a day a small pool is
      // noticed as a loop within days.
      final planned = ambientPlan(perWeek: 3);
      expect(planned.map((p) => p.text).toSet(), hasLength(3), reason: 'repeated inside one week');
    });

    test('ids stay in their own range, clear of the reminders', () {
      final planned = ambientPlan(perWeek: 9);
      expect(planned.map((p) => p.id).toSet(), hasLength(planned.length));
      for (final p in planned) {
        expect(p.id, greaterThanOrEqualTo(SignalPlanner.ambientBase));
        expect(p.id, lessThan(SignalPlanner.ambientBase + 100));
      }
    });
  });
}
