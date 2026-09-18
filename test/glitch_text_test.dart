import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/theme/cyber_theme.dart';
import 'package:sprawl_run/widgets/glitch_text.dart';

/// The glitch is two offset copies of the text. They have to wrap exactly as
/// the text beneath them does, or a two-line title gets a one-line ghost
/// sliding across it.
void main() {
  testWidgets('the colour layers wrap on the same lines as the title', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCyberTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              child: GlitchText('SPRAWL PRIME', style: CyType.display(size: 28)),
            ),
          ),
        ),
      ),
    );
    // Wait for a glitch to be scheduled and land mid-animation, when the
    // layers are on screen.
    for (var i = 0; i < 40 && find.byType(Text).evaluate().length < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    final texts = find.byType(Text).evaluate().toList();
    expect(texts.length, 3, reason: 'base text plus two glitch layers while animating');

    final heights = texts.map((e) => e.renderObject!.paintBounds.height).toSet();
    expect(heights, hasLength(1), reason: 'all three layers wrapped to the same number of lines');
    expect(heights.single, greaterThan(40), reason: 'the title did wrap to two lines at this width');
  });
}
