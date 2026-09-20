import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/models/achievement.dart';
import 'package:sprawl_run/models/mission.dart';
import 'package:sprawl_run/theme/cyber_palette.dart';
import 'package:sprawl_run/theme/cyber_theme.dart';
import 'package:sprawl_run/widgets/unlock_reveal.dart';

const _codex = CodexEntry(id: 'c1', title: 'Black Clinics', category: 'STREET MED', body: 'Unlicensed surgery.');

AchievementDef _ach(AchTier tier) => AchievementDef(
  id: 'a-${tier.name}',
  title: 'Test ${tier.label}',
  description: 'A description.',
  category: AchCategory.distance,
  tier: tier,
  target: 1,
  metric: (_) => 1,
  format: (v) => '$v',
);

Future<void> _pump(
  WidgetTester tester, {
  required List<Unlock> unlocks,
  VoidCallback? onDone,
  ValueChanged<Unlock>? onShow,
  Duration autoAdvance = Duration.zero,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildCyberTheme(),
      home: Scaffold(
        body: UnlockReveal(unlocks: unlocks, onDone: onDone ?? () {}, onShow: onShow, autoAdvance: autoAdvance),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600)); // boot-in
}

void main() {
  testWidgets('shows one card at a time with a counter, and tapping advances', (tester) async {
    var done = 0;
    await _pump(
      tester,
      unlocks: [Unlock.codex(_codex), Unlock.achievement(_ach(AchTier.legend))],
      onDone: () => done++,
    );

    expect(find.text('CODEX ENTRY RECOVERED'), findsOneWidget);
    expect(find.text('BLACK CLINICS'), findsOneWidget);
    expect(find.text('01 / 02'), findsOneWidget);
    expect(find.text('ACHIEVEMENT UNLOCKED'), findsNothing);
    expect(find.text('TAP TO CONTINUE'), findsOneWidget);

    await tester.tap(find.text('TAP TO CONTINUE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('ACHIEVEMENT UNLOCKED'), findsOneWidget);
    // Finders see widgets at opacity zero; the runner does not. The boot-in
    // has to restart for every card, not just the first.
    expect(
      tester.widget<Opacity>(find.byType(Opacity).first).opacity,
      greaterThan(0.95),
      reason: 'the second card faded in',
    );
    expect(find.text('TEST LEGEND'), findsOneWidget);
    expect(find.text('LEGEND'), findsOneWidget, reason: 'tier tag');
    expect(find.text('02 / 02'), findsOneWidget);
    expect(find.text('CONTINUE'), findsOneWidget, reason: 'the last card ends the sequence with a button');
    expect(done, 0);

    await tester.tap(find.text('CONTINUE'));
    await tester.pump();
    expect(done, 1);
  });

  testWidgets('every card announces itself once, in order', (tester) async {
    final shown = <String>[];
    await _pump(
      tester,
      unlocks: [Unlock.mission('NINSEI'), Unlock.codex(_codex), Unlock.achievement(_ach(AchTier.chrome))],
      onShow: (u) => shown.add(u.kicker),
    );
    await tester.tap(find.byType(UnlockReveal));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byType(UnlockReveal));
    await tester.pump(const Duration(milliseconds: 600));

    expect(shown, ['NEW OPERATION', 'CODEX ENTRY RECOVERED', 'ACHIEVEMENT UNLOCKED']);
  });

  testWidgets('cards advance by themselves when left alone', (tester) async {
    var done = 0;
    await _pump(
      tester,
      unlocks: [Unlock.codex(_codex), Unlock.mission('NINSEI')],
      onDone: () => done++,
      autoAdvance: const Duration(seconds: 3),
    );
    expect(find.text('01 / 02'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('02 / 02'), findsOneWidget);
    expect(done, 0);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(done, 1);
  });

  test('the hold scales with how much there is to read', () {
    Duration holdForBody(int chars) => UnlockReveal.holdFor(
      Unlock(kicker: '', title: '', body: 'x' * chars, accent: Cy.cyan, icon: Icons.memory, stamp: ''),
    );
    expect(
      UnlockReveal.holdFor(Unlock.mission('NINSEI')),
      const Duration(seconds: 12),
      reason: 'one line still gets a readable minimum',
    );
    // A typical codex entry is around 240 characters; the longest shipped is ~410.
    expect(holdForBody(240), const Duration(milliseconds: 22400));
    expect(holdForBody(410), const Duration(milliseconds: 32600));
    expect(holdForBody(1000), const Duration(seconds: 40), reason: 'capped so a card can never feel stuck');
  });

  test('a STREET achievement is never revealed in grey', () {
    expect(Unlock.achievement(_ach(AchTier.street)).accent, isNot(Cy.inkDim));
    expect(Unlock.achievement(_ach(AchTier.legend)).accent, AchTier.legend.color);
  });
}
