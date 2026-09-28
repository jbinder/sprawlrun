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
import 'package:sprawl_run/widgets/signal_popup.dart';

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

  testWidgets('the watcher can be torn down and rebuilt without losing taps', (tester) async {
    // A single-subscription stream throws on a second listen, which would kill
    // every later tap for the life of the app. Navigating in a way that
    // remounts the watcher must stay harmless.
    final taps = StreamController<Signal>.broadcast();
    addTearDown(taps.close);
    final state = await _boot(tester, taps.stream);

    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();

    taps.add(long);
    await tester.pumpAndSettle();
    expect(find.text(long.text), findsOneWidget);
  });

  testWidgets('a tapped signal is shown in full, and closing it is the end of it', (tester) async {
    final taps = StreamController<Signal>();
    addTearDown(taps.close);
    final state = await _boot(tester, taps.stream);

    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();
    expect(find.text(long.text), findsNothing);

    taps.add(long);
    await tester.pumpAndSettle();

    expect(find.text('INCOMING'), findsOneWidget);
    expect(find.text('PACHINKO'), findsOneWidget);
    expect(find.text(long.text), findsOneWidget, reason: 'the whole line, not a truncation');

    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
    expect(find.text(long.text), findsNothing, reason: 'nothing is kept; there is no inbox');
  });

  testWidgets('a tap that launched the app is not lost', (tester) async {
    // The tap arrives while the plugin initialises, long before the UI is up.
    // The stream buffers for exactly this reason.
    final taps = StreamController<Signal>();
    addTearDown(taps.close);
    taps.add(long);

    final state = await _boot(tester, taps.stream);
    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();

    expect(find.text(long.text), findsOneWidget);
  });

  testWidgets('a second signal does not stack a dialog on the first', (tester) async {
    final taps = StreamController<Signal>();
    addTearDown(taps.close);
    final state = await _boot(tester, taps.stream);

    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();

    taps.add(long);
    taps.add(const Signal(from: 'SIX', text: 'Two couriers retired this week.'));
    await tester.pumpAndSettle();

    expect(find.text('CLOSE'), findsOneWidget, reason: 'one dialog, not two to dismiss');
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
