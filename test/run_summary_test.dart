import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/run_outcome.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/screens/run_summary_screen.dart';
import 'package:sprawl_run/state/app_state.dart';
import 'package:sprawl_run/theme/cyber_theme.dart';

import 'support/fakes.dart';

void main() {
  const trace = [
    TracePoint(lat: 48.20849, lon: 16.37208, elapsedSeconds: 0),
    TracePoint(lat: 48.20901, lon: 16.37311, elapsedSeconds: 30),
  ];

  Future<void> pump(WidgetTester tester, RunRecord record) async {
    final root = tempRoot('summary');
    addTearDown(() => root.deleteSync(recursive: true));
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final state = await tester.runAsync(() async {
      final s = AppState(
        profiles: ProfileRepository(root),
        runs: RunRepository(Directory('${root.path}/runs')),
        missions: MissionRepository(externalDir: Directory('${root.path}/packs')),
        narrator: FakeNarrator(),
      );
      await s.load();
      return s;
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state!,
        child: MaterialApp(
          theme: buildCyberTheme(),
          home: RunSummaryScreen(report: RunOutcomeReport(record: record), mission: null),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a tracked run reports how long it spent moving', (tester) async {
    final record = run(at: DateTime(2026, 9, 25, 7), meters: 5000, seconds: 1800).copyWith(trace: trace);
    await pump(tester, record);

    expect(find.textContaining('MOVING'), findsOneWidget);
    expect(find.text('TIME ONLY'), findsNothing);
  });

  testWidgets('a run that covered no distance says so instead of claiming no movement', (tester) async {
    // Moving time is only counted from GPS speed, so a run through a GPS
    // failure has none to report — even though the runner really ran.
    final record = run(at: DateTime(2026, 9, 19, 6), meters: 0, seconds: 7338);
    await pump(tester, record);

    expect(find.text('TIME ONLY'), findsOneWidget);
    expect(find.textContaining('MOVING'), findsNothing);
  });
}
