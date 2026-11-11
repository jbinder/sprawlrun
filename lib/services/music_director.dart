import '../audio/song.dart';
import '../models/run_record.dart';

/// A change of music level for the player to make.
class MusicCue {
  const MusicCue(this.level, {this.atOnce = false});

  final MusicLevel level;

  /// From the next bar, rather than waiting for the next phrase.
  final bool atOnce;
}

/// Decides how much of the song a run calls for. Pure, and told everything it
/// knows, so a whole run can be played through it in a test.
///
/// Pace is judged against the runner's own usual pace, so an easy day for a fast
/// runner is not scored as a sprint. Low is set well below it: slowing down on a
/// climb must not take the music away just when it is wanted.
class MusicDirector {
  MusicDirector({required this.usualSpeed});

  /// Metres per second, or null when there is no history to compare with. Pace
  /// then changes nothing, and a chase or a goal still does.
  final double? usualSpeed;

  static const double lowBelow = 0.75, lowUntil = 0.80;
  static const double highAbove = 1.10, highUntil = 1.05;

  /// Seconds of movement the judgement looks back over, and needs before making
  /// one. It takes their median, so a burst or a GPS jump shorter than half of it
  /// changes nothing, while a real change of pace is answered once it has lasted
  /// that long. An average over 25 seconds answered twenty and more seconds late,
  /// which a runner noticed on an interval run.
  static const int windowSeconds = 12, minimumSeconds = 10;

  /// Slower than this is standing still, as `RunEngine` counts it.
  static const double stillBelowMps = 0.65;

  /// A traffic light is no reason to strip the song. This long is a real stop.
  static const int stillForLowSeconds = 60;

  /// About sixteen bars at a running tempo.
  static const int goalLiftSeconds = 23;

  final List<double> _speeds = [];
  MusicLevel _paced = MusicLevel.normal;
  MusicLevel _current = MusicLevel.normal;
  int _stillSeconds = 0;
  int _liftLeft = 0;
  bool _chasing = false;

  /// One second of the run, at [speed], whether that came from the GPS or from
  /// steps. Null when neither has anything to say: not knowing is not standing
  /// still, so the level holds. Called while running and while auto-paused, and
  /// not during a manual pause, when the music is held anyway.
  MusicCue? tick(double? speed) {
    if (_liftLeft > 0) _liftLeft--;
    if (speed == null) return _next(atOnce: false);
    if (speed < stillBelowMps) {
      _stillSeconds++;
      if (_stillSeconds >= stillForLowSeconds && usualSpeed != null) {
        _paced = MusicLevel.low;
        // Whatever comes next is judged afresh, not by the pace before the stop.
        _speeds.clear();
      }
    } else {
      _stillSeconds = 0;
      _speeds.add(speed);
      if (_speeds.length > windowSeconds) _speeds.removeAt(0);
      _judgePace();
    }
    return _next(atOnce: false);
  }

  MusicCue? setChasing(bool chasing) {
    final rising = chasing && !_chasing;
    _chasing = chasing;
    return _next(atOnce: rising);
  }

  /// One lift for reaching the goal, then the song carries on with the runner.
  MusicCue? goalReached() {
    _liftLeft = goalLiftSeconds;
    return _next(atOnce: true);
  }

  void _judgePace() {
    final usual = usualSpeed;
    if (usual == null || usual <= 0 || _speeds.length < minimumSeconds) return;
    final sorted = [..._speeds]..sort();
    final share = sorted[sorted.length ~/ 2] / usual;
    _paced = switch (_paced) {
      MusicLevel.low => share > highAbove ? MusicLevel.high : (share >= lowUntil ? MusicLevel.normal : MusicLevel.low),
      MusicLevel.normal => share < lowBelow ? MusicLevel.low : (share > highAbove ? MusicLevel.high : MusicLevel.normal),
      MusicLevel.high => share < lowBelow ? MusicLevel.low : (share <= highUntil ? MusicLevel.normal : MusicLevel.high),
    };
  }

  MusicCue? _next({required bool atOnce}) {
    final level = _chasing || _liftLeft > 0 ? MusicLevel.high : _paced;
    if (level == _current) return null;
    _current = level;
    return MusicCue(level, atOnce: atOnce);
  }

  /// The runner's usual speed for [activity]: the median of their recent runs of
  /// it, so one walk home in a run's clothing moves it very little. Null with
  /// fewer than [minimumRuns] to go by. Derived from the log, never stored.
  static double? usualSpeedOf(List<RunRecord> log, Activity activity) {
    final recent = [
      for (final run in log)
        if (run.activity == activity &&
            run.distanceMeters >= 500 &&
            run.movingSeconds >= 120 &&
            !run.distanceEstimated)
          run,
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (recent.length < minimumRuns) return null;
    final speeds = [for (final run in recent.take(10)) run.distanceMeters / run.movingSeconds]..sort();
    return speeds[speeds.length ~/ 2];
  }

  static const int minimumRuns = 3;
}
