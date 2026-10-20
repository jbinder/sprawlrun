import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/widgets/panels.dart';

/// The home screen cut the pack's title short with half the row still empty:
/// the title shared the free room equally with the rule beside it.
void main() {
  Future<RenderParagraph> pumpHeader(WidgetTester tester, String title) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SectionHeader(title, trailing: const SizedBox(width: 100, height: 10)),
        ),
      ),
    );
    return tester.renderObject<RenderParagraph>(find.text(title.toUpperCase()));
  }

  testWidgets('a title that fits is shown whole, however little rule is left', (tester) async {
    final title = await pumpHeader(tester, 'Null Tide');
    expect(title.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a title too long for the row is ellipsized, not overflowed', (tester) async {
    final title = await pumpHeader(tester, 'A pack title far too long for any phone to show in one line');
    expect(title.didExceedMaxLines, isTrue);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(SectionHeader)).width, 360);
  });
}
