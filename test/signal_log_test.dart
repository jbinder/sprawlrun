import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/signal_log_repository.dart';
import 'package:sprawl_run/models/signal_log.dart';

import 'support/fakes.dart';

/// The signal log: the one thing on the timeline that is stored, because it
/// has no other record anywhere.
void main() {
  final now = DateTime(2026, 10, 2, 12);
  late Directory root;
  late SignalLogRepository log;

  setUp(() {
    root = tempRoot('signal-log');
    log = SignalLogRepository(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  SignalLogEntry at(DateTime when, [String text = 'line']) =>
      SignalLogEntry(at: when, kind: SignalKind.ambient, from: 'WREN', text: text);

  test('what has been sent survives a re-plan; what was pending is replaced', () async {
    final sent = at(now.subtract(const Duration(hours: 3)), 'already fired');
    final pending = at(now.add(const Duration(hours: 3)), 'old plan');
    await log.record([sent, pending], now.subtract(const Duration(hours: 4)));

    // Re-planned later: the earlier line has fired, the pending one was
    // cancelled when the new plan was scheduled.
    final fresh = at(now.add(const Duration(hours: 5)), 'new plan');
    final after = await log.record([fresh], now);

    expect(after.map((e) => e.text), containsAll(['already fired', 'new plan']));
    expect(after.map((e) => e.text), isNot(contains('old plan')));
  });

  test('only what has been sent shows; the plan stays hidden until its time', () async {
    await log.record([at(now.subtract(const Duration(minutes: 1)), 'past'), at(now.add(const Duration(minutes: 1)), 'future')],
        now.subtract(const Duration(hours: 1)));
    expect((await log.sent(now)).map((e) => e.text), ['past']);
  });

  test('switching signals off clears what was pending and keeps the history', () async {
    await log.record([at(now.subtract(const Duration(hours: 1)), 'past'), at(now.add(const Duration(hours: 1)), 'future')],
        now.subtract(const Duration(hours: 2)));
    final after = await log.record(const [], now);
    expect(after.map((e) => e.text), ['past']);
  });

  test('old entries age out', () async {
    final ancient = at(now.subtract(SignalLogRepository.keepFor + const Duration(days: 1)), 'ancient');
    final recent = at(now.subtract(const Duration(days: 2)), 'recent');
    final after = await log.replaceAll([ancient, recent], now);
    expect(after.map((e) => e.text), ['recent']);
  });

  test('the log is capped however it was filled', () async {
    final flood = [
      for (var i = 0; i < SignalLogRepository.maxEntries + 50; i++) at(now.subtract(Duration(minutes: i)), 'line $i'),
    ];
    final after = await log.replaceAll(flood, now);
    expect(after, hasLength(SignalLogRepository.maxEntries));
    expect(after.first.text, 'line 0', reason: 'the newest are the ones kept');
  });

  test('it reads back what it wrote', () async {
    await log.record([at(now.subtract(const Duration(hours: 1)), 'kept')], now.subtract(const Duration(hours: 2)));
    final reread = await SignalLogRepository(root).sent(now);
    expect(reread.single.text, 'kept');
    expect(reread.single.kind, SignalKind.ambient);
    expect(reread.single.from, 'WREN');
  });

  test('merging adds what is missing and never duplicates', () async {
    final shared = at(now.subtract(const Duration(hours: 5)), 'on both');
    await log.replaceAll([shared], now);
    final after = await log.merge([shared, at(now.subtract(const Duration(hours: 2)), 'only incoming')], now);
    expect(after.map((e) => e.text), ['only incoming', 'on both']);
  });

  test('a corrupt file is kept aside, not overwritten', () async {
    root.createSync(recursive: true);
    File('${root.path}/signals.json').writeAsStringSync('{ not json');
    expect(await log.loadAll(), isEmpty);
    expect(
      root.listSync().whereType<File>().any((f) => f.path.contains('signals.json.corrupt-')),
      isTrue,
    );
  });

  test('one malformed entry costs that entry, not the log', () async {
    root.createSync(recursive: true);
    File('${root.path}/signals.json').writeAsStringSync(
      '[{"at":"2026-10-01T10:00:00.000","kind":"ambient","from":"WREN","text":"fine"},'
      '{"at":"nonsense","kind":"ambient","from":"WREN","text":"bad date"},'
      '{"at":"2026-10-01T09:00:00.000","kind":"unknown","from":"WREN","text":"bad kind"}]',
    );
    expect((await log.loadAll()).map((e) => e.text), ['fine']);
  });
}
