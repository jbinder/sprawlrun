import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/signal_log_repository.dart';
import 'package:sprawl_run/models/signal_log.dart';

import 'support/fakes.dart';

/// The signal archive: the one thing on THE WIRE that is stored, because it
/// has no other record anywhere. References, not text; kept for good; one file
/// per year so a launch never pays for the whole of it.
void main() {
  final now = DateTime(2026, 10, 2, 12);
  late Directory root;
  late SignalLogRepository log;

  setUp(() {
    root = tempRoot('signal-log');
    log = SignalLogRepository(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  SignalLogEntry at(DateTime when, String ref) =>
      SignalLogEntry(at: when, kind: SignalKind.ambient, from: 'WREN', ref: ref);
  File yearFile(int year) => File('${root.path}/signals/$year.json');
  Future<List<String>> refs() async => (await SignalLogRepository(root).loadAll()).map((e) => e.ref).toList();

  group('the plan', () {
    test('what has been sent survives a re-plan; what was pending is replaced', () async {
      await log.record([
        at(now.subtract(const Duration(hours: 3)), 'fired'),
        at(now.add(const Duration(hours: 3)), 'old-plan'),
      ], now.subtract(const Duration(hours: 4)));
      await log.record([at(now.add(const Duration(hours: 5)), 'new-plan')], now);

      expect(await refs(), ['new-plan', 'fired']);
    });

    test('only what has been sent counts as sent', () async {
      await log.record([
        at(now.subtract(const Duration(minutes: 1)), 'past'),
        at(now.add(const Duration(minutes: 1)), 'future'),
      ], now.subtract(const Duration(hours: 1)));
      expect((await log.sent(now)).map((e) => e.ref), ['past']);
    });

    test('switching signals off clears what was pending and keeps the history', () async {
      await log.record([
        at(now.subtract(const Duration(hours: 1)), 'past'),
        at(now.add(const Duration(hours: 1)), 'future'),
      ], now.subtract(const Duration(hours: 2)));
      await log.record(const [], now);
      expect(await refs(), ['past']);
    });

    test('a re-plan that changes nothing does not rewrite the file', () async {
      final plan = [at(now.add(const Duration(hours: 2)), 'same')];
      await log.record(plan, now);
      final written = yearFile(2026).lastModifiedSync();

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await log.record(plan, now);
      expect(yearFile(2026).lastModifiedSync(), written);
    });
  });

  group('the yearly split', () {
    test('each year lives in its own file', () async {
      await log.replaceAll([at(DateTime(2024, 5, 1), 'a'), at(DateTime(2025, 5, 1), 'b'), at(DateTime(2026, 5, 1), 'c')]);
      expect([2024, 2025, 2026].map((y) => yearFile(y).existsSync()), everyElement(isTrue));
    });

    test('a launch reads only the years that can hold something pending', () async {
      // The whole point of the split: years of history on disk, and a re-plan
      // that never loads them.
      await log.replaceAll([for (var y = 2016; y <= 2026; y++) at(DateTime(y, 3, 1), 'y$y')]);

      final fresh = SignalLogRepository(root);
      await fresh.record([at(now.add(const Duration(hours: 4)), 'plan')], now);
      expect(fresh.yearsInMemory, {2026});
    });

    test('a closed year is never rewritten', () async {
      await log.replaceAll([at(DateTime(2025, 6, 1), 'old'), at(DateTime(2026, 6, 1), 'new')]);
      final closed = yearFile(2025).lastModifiedSync();

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await SignalLogRepository(root).record([at(now.add(const Duration(hours: 4)), 'plan')], now);
      expect(yearFile(2025).lastModifiedSync(), closed);
    });

    test('a plan across New Year lands in both years, and December stays sent', () async {
      final eve = DateTime(2026, 12, 30, 10);
      await log.record([
        at(DateTime(2026, 12, 31, 9), 'dec'),
        at(DateTime(2027, 1, 2, 9), 'jan'),
      ], eve);
      expect(yearFile(2027).existsSync(), isTrue);

      // Opened again in mid-January: both have fired, and the old plan's
      // January entry — once pending, now past — is kept, not dropped.
      await SignalLogRepository(root).record(const [], DateTime(2027, 1, 15));
      expect(await refs(), ['jan', 'dec']);
    });

    test('nothing ages out and nothing is capped', () async {
      final decade = [for (var i = 0; i < 22 * 52 * 10; i++) at(now.subtract(Duration(hours: i * 7)), 'r$i')];
      await log.replaceAll(decade);
      expect(await refs(), hasLength(decade.length));
    });

    test('one damaged year is set aside; the rest still read', () async {
      await log.replaceAll([at(DateTime(2025, 6, 1), 'kept'), at(DateTime(2026, 6, 1), 'lost')]);
      yearFile(2026).writeAsStringSync('{ not json');

      expect(await refs(), ['kept']);
      expect(
        Directory('${root.path}/signals').listSync().any((f) => f.path.contains('2026.json.corrupt-')),
        isTrue,
      );
    });
  });

  group('the single file it replaced', () {
    void writeLegacy(String json) {
      root.createSync(recursive: true);
      File('${root.path}/signals.json').writeAsStringSync(json);
    }

    test('is split into years and then removed', () async {
      writeLegacy(
        '[{"at":"2025-12-31T10:00:00.000","kind":"ambient","from":"WREN","ref":"old"},'
        '{"at":"2026-01-01T10:00:00.000","kind":"ambient","from":"WREN","ref":"new"}]',
      );
      expect(await refs(), ['new', 'old']);
      expect(yearFile(2025).existsSync() && yearFile(2026).existsSync(), isTrue);
      expect(File('${root.path}/signals.json').existsSync(), isFalse);
    });

    test('loses nothing if a split was interrupted and runs again', () async {
      // The yearly file was written but the old one not yet removed.
      await log.replaceAll([at(DateTime(2026, 1, 1, 10), 'already')]);
      writeLegacy('[{"at":"2026-01-01T10:00:00.000","kind":"ambient","from":"WREN","ref":"already"},'
          '{"at":"2026-02-01T10:00:00.000","kind":"ambient","from":"WREN","ref":"pending-copy"}]');
      expect(await refs(), ['pending-copy', 'already']);
    });

    test('an entry written with its full text reads, by referencing it', () async {
      writeLegacy('[{"at":"2026-10-01T10:00:00.000","kind":"ambient","from":"WREN","text":"The gulls have moved inland."}]');
      expect(await refs(), [signalRef('The gulls have moved inland.')]);
    });
  });

  test('an entry is a reference, not the text — a few dozen bytes', () async {
    await log.replaceAll([at(now.subtract(const Duration(hours: 1)), signalRef('A line long enough to matter.'))]);
    final raw = yearFile(2026).readAsStringSync();
    expect(raw, isNot(contains('A line long enough')));
    expect(raw.length, lessThan(120));
  });

  test('it reads back what it wrote, figures included', () async {
    await log.replaceAll([
      SignalLogEntry(
        at: now.subtract(const Duration(hours: 1)),
        kind: SignalKind.debrief,
        from: 'MARROW',
        ref: 'abcd1234',
        figures: const SignalFigures(value: 12, target: 30, unit: 'MIN', weeks: 3),
      ),
    ]);
    final reread = (await SignalLogRepository(root).sent(now)).single;
    expect(reread.kind, SignalKind.debrief);
    expect(reread.figures?.value, 12);
    expect(reread.figures?.weeks, 3);
  });

  test('merging adds what is missing and never duplicates', () async {
    final shared = at(now.subtract(const Duration(hours: 5)), 'both');
    await log.replaceAll([shared]);
    await log.merge([shared, at(DateTime(2025, 3, 1), 'other-year')]);
    expect(await refs(), ['both', 'other-year']);
  });

  test('one malformed entry costs that entry, not the year', () async {
    Directory('${root.path}/signals').createSync(recursive: true);
    yearFile(2026).writeAsStringSync(
      '[{"at":"2026-10-01T10:00:00.000","kind":"ambient","from":"WREN","ref":"ok"},'
      '{"at":"nonsense","kind":"ambient","from":"WREN","ref":"bad-date"},'
      '{"at":"2026-10-01T09:00:00.000","kind":"unknown","from":"WREN","ref":"bad-kind"}]',
    );
    expect(await refs(), ['ok']);
  });
}
