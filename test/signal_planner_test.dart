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
      // Within one: slots are counted from a fixed epoch, so a week rarely
      // starts on a slot boundary and the slot straddling `now` may already have
      // been. Asking for ten and getting nine is not worth moving the schedule
      // around for; asking for ten and getting five was the bug. What the rate
      // really has to hold over time is the fortnight test below.
      expect(ambientPlan(perWeek: 3).length, inInclusiveRange(2, 4));
      expect(ambientPlan(perWeek: 10).length, inInclusiveRange(9, 11));
      expect(ambientPlan(perWeek: 14).length, inInclusiveRange(13, 15));
    });

    test('slots already past today are simply gone, not crammed in later', () {
      // Planned at 10:00, so anything the day had scheduled for the small
      // hours has been and gone.
      expect(ambientPlan(perWeek: 3).length, lessThanOrEqualTo(3));
      expect(ambientPlan(perWeek: 3), isNotEmpty);
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

      final withoutRun = ambientPlan(perWeek: 5);
      expect(withRun.length, withoutRun.length, reason: 'a run should change nothing here');
      expect(withRun, isNotEmpty);
    });

    test('re-planning later the same day does not push them further away', () {
      // The app re-plans on every launch. Anchoring to the moment of planning
      // would slide the whole schedule forward each time, so a runner who
      // opens the app a few times a day would never hear one.
      final first = ambientPlan();
      final later = ambientPlan(now: monday.add(const Duration(hours: 6)));

      final stillAhead = first.where((p) => p.at.isAfter(monday.add(const Duration(hours: 6))));
      expect(stillAhead, isNotEmpty, reason: 'nothing left to compare');
      for (final p in stillAhead) {
        expect(
          later.any((q) => q.at == p.at && q.text == p.text),
          isTrue,
          reason: '${p.at} moved or changed after re-planning',
        );
      }
    });

    test('two a day still means two a day after a fortnight of re-planning', () {
      // The regression this guards: with slots measured from the moment of
      // planning, or from today's midnight, every launch re-rolled the schedule
      // and any slot whose turn had passed was dropped rather than kept. Asking
      // for fourteen a week quietly delivered half that. So walk a fortnight,
      // re-planning four times a day as an ordinary runner would, and count what
      // would actually have been sent.
      final start = DateTime(monday.year, monday.month, monday.day);
      final sent = <DateTime>{};
      for (var tick = 0; tick < 14 * 4; tick++) {
        final at = start.add(Duration(hours: 6 * tick));
        for (final p in ambientPlan(perWeek: 14, now: at)) {
          // Anything still ahead of the next re-plan survives to fire.
          if (p.at.isBefore(at.add(const Duration(hours: 6)))) sent.add(p.at);
        }
      }
      expect(sent, hasLength(28), reason: 'lost signals to re-planning');
    });

    test('a slot pencilled in today is still there tomorrow', () {
      final today = ambientPlan(perWeek: 14);
      final tomorrow = ambientPlan(perWeek: 14, now: monday.add(const Duration(days: 1)));
      final overlap = today.where((p) => p.at.isAfter(monday.add(const Duration(days: 1))));

      expect(overlap, isNotEmpty, reason: 'nothing left to compare');
      for (final p in overlap) {
        expect(
          tomorrow.any((q) => q.at == p.at && q.text == p.text && q.id == p.id),
          isTrue,
          reason: '${p.at} moved, changed or was dropped a day later',
        );
      }
    });

    test('nothing is sent when nothing is written', () {
      expect(ambientPlan(pool: const SignalPool()), isEmpty);
    });

    test('nothing repeats until the pool is exhausted', () {
      // The reason the copy has to be plentiful: at two a day a small pool is
      // noticed as a loop within days.
      final planned = ambientPlan(perWeek: 3);
      expect(
        planned.map((p) => p.text).toSet(),
        hasLength(planned.length),
        reason: 'repeated inside one week from a pool of ${ambientPool.ambient.length}',
      );
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
