import 'run_record.dart';

/// What one run measured about the runner's stride: steps and GPS distance
/// over the same seconds, split by gait, since a walking step and a running
/// step are very different lengths. Only seconds with live GPS and steps
/// both count, so it is a measurement, never an estimate fed back in.
class StrideSample {
  const StrideSample({this.walkSteps = 0, this.walkMeters = 0, this.runSteps = 0, this.runMeters = 0});

  final int walkSteps;
  final double walkMeters;
  final int runSteps;
  final double runMeters;

  bool get isEmpty => walkSteps == 0 && runSteps == 0;

  StrideSample add({required bool running, required int steps, required double meters}) => running
      ? StrideSample(walkSteps: walkSteps, walkMeters: walkMeters, runSteps: runSteps + steps, runMeters: runMeters + meters)
      : StrideSample(walkSteps: walkSteps + steps, walkMeters: walkMeters + meters, runSteps: runSteps, runMeters: runMeters);

  Map<String, dynamic> toJson() => {
    'ws': walkSteps,
    'wm': double.parse(walkMeters.toStringAsFixed(1)),
    'rs': runSteps,
    'rm': double.parse(runMeters.toStringAsFixed(1)),
  };

  factory StrideSample.fromJson(Map<String, dynamic> json) => StrideSample(
    walkSteps: (json['ws'] as num?)?.toInt() ?? 0,
    walkMeters: (json['wm'] as num?)?.toDouble() ?? 0,
    runSteps: (json['rs'] as num?)?.toInt() ?? 0,
    runMeters: (json['rm'] as num?)?.toDouble() ?? 0,
  );
}

/// How far one step carries the runner, walking and running — what turns
/// steps into distance when the GPS has none to give.
///
/// Derived, never stored: learned from the [StrideSample]s of recent runs,
/// and where those are too few, scaled from the runner's height. A gait that
/// has been measured also corrects the other one, since someone with a long
/// running stride has a long walking one too.
class Stride {
  const Stride({required this.walk, required this.run});

  /// Metres per step.
  final double walk;
  final double run;

  /// Steps per minute from which a step is a running step.
  static const double runningCadence = 140;

  /// Step length as a share of height. Common rules of thumb; the runner's
  /// own runs replace them as soon as there are enough.
  static const double walkPerHeight = 0.415;
  static const double runPerHeight = 0.65;

  /// The height assumed when the runner has given none.
  static const double defaultHeightCm = 170;

  /// Steps a gait needs, over recent runs, before it is trusted over height.
  static const int learnedAfterSteps = 1000;

  /// How many recent runs are learned from, so a stride that changes with
  /// training is followed rather than averaged over years.
  static const int recentRuns = 30;

  double at(double cadence) => cadence >= runningCadence ? run : walk;

  /// The stride for [runs] (newest first, as the run log is kept) and a
  /// height in cm, 0 when unknown.
  factory Stride.of(List<RunRecord> runs, {double heightCm = 0}) {
    final h = (heightCm > 0 ? heightCm : defaultHeightCm) / 100;
    var walkSteps = 0, runSteps = 0;
    var walkMeters = 0.0, runMeters = 0.0;
    var used = 0;
    for (final r in runs) {
      final s = r.strides;
      if (s == null || s.isEmpty) continue;
      // A gait whose average is not a human step is a bad measurement — a
      // phone in a bag on a bike, fixes jumping indoors — and is left out.
      if (_plausible(s.walkSteps, s.walkMeters, 0.25, 1.2)) {
        walkSteps += s.walkSteps;
        walkMeters += s.walkMeters;
      }
      if (_plausible(s.runSteps, s.runMeters, 0.4, 2.4)) {
        runSteps += s.runSteps;
        runMeters += s.runMeters;
      }
      if (++used >= recentRuns) break;
    }

    final learnedWalk = walkSteps >= learnedAfterSteps ? walkMeters / walkSteps : null;
    final learnedRun = runSteps >= learnedAfterSteps ? runMeters / runSteps : null;
    return Stride(
      walk: learnedWalk ?? (learnedRun != null ? learnedRun * walkPerHeight / runPerHeight : h * walkPerHeight),
      run: learnedRun ?? (learnedWalk != null ? learnedWalk * runPerHeight / walkPerHeight : h * runPerHeight),
    );
  }

  static bool _plausible(int steps, double meters, double min, double max) {
    if (steps <= 0) return false;
    final perStep = meters / steps;
    return perStep >= min && perStep <= max;
  }
}
