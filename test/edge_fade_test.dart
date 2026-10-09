import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/widgets/edge_fade.dart';

/// A long list used to stop dead at the edge of the screen, with nothing to say
/// there was more — the filter rails fade sideways, the lists did not.
void main() {
  Future<void> pumpList(WidgetTester tester, int rows) => tester.pumpWidget(
    MaterialApp(
      scrollBehavior: const CyberScrollBehavior(),
      home: Scaffold(
        body: ListView(children: [for (var i = 0; i < rows; i++) SizedBox(height: 60, child: Text('row $i'))]),
      ),
    ),
  );

  EdgeFadeState fade(WidgetTester tester) => tester.state<EdgeFadeState>(find.byType(EdgeFade));

  testWidgets('a long list fades only the edge that still hides rows', (tester) async {
    await pumpList(tester, 60);
    await tester.pump();
    expect(fade(tester).moreAbove, isFalse, reason: 'nothing above the first row');
    expect(fade(tester).moreBelow, isTrue);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(fade(tester).moreAbove, isTrue);
    expect(fade(tester).moreBelow, isTrue, reason: 'mid-list: both edges hide rows');

    await tester.fling(find.byType(ListView), const Offset(0, -20000), 5000);
    await tester.pumpAndSettle();
    expect(fade(tester).moreAbove, isTrue);
    expect(fade(tester).moreBelow, isFalse, reason: 'at the end, the bottom clears');
  });

  testWidgets('a list that fits is not faded at all', (tester) async {
    await pumpList(tester, 3);
    await tester.pump();
    expect(fade(tester).moreAbove, isFalse);
    expect(fade(tester).moreBelow, isFalse);
  });

  testWidgets('sideways scrolling is left to the filter rails', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const CyberScrollBehavior(),
        home: Scaffold(
          body: ListView(
            scrollDirection: Axis.horizontal,
            children: [for (var i = 0; i < 30; i++) SizedBox(width: 80, child: Text('chip $i'))],
          ),
        ),
      ),
    );
    expect(find.byType(EdgeFade), findsNothing);
  });
}
