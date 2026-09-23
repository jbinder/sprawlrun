import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/theme/cyber_theme.dart';
import 'package:sprawl_run/widgets/route_trace.dart';

void main() {
  const trace = [
    TracePoint(lat: 48.20849, lon: 16.37208, elapsedSeconds: 0),
    TracePoint(lat: 48.20901, lon: 16.37311, elapsedSeconds: 30),
    TracePoint(lat: 48.20977, lon: 16.37402, elapsedSeconds: 60),
  ];

  Future<void> pump(
    WidgetTester tester, {
    List<TracePoint> points = trace,
    bool animate = true,
    bool disableAnimations = false,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: buildCyberTheme(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: RouteTrace(trace: points, animate: animate)),
      ),
    ),
  );

  final replay = find.byTooltip('Replay route');
  IconButton replayButton(WidgetTester tester) =>
      tester.widget<IconButton>(find.ancestor(of: replay, matching: find.byType(IconButton)));

  group('the head follows the pace that was run', () {
    test('an even pace puts it halfway along at halfway through', () {
      const even = [
        TracePoint(lat: 0, lon: 0, elapsedSeconds: 0),
        TracePoint(lat: 0, lon: 1, elapsedSeconds: 10),
        TracePoint(lat: 0, lon: 2, elapsedSeconds: 20),
      ];
      expect(traceHeadAt(even, 0), (0, 0.0));
      // The end of one leg and the start of the next are the same point.
      expect(traceHeadAt(even, 0.5), (0, 1.0), reason: 'exactly on the middle fix');
      expect(traceHeadAt(even, 0.75), (1, 0.5));
    });

    test('a slow start then a sprint leaves it short of halfway at halftime', () {
      // Two minutes to cover the first leg, ten seconds for the second.
      const uneven = [
        TracePoint(lat: 0, lon: 0, elapsedSeconds: 0),
        TracePoint(lat: 0, lon: 1, elapsedSeconds: 120),
        TracePoint(lat: 0, lon: 2, elapsedSeconds: 130),
      ];
      final (index, fraction) = traceHeadAt(uneven, 0.5);
      expect(index, 0, reason: 'still on the slow first leg');
      expect(fraction, closeTo(65 / 120, 0.001));

      // And in the last few per cent it is already deep into the sprint.
      final (lateIndex, lateFraction) = traceHeadAt(uneven, 0.96);
      expect(lateIndex, 1);
      expect(lateFraction, closeTo(0.48, 0.01));
    });

    test('a paused stretch holds the head still rather than skipping it', () {
      const paused = [
        TracePoint(lat: 0, lon: 0, elapsedSeconds: 0),
        TracePoint(lat: 0, lon: 1, elapsedSeconds: 10),
        TracePoint(lat: 0, lon: 1, elapsedSeconds: 70), // a minute standing still
        TracePoint(lat: 0, lon: 2, elapsedSeconds: 80),
      ];
      final (index, _) = traceHeadAt(paused, 0.5);
      expect(index, 1, reason: 'halfway through the run is in the middle of the pause');
    });

    test('synthetic points sharing a timestamp fall back to even spacing', () {
      const flat = [
        TracePoint(lat: 0, lon: 0, elapsedSeconds: 0),
        TracePoint(lat: 0, lon: 1, elapsedSeconds: 0),
        TracePoint(lat: 0, lon: 2, elapsedSeconds: 0),
      ];
      expect(traceHeadAt(flat, 0.5), (1, 0.0));
    });

    test('the ends are clamped rather than running off the trace', () {
      const two = [
        TracePoint(lat: 0, lon: 0, elapsedSeconds: 0),
        TracePoint(lat: 0, lon: 1, elapsedSeconds: 10),
      ];
      expect(traceHeadAt(two, -1), (0, 0.0));
      expect(traceHeadAt(two, 2), (0, 1.0));
    });
  });

  testWidgets('the route draws itself, then offers a replay', (tester) async {
    await pump(tester);

    // Mid-draw there is nothing to replay yet — it is still happening.
    await tester.pump(RouteTrace.drawDuration ~/ 2);
    expect(replayButton(tester).onPressed, isNull);

    await tester.pumpAndSettle();
    expect(replayButton(tester).onPressed, isNotNull, reason: 'the draw has finished');

    // Replaying starts over, so the control goes dead again until it lands.
    await tester.tap(replay);
    await tester.pump();
    await tester.pump(RouteTrace.drawDuration ~/ 2);
    expect(replayButton(tester).onPressed, isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('a runner who turned animations off gets the finished route', (tester) async {
    await pump(tester, disableAnimations: true);
    await tester.pump();

    expect(
      replayButton(tester).onPressed,
      isNotNull,
      reason: 'complete on the first frame, with no animation to wait for',
    );
  });

  testWidgets('without animate the route is simply drawn, with no replay control', (tester) async {
    await pump(tester, animate: false);
    await tester.pump();

    expect(replay, findsNothing);
    expect(find.text('NO ROUTE DATA'), findsNothing);
  });

  testWidgets('a trace too short to draw says so instead of animating', (tester) async {
    await pump(tester, points: const [TracePoint(lat: 48.2, lon: 16.3, elapsedSeconds: 0)]);
    await tester.pump();

    expect(find.text('NO ROUTE DATA'), findsOneWidget);
    expect(replay, findsNothing);
  });
}
