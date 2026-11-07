import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/widgets/scrolling_text.dart';

void main() {
  Future<void> show(WidgetTester tester, String text, double width) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: ScrollingText(text, style: const TextStyle(fontSize: 12))),
        ),
      ),
    ),
  );

  double offset(WidgetTester tester) {
    final found = find.byType(Transform);
    if (found.evaluate().isEmpty) return 0;
    return tester.widget<Transform>(found.first).transform.getTranslation().x;
  }

  testWidgets('a title that fits sits still', (tester) async {
    await show(tester, 'Short', 300);
    expect(find.byType(ClipRect), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(offset(tester), 0);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a long one rests, drifts along, rests, and comes back', (tester) async {
    await show(tester, 'A very long file name that cannot possibly fit on this line', 100);
    await tester.pump();
    expect(offset(tester), 0);

    await tester.pump(const Duration(seconds: 2));
    expect(offset(tester), 0, reason: 'resting at the start, long enough to read');

    await tester.pump(const Duration(seconds: 3));
    final moved = offset(tester);
    expect(moved, lessThan(0));
    expect(moved.abs(), lessThan(ScrollingText.pixelsPerSecond * 2.5), reason: 'slowly');

    // Whatever the length, it gets back to where it began.
    final state = tester.state(find.byType(ScrollingText));
    expect(state.mounted, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('it copes with a new title in the same place', (tester) async {
    await show(tester, 'A very long file name that cannot possibly fit on this line', 100);
    await tester.pump(const Duration(seconds: 6));
    await show(tester, 'Short', 300);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Short'), findsOneWidget);
    expect(find.byType(ClipRect), findsNothing);
  });
}
