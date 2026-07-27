import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/mission_repository.dart';
import 'data/profile_repository.dart';
import 'data/run_repository.dart';
import 'services/location_service.dart';
import 'services/narrator.dart';
import 'services/run_engine.dart';
import 'state/app_state.dart';
import 'theme/cyber_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(cyberOverlayStyle);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  final documents = await getApplicationDocumentsDirectory();
  final root = Directory('${documents.path}/sprawlrun');
  await root.create(recursive: true);

  final narrator = AudioNarrator();
  final appState = AppState(
    profiles: ProfileRepository(root),
    runs: RunRepository(Directory('${root.path}/runs')),
    // Side-loaded mission packs land here; see docs/MISSION_PACKS.md.
    missions: MissionRepository(externalDir: Directory('${root.path}/mission_packs')),
    narrator: narrator,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider(
          create: (_) => RunEngine(narrator: narrator, location: GpsLocationSource()),
        ),
      ],
      child: const SprawlRunApp(),
    ),
  );

  // Loading after the first frame means the runner sees the app's own shell
  // booting rather than a white rectangle.
  await appState.load();
}
