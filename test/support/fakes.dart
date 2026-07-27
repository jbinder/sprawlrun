import 'dart:async';
import 'dart:io';

import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/mission.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/services/geo.dart';
import 'package:sprawl_run/services/location_service.dart';
import 'package:sprawl_run/services/narrator.dart';

/// A location source the test drives by hand, one step at a time.
class FakeLocation implements LocationSource {
  FakeLocation({this.readiness = LocationReadiness.ready, this.accuracy = 5});

  LocationReadiness readiness;
  double accuracy;

  final _controller = StreamController<GeoFix>.broadcast();

  double lat = 52.5200;
  double lon = 13.4050;
  bool stopped = false;

  @override
  Future<LocationReadiness> prepare() async => readiness;

  @override
  Stream<GeoFix> fixes() => _controller.stream;

  @override
  Future<void> stop() async => stopped = true;

  /// Moves due north by [meters] and emits a fix stamped [now].
  ///
  /// A real GPS keeps reporting while the runner stands still, so this emits
  /// even when [meters] is zero.
  void step(DateTime now, double meters) {
    // 1 degree of latitude is ~111.32 km everywhere, which keeps the test's
    // expected distances trivial to reason about.
    lat += meters / 111320.0;
    _controller.add(GeoFix(lat: lat, lon: lon, timestamp: now, accuracy: accuracy, speed: meters));
  }

  /// Emits a fix jittering [meters] alternately north and south of the current
  /// position — GPS noise while genuinely stationary.
  void jitter(DateTime now, double meters) {
    _jitterSign = -_jitterSign;
    _controller.add(
      GeoFix(
        lat: lat + _jitterSign * meters / 111320.0,
        lon: lon,
        timestamp: now,
        accuracy: accuracy,
      ),
    );
  }

  int _jitterSign = 1;

  void emitRaw(GeoFix fix) => _controller.add(fix);
}

/// Records what would have been spoken, and takes [lineDuration] per line so
/// beat-gap logic is exercised the way it is in the real app.
class FakeNarrator implements Narrator {
  FakeNarrator({this.lineDuration = const Duration(seconds: 2)});

  final Duration lineDuration;

  final List<List<StoryLine>> beats = [];
  final List<String> sfxPlayed = [];
  final _events = StreamController<NarrationEvent>.broadcast();

  bool ambientBed = false;
  bool stopped = false;

  List<String> get spokenText => [
    for (final beat in beats)
      for (final line in beat) line.text,
  ];

  @override
  Stream<NarrationEvent> get events => _events.stream;

  @override
  Future<void> init(Profile profile) async {}

  @override
  Future<void> applyProfile(Profile profile) async {}

  @override
  Future<void> speakBeat(List<StoryLine> lines) async {
    beats.add(lines);
    for (final line in lines) {
      _events.add(NarrationEvent(line));
      await Future<void>.delayed(lineDuration);
    }
    _events.add(const NarrationEvent(null));
  }

  @override
  Future<void> sfx(String name) async => sfxPlayed.add(name);

  @override
  Future<void> setAmbientBed(bool on) async => ambientBed = on;

  @override
  Future<void> stopAll() async => stopped = true;

  @override
  Future<void> dispose() async => _events.close();
}

/// A throwaway directory that cleans itself up.
Directory tempRoot(String label) =>
    Directory.systemTemp.createTempSync('sprawlrun_$label');

/// Builds a run record with sensible defaults so tests only state what matters.
RunRecord run({
  required DateTime at,
  double meters = 5000,
  double seconds = 1800,
  RunOutcome outcome = RunOutcome.success,
  String? missionId,
  int chasesTotal = 0,
  int chasesEvaded = 0,
  double calories = 300,
  int beatsHeard = 0,
}) => RunRecord(
  id: at.microsecondsSinceEpoch.toString(),
  startedAt: at,
  endedAt: at.add(Duration(seconds: seconds.round())),
  elapsedSeconds: seconds,
  movingSeconds: seconds,
  distanceMeters: meters,
  calories: calories,
  goal: const RunGoal(GoalType.time, 1800),
  outcome: outcome,
  missionId: missionId,
  missionCodename: missionId?.toUpperCase(),
  chasesTotal: chasesTotal,
  chasesEvaded: chasesEvaded,
  beatsHeard: beatsHeard,
);
