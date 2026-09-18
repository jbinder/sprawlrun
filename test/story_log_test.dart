import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/mission.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/theme/cyber_theme.dart';
import 'package:sprawl_run/widgets/story_log.dart';

final _mission = Mission(
  id: 'm',
  packId: 'p',
  order: 1,
  codename: 'OP',
  title: 'Op',
  location: 'Here',
  brief: '',
  objective: '',
  debrief: '',
  suggestedGoal: const RunGoal(GoalType.time, 600),
  beats: const [
    StoryBeat(
      id: 'b0',
      trigger: BeatTrigger(fraction: 0),
      headline: 'Incoming',
      lines: [
        StoryLine(speaker: 'KESTREL', text: 'Package is live.'),
        StoryLine(speaker: 'SIX', text: 'Please do not stop.'),
      ],
    ),
  ],
  codex: const [CodexEntry(id: 'cdx', title: 'The Turing Registry', category: 'LAW', body: '')],
);

const _story = [
  StoryEvent(atSeconds: 5, kind: StoryEventKind.beat, ref: 'b0'),
  StoryEvent(atSeconds: 6, kind: StoryEventKind.codex, ref: 'cdx'),
  StoryEvent(atSeconds: 300, kind: StoryEventKind.chaseStarted, ref: 'DRONE'),
  StoryEvent(atSeconds: 360, kind: StoryEventKind.chaseEnded, ref: 'DRONE', escaped: false),
  StoryEvent(atSeconds: 600, kind: StoryEventKind.goal),
];

Future<void> _pump(WidgetTester tester, {Mission? mission}) => tester.pumpWidget(
  MaterialApp(
    theme: buildCyberTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: StoryLog(
          story: _story,
          mission: mission,
          codexTitle: (id) => id == 'cdx' ? 'The Turing Registry' : null,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('reads the run back: lines from the pack, pursuits with their outcome', (tester) async {
    await _pump(tester, mission: _mission);

    expect(find.text('INCOMING'), findsOneWidget, reason: 'the beat headline');
    expect(find.text('Package is live.'), findsOneWidget);
    expect(find.text('Please do not stop.'), findsOneWidget);
    expect(find.text('KESTREL'), findsOneWidget);
    expect(find.text('INTEL INTERCEPTED — The Turing Registry'), findsOneWidget);
    expect(find.text('PURSUIT — DRONE'), findsOneWidget);
    expect(find.text('CAUGHT — DRONE'), findsOneWidget);
    expect(find.text('TARGET REACHED'), findsOneWidget);
    expect(find.text('00:05'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
  });

  testWidgets('a run whose pack is gone still shows what happened, without the words', (tester) async {
    await _pump(tester, mission: null);

    expect(find.text('TRANSMISSION'), findsOneWidget);
    expect(find.textContaining('no longer installed'), findsOneWidget);
    expect(find.text('Package is live.'), findsNothing);
    expect(find.text('CAUGHT — DRONE'), findsOneWidget, reason: 'pursuits need no pack');
  });
}
