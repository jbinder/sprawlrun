import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/mission.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/models/signal_log.dart';
import 'package:sprawl_run/services/timeline.dart';

import 'support/fakes.dart';

/// The timeline is projected, not stored — so everything on it here comes from
/// the run log, the profile and the packs, plus the signal log.
void main() {
  final day = DateTime(2026, 10, 1, 8);

  MissionPack packWithCodex() => const MissionPack(
    id: 'sprawl_prime',
    title: 'SPRAWL PRIME',
    tagline: '',
    missions: [
      Mission(
        id: 'sp01',
        packId: 'sprawl_prime',
        order: 1,
        codename: 'SP01',
        title: 'Dead Drop',
        location: '',
        brief: '',
        objective: '',
        debrief: '',
        suggestedGoal: RunGoal(GoalType.time, 900),
        beats: [],
        codex: [CodexEntry(id: 'cdx_ninsei', title: 'Ninsei', category: 'PLACE', body: '…')],
      ),
    ],
  );

  List<TimelineEntry> build({
    List<SentSignal> signals = const [],
    List<RunRecord> runs = const [],
    Profile profile = const Profile(),
    List<MissionPack>? packs,
  }) => Timeline.build(signals: signals, runs: runs, profile: profile, packs: packs ?? [packWithCodex()]);

  test('newest first, everything interleaved', () {
    final entries = build(
      signals: [SentSignal(at: day.add(const Duration(hours: 3)), kind: SignalKind.ambient, from: 'WREN', text: 'later')],
      runs: [run(at: day)],
      profile: Profile(unlockedAchievements: {'dist_5k': day.add(const Duration(hours: 1))}),
    );
    expect(entries.map((e) => e.kind), [TimelineKind.signal, TimelineKind.achievement, TimelineKind.run]);
  });

  test('only the first success clears an operation', () {
    final entries = build(runs: [
      run(at: day, missionId: 'sp01', outcome: RunOutcome.failed),
      run(at: day.add(const Duration(days: 1)), missionId: 'sp01'),
      run(at: day.add(const Duration(days: 2)), missionId: 'sp01'),
    ]);
    final runs = entries.where((e) => e.kind == TimelineKind.run).toList().reversed.toList();
    expect(runs.map((e) => e.cleared), [false, true, false]);
    expect(runs.map((e) => e.title), ['ATTEMPT — SP01', 'CLEARED — SP01', 'OPERATION — SP01']);
  });

  test('a run nobody counts is not on it', () {
    expect(build(runs: [run(at: day, outcome: RunOutcome.discarded)]), isEmpty);
  });

  const unlocked = Profile(unlockedCodex: {'cdx_ninsei'});

  test('intel from a failed run is not on it — it was lost, not banked', () {
    // Found on the device: an entry showed as intercepted after a failed
    // attempt, while the codex itself correctly had it locked.
    const event = StoryEvent(atSeconds: 600, kind: StoryEventKind.codex, ref: 'cdx_ninsei');
    final entries = build(
      runs: [run(at: day, missionId: 'sp01', outcome: RunOutcome.failed, story: const [event])],
    );
    expect(entries.where((e) => e.kind == TimelineKind.codex), isEmpty);
  });

  test('a mention is not an unlock unless the profile holds the entry', () {
    const event = StoryEvent(atSeconds: 600, kind: StoryEventKind.codex, ref: 'cdx_ninsei');
    final entries = build(runs: [run(at: day, missionId: 'sp01', story: const [event])]);
    expect(entries.where((e) => e.kind == TimelineKind.codex), isEmpty);
  });

  test('intel is dated to the successful run that banked it, not an earlier failure', () {
    const event = StoryEvent(atSeconds: 600, kind: StoryEventKind.codex, ref: 'cdx_ninsei');
    final entries = build(
      profile: unlocked,
      runs: [
        run(at: day, missionId: 'sp01', outcome: RunOutcome.failed, story: const [event]),
        run(at: day.add(const Duration(days: 1)), missionId: 'sp01', story: const [event]),
      ],
    );
    expect(entries.where((e) => e.kind == TimelineKind.codex).single.at, day.add(const Duration(days: 1, minutes: 10)));
  });

  test('intel is dated to the moment in the run it was intercepted, once', () {
    const event = StoryEvent(atSeconds: 600, kind: StoryEventKind.codex, ref: 'cdx_ninsei');
    final entries = build(profile: unlocked, runs: [
      run(at: day, missionId: 'sp01', story: const [event]),
      run(at: day.add(const Duration(days: 1)), missionId: 'sp01', story: const [event]),
    ]);
    final intel = entries.where((e) => e.kind == TimelineKind.codex).toList();
    expect(intel, hasLength(1), reason: 'an entry unlocks once, however often it is mentioned');
    expect(intel.single.at, day.add(const Duration(minutes: 10)));
    expect(intel.single.body, 'Ninsei');
  });

  test('intel from a pack that is gone is left out rather than shown as an id', () {
    const event = StoryEvent(atSeconds: 60, kind: StoryEventKind.codex, ref: 'cdx_ninsei');
    final entries = build(profile: unlocked, runs: [run(at: day, story: const [event])], packs: const []);
    expect(entries.where((e) => e.kind == TimelineKind.codex), isEmpty);
  });

  test('an achievement the catalogue no longer has is left out', () {
    expect(build(profile: Profile(unlockedAchievements: {'retired_id': day})), isEmpty);
  });

  test('a signal keeps its speaker, its kind and its whole text', () {
    final entry = build(signals: [
      SentSignal(at: day, kind: SignalKind.debrief, from: 'MARROW', text: "Week's accounts, and they balance. 40 of 30 min."),
    ]).single;
    expect(entry.title, 'MARROW');
    expect(entry.signalKind, SignalKind.debrief);
    expect(entry.body, "Week's accounts, and they balance. 40 of 30 min.");
  });
}
