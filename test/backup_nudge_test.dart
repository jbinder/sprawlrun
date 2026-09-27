import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/services/backup_nudge.dart';

import 'support/fakes.dart';

/// The arithmetic behind the backup nudge. It has to be quiet enough to be
/// believed and loud enough to be acted on.
void main() {
  final now = DateTime(2026, 6, 15, 10);

  BackupNudge? nudge({Profile profile = const Profile(), int runs = 0, Duration spacing = const Duration(days: 1), DateTime? first}) {
    final start = first ?? now.subtract(spacing * runs);
    return BackupNudge.of(
      profile: profile,
      runLog: [for (var i = 0; i < runs; i++) run(at: start.add(spacing * i))],
      now: now,
    );
  }

  test('a fresh install is left alone', () {
    expect(nudge(), isNull);
  });

  test('a runner with a handful of runs is not nagged', () {
    expect(nudge(runs: BackupNudge.runsThreshold - 1), isNull);
  });

  test('ten unsaved runs is worth interrupting for', () {
    final n = nudge(runs: BackupNudge.runsThreshold);
    expect(n, isNotNull);
    expect(n!.runsAtRisk, BackupNudge.runsThreshold);
  });

  test('few runs but a long time since the last export still asks', () {
    // A runner who goes out once a month has built something they would miss.
    final n = nudge(
      profile: Profile(lastExportAt: now.subtract(const Duration(days: 40))),
      runs: 2,
      spacing: const Duration(days: 10),
    );
    expect(n, isNotNull);
    expect(n!.runsAtRisk, 2, reason: 'only the runs since the export are at risk');
  });

  test('silence when nothing is at risk, however long it has been', () {
    // Four quiet months with no runs is not a risk, and saying so would teach
    // the runner to ignore the panel for the week it matters.
    expect(
      BackupNudge.of(
        profile: Profile(lastExportAt: now.subtract(const Duration(days: 120))),
        runLog: const [],
        now: now,
      ),
      isNull,
    );
  });

  test('exporting counts only the runs that came after it', () {
    final exported = now.subtract(const Duration(days: 5));
    final n = BackupNudge.of(
      profile: Profile(lastExportAt: exported),
      runLog: [
        for (var i = 0; i < 20; i++) run(at: exported.subtract(Duration(days: i + 1))),
        for (var i = 0; i < 3; i++) run(at: exported.add(Duration(days: i + 1))),
      ],
      now: now,
    );
    expect(n, isNull, reason: 'three runs since an export is not worth a panel');
  });

  test('a discarded run is not something to lose', () {
    expect(
      BackupNudge.of(
        profile: const Profile(),
        runLog: [
          for (var i = 0; i < 12; i++)
            run(at: now.subtract(Duration(days: i + 1)), outcome: RunOutcome.discarded),
        ],
        now: now,
      ),
      isNull,
    );
  });

  test('dismissing buys the same quiet as exporting', () {
    final profile = Profile(backupNudgeSnoozedAt: now.subtract(const Duration(days: 1)));
    final runs = [for (var i = 0; i < 12; i++) run(at: now.subtract(Duration(days: i + 2)))];

    expect(
      BackupNudge.of(profile: profile, runLog: runs, now: now),
      isNull,
      reason: 'dismissed yesterday, and nothing has happened since',
    );

    // Ten more runs after the dismissal and it is fair to ask again.
    expect(
      BackupNudge.of(
        profile: profile,
        runLog: [...runs, for (var i = 0; i < 10; i++) run(at: now.subtract(Duration(hours: i + 1)))],
        now: now,
      ),
      isNotNull,
    );
  });

  test('a dismissal from before the last export is spent', () {
    // The export answered it, so the snooze must not go on suppressing the
    // panel for a runner who has since recorded a fortnight of runs.
    final profile = Profile(
      backupNudgeSnoozedAt: now.subtract(const Duration(days: 30)),
      lastExportAt: now.subtract(const Duration(days: 20)),
    );
    expect(
      BackupNudge.of(
        profile: profile,
        runLog: [for (var i = 0; i < 12; i++) run(at: now.subtract(Duration(days: i + 1)))],
        now: now,
      ),
      isNotNull,
    );
  });

  test('the count is derived, so a re-import of the same runs changes nothing', () {
    final runs = [for (var i = 0; i < 11; i++) run(at: now.subtract(Duration(days: i + 1)))];
    final first = BackupNudge.of(profile: const Profile(), runLog: runs, now: now);
    final again = BackupNudge.of(profile: const Profile(), runLog: [...runs], now: now);
    expect(first!.runsAtRisk, again!.runsAtRisk);
  });
}
