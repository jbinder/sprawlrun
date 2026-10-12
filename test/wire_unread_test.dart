import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sprawl_run/data/backup.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/data/signal_log_repository.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/signal_log.dart';
import 'package:sprawl_run/screens/timeline_screen.dart';
import 'package:sprawl_run/services/signal_scheduler.dart';
import 'package:sprawl_run/state/app_state.dart';

import 'support/fakes.dart';

/// What is new on THE WIRE: every signal sent since it was last opened.
/// Opening it marks them all read; nothing else does.
void main() {
  SignalLogEntry sent(DateTime at, {SignalKind kind = SignalKind.reminder}) =>
      SignalLogEntry(at: at, kind: kind, from: 'WREN', ref: 'r${at.millisecondsSinceEpoch}');

  group('the archive', () {
    late Directory root;
    late SignalLogRepository log;

    setUp(() {
      root = tempRoot('wire-unread');
      log = SignalLogRepository(root);
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('counts what was sent after the last visit, and nothing still pending', () async {
      final now = DateTime(2026, 10, 11, 12);
      final readAt = DateTime(2026, 10, 10, 12);
      await log.record([sent(DateTime(2026, 10, 9, 8)), sent(DateTime(2026, 10, 12, 8))], DateTime(2026, 10, 1));

      expect(await log.anySent(after: readAt, now: now), isFalse,
          reason: 'one before the visit, one not sent yet');

      await log.record([sent(DateTime(2026, 10, 11, 8))], DateTime(2026, 10, 10, 13));
      expect(await log.anySent(after: readAt, now: now), isTrue);
    });

    test('every kind counts, ambient noise included', () async {
      await log.record([sent(DateTime(2026, 10, 11, 8), kind: SignalKind.ambient)], DateTime(2026, 10, 1));
      expect(await log.anySent(after: DateTime(2026, 10, 10), now: DateTime(2026, 10, 11, 12)), isTrue);
    });

    test('a visit before New Year still sees what came in December', () async {
      // The launch re-plan only reads this year; a signal on 30 December
      // must not miss the dot because the calendar turned.
      await SignalLogRepository(root).record([sent(DateTime(2026, 12, 30, 8))], DateTime(2026, 12, 1));
      final fresh = SignalLogRepository(root);
      await fresh.record(const [], DateTime(2027, 1, 2));

      expect(await fresh.anySent(after: DateTime(2026, 12, 20), now: DateTime(2027, 1, 2)), isTrue);
    });
  });

  group('the app', () {
    Future<(AppState, Directory)> boot({Profile? profile, List<SignalLogEntry> history = const []}) async {
      final root = tempRoot('wire-unread-app');
      addTearDown(() => root.deleteSync(recursive: true));
      final profiles = ProfileRepository(root);
      if (profile != null) await profiles.save(profile);
      if (history.isNotEmpty) await SignalLogRepository(root).record(history, DateTime(2000));

      final state = AppState(
        profiles: profiles,
        runs: RunRepository(Directory('${root.path}/runs')),
        missions: MissionRepository(externalDir: Directory('${root.path}/packs'), bundle: _DiskBundle()),
        narrator: FakeNarrator(),
        signals: SignalScheduler(schedule: (_) async {}, cancelAll: () async {}),
      );
      await state.load();
      return (state, root);
    }

    test('after the update, everything already archived starts as read', () async {
      // A profile from 0.5.0: no wireReadAt, and a history of signals.
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final (state, root) = await boot(
        profile: const Profile(dataVersion: 1),
        history: [sent(yesterday), sent(yesterday.subtract(const Duration(days: 30)))],
      );

      expect(state.hasUnreadSignals, isFalse);
      expect(state.profile.wireReadAt, isNotNull);
      expect((await ProfileRepository(root).load()).wireReadAt, state.profile.wireReadAt,
          reason: 'kept, or the next launch would start it again and swallow what came in between');
    });

    test('a signal sent since the last visit lights the dot, and opening THE WIRE clears it', () async {
      final lastVisit = DateTime.now().subtract(const Duration(days: 2));
      final (state, root) = await boot(
        profile: Profile(dataVersion: 1, wireReadAt: lastVisit),
        history: [sent(lastVisit.add(const Duration(days: 1)))],
      );
      expect(state.hasUnreadSignals, isTrue);

      final before = await state.markSignalsRead();
      expect(before, lastVisit, reason: 'so THE WIRE can mark what was new for this visit');
      expect(state.hasUnreadSignals, isFalse);
      expect((await ProfileRepository(root).load()).wireReadAt!.isAfter(lastVisit), isTrue);

      await state.refreshUnreadSignals();
      expect(state.hasUnreadSignals, isFalse, reason: 'and it stays clear');
    });

    test('knows when the next signal is due, to look again then', () async {
      final (state, _) = await boot();
      // The weekly debrief is on by default.
      expect(state.nextSignalAt, isNotNull);
      expect(state.nextSignalAt!.isAfter(DateTime.now()), isTrue);
    });

    test('restoring a backup from before this existed starts it too', () async {
      final (state, _) = await boot();
      final archive = BackupArchive(
        exportedAt: DateTime.now(),
        profile: const Profile(dataVersion: 1),
        runs: const [],
        signals: [sent(DateTime.now().subtract(const Duration(days: 3)))],
      );
      await state.importBackup(archive, ImportMode.replace);

      expect(state.profile.wireReadAt, isNotNull);
      expect(state.hasUnreadSignals, isFalse, reason: 'a restored history is not news');
    });
  });

  test('the profile keeps the moment, and reads without it', () {
    final at = DateTime(2026, 10, 11, 9, 30);
    expect(Profile.fromJson(Profile(wireReadAt: at).toJson()).wireReadAt, at);
    expect(Profile.fromJson(const {}).wireReadAt, isNull);
  });

  testWidgets('THE WIRE marks what arrived since the last visit, and only that', (tester) async {
    final root = tempRoot('wire-unread-screen');
    addTearDown(() => root.deleteSync(recursive: true));
    final lastVisit = DateTime.now().subtract(const Duration(days: 1));

    late AppState state;
    await tester.runAsync(() async {
      state = AppState(
        profiles: ProfileRepository(root),
        runs: RunRepository(Directory('${root.path}/runs')),
        missions: MissionRepository(externalDir: Directory('${root.path}/packs'), bundle: _DiskBundle()),
        narrator: FakeNarrator(),
      );
      await state.load();
      await state.loadSignalArchive();
    });
    state.profile = state.profile.copyWith(wireReadAt: lastVisit);
    state.signalHistory = [
      SentSignal(at: lastVisit.add(const Duration(hours: 2)), kind: SignalKind.ambient, from: 'SIX', text: 'After.'),
      SentSignal(at: lastVisit.subtract(const Duration(hours: 2)), kind: SignalKind.reminder, from: 'WREN', text: 'Before.'),
    ];

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: TimelineScreen()),
    ));
    await tester.pump();

    expect(find.text('NEW'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('NEW'), matching: find.byType(Row)).evaluate().any(
        (row) => find.descendant(of: find.byWidget(row.widget), matching: find.text('SIX')).evaluate().isNotEmpty,
      ),
      isTrue,
      reason: 'on the signal sent after the visit',
    );
    expect(state.profile.wireReadAt!.isAfter(lastVisit), isTrue, reason: 'opening it read everything');
    expect(state.hasUnreadSignals, isFalse);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('NEW'), findsOneWidget, reason: 'the mark stays for the whole visit');
  });
}

class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.view(File(key).readAsBytesSync().buffer);

  @override
  Future<String> loadString(String key, {bool cache = true}) async => File(key).readAsStringSync();
}
