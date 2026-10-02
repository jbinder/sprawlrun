import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/mission.dart';
import 'package:sprawl_run/services/signal_scheduler.dart';
import 'package:sprawl_run/state/app_state.dart';
import 'package:sprawl_run/screens/timeline_screen.dart';
import 'package:sprawl_run/widgets/signal_watcher.dart';

import 'support/fakes.dart';

/// Reading a signal in full after tapping it. The shade truncates and a
/// dismissed notification is gone, so this is the only way back to the text.
void main() {
  const long = Signal(
    from: 'PACHINKO',
    text: 'Someone is selling your gait signature in the night market. Badly. '
        'It has you at forty-one kilos and walking with a limp you do not have.',
  );

  group('the payload a notification carries', () {
    test('round-trips', () {
      final back = SignalScheduler.decodePayload(SignalScheduler.encodePayload(long));
      expect(back?.from, long.from);
      expect(back?.text, long.text);
    });

    test('survives quotes and newlines in the copy', () {
      const awkward = Signal(from: 'WREN', text: 'She said "no", then—\nnothing. {not json}');
      final back = SignalScheduler.decodePayload(SignalScheduler.encodePayload(awkward));
      expect(back?.text, awkward.text);
    });

    test('anything unreadable is nothing, never a crash', () {
      // A tap must not be able to take the app down, whatever posted it.
      for (final payload in [null, '', 'not json at all', '[]', '42', '{}', '{"from":"X"}', '{"from":"X","text":""}']) {
        expect(SignalScheduler.decodePayload(payload), isNull, reason: 'payload: $payload');
      }
    });
  });

  group('collecting taps from the platform', () {
    test('a tap with nobody listening is replayed to the first subscriber', () async {
      // The cold-start case, and the one that was broken: the launch tap is
      // read while the app is still on the boot screen.
      final taps = SignalTaps();
      addTearDown(taps.close);
      taps.deliver(id: 7101, payload: SignalScheduler.encodePayload(long));

      expect(await taps.stream.first, isA<Signal>().having((s) => s.text, 'text', long.text));
    });

    test('one tap reported by both routes shows once', () async {
      // A cold start is reported by getNotificationAppLaunchDetails and a warm
      // one by the callback. A launch that is somehow both is still one tap.
      final taps = SignalTaps();
      addTearDown(taps.close);
      final seen = <Signal>[];
      taps.stream.listen(seen.add);

      final payload = SignalScheduler.encodePayload(long);
      taps.deliver(id: 7101, payload: payload);
      taps.deliver(id: 7101, payload: payload);
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(1));
    });

    test('two different signals both arrive', () async {
      final taps = SignalTaps();
      addTearDown(taps.close);
      final seen = <Signal>[];
      taps.stream.listen(seen.add);

      taps.deliver(id: 7101, payload: SignalScheduler.encodePayload(long));
      taps.deliver(id: 7102, payload: SignalScheduler.encodePayload(const Signal(from: 'SIX', text: 'Rates are up.')));
      await Future<void>.delayed(Duration.zero);

      expect(seen.map((s) => s.from), ['PACHINKO', 'SIX']);
    });

    test('an old build\'s notification carries no payload, and is dropped quietly', () async {
      final taps = SignalTaps();
      addTearDown(taps.close);
      final seen = <Signal>[];
      taps.stream.listen(seen.add);

      taps.deliver(id: 7101, payload: null);
      await Future<void>.delayed(Duration.zero);

      expect(seen, isEmpty);
    });
  });

  testWidgets('the watcher can be torn down and rebuilt without losing taps', (tester) async {
    // A single-subscription stream throws on a second listen, which would kill
    // every later tap for the life of the app.
    final taps = StreamController<Signal>.broadcast();
    addTearDown(taps.close);
    final state = await _boot(tester, taps.stream);

    await tester.pumpWidget(_app(state));
    await _transition(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(state));
    await _transition(tester);

    taps.add(long);
    await _transition(tester);
    expect(find.byType(TimelineScreen), findsOneWidget);
  });

  testWidgets('a tapped signal opens the timeline with the whole message', (tester) async {
    final taps = StreamController<Signal>();
    addTearDown(taps.close);
    final state = await _boot(tester, taps.stream);

    await tester.pumpWidget(_app(state));
    await _transition(tester);
    expect(find.byType(TimelineScreen), findsNothing);

    taps.add(long);
    await _transition(tester);

    expect(find.byType(TimelineScreen), findsOneWidget);
    expect(find.text('PACHINKO'), findsOneWidget);
    expect(find.text(long.text), findsOneWidget, reason: 'the whole line, not a truncation');

    // And it stays readable: back out and the signal is not gone with it.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await _transition(tester);
    expect(find.byType(TimelineScreen), findsNothing);
  });

  testWidgets('a tap that launched the app is not lost', (tester) async {
    // The tap arrives while the plugin initialises, long before the UI is up.
    final taps = StreamController<Signal>();
    addTearDown(taps.close);
    taps.add(long);

    final state = await _boot(tester, taps.stream);
    await tester.pumpWidget(_app(state));
    await _transition(tester);

    expect(find.text(long.text), findsOneWidget);
  });

  testWidgets('a second tap replaces an open timeline rather than stacking one', (tester) async {
    final taps = StreamController<Signal>();
    addTearDown(taps.close);
    final state = await _boot(tester, taps.stream);

    await tester.pumpWidget(_app(state));
    await _transition(tester);

    taps.add(long);
    await _transition(tester);
    taps.add(const Signal(from: 'SIX', text: 'Two couriers retired this week.'));
    await _transition(tester);

    expect(find.byType(TimelineScreen), findsOneWidget);
    expect(find.text('Two couriers retired this week.'), findsOneWidget);

    // One back press returns home, not to a stale timeline beneath.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await _transition(tester);
    expect(find.byType(TimelineScreen), findsNothing);
  });
}

Widget _app(AppState state) => ChangeNotifierProvider.value(
  value: state,
  child: MaterialApp(home: SignalWatcher(child: Scaffold(body: Builder(builder: (_) => const SizedBox())))),
);

Future<AppState> _boot(WidgetTester tester, Stream<Signal> taps) async {
  final root = tempRoot('signal-popup');
  addTearDown(() => root.deleteSync(recursive: true));

  late AppState state;
  await tester.runAsync(() async {
    state = AppState(
      profiles: ProfileRepository(root),
      runs: RunRepository(Directory('${root.path}/runs')),
      missions: MissionRepository(externalDir: Directory('${root.path}/packs'), bundle: _DiskBundle()),
      narrator: FakeNarrator(),
      signals: SignalScheduler(schedule: (_) async {}, cancelAll: () async {}, taps: taps),
    );
    await state.load();
  });
  return state;
}

class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.view(File(key).readAsBytesSync().buffer);

  @override
  Future<String> loadString(String key, {bool cache = true}) async => File(key).readAsStringSync();
}

/// Waits out a route transition. Not `pumpAndSettle`: the timeline's grid
/// backdrop animates forever, so it never settles — the other screen tests
/// pump fixed durations for the same reason.
///
/// Three frames, not two. A pushed route spends its first frame offstage while
/// the navigator measures heroes, and a pump is one frame however long it is,
/// so `pump(); pump(600ms)` ends with the screen built but still invisible to
/// a finder.
Future<void> _transition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 600));
}
