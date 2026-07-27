import 'dart:math';

enum GoalType { time, distance }

/// What the runner must reach for a mission to count as a success.
///
/// Stored as seconds for [GoalType.time] and metres for [GoalType.distance] so
/// there is exactly one unit per type anywhere in the app.
class RunGoal {
  const RunGoal(this.type, this.value);

  final GoalType type;
  final double value;

  static const RunGoal defaultGoal = RunGoal(GoalType.time, 1500); // 25 minutes

  factory RunGoal.seconds(double s) => RunGoal(GoalType.time, s);
  factory RunGoal.metres(double m) => RunGoal(GoalType.distance, m);

  bool get isTime => type == GoalType.time;
  bool get isDistance => type == GoalType.distance;

  Duration get asDuration => Duration(seconds: value.round());

  /// 0..1 completion for the given run state. Beat scheduling and the HUD ring
  /// both key off this, so a mission's pacing adapts to whatever goal the
  /// runner picked.
  double progress({required double elapsedSeconds, required double distanceMeters}) {
    if (value <= 0) return 0;
    final raw = isTime ? elapsedSeconds / value : distanceMeters / value;
    return raw.clamp(0.0, 1.0);
  }

  bool isMet({required double elapsedSeconds, required double distanceMeters}) =>
      progress(elapsedSeconds: elapsedSeconds, distanceMeters: distanceMeters) >= 1.0;

  /// Remaining amount, in this goal's own unit.
  double remaining({required double elapsedSeconds, required double distanceMeters}) =>
      max(0.0, value - (isTime ? elapsedSeconds : distanceMeters));

  RunGoal copyWith({GoalType? type, double? value}) => RunGoal(type ?? this.type, value ?? this.value);

  Map<String, dynamic> toJson() => {'type': type.name, 'value': value};

  factory RunGoal.fromJson(Map<String, dynamic> json) => RunGoal(
    GoalType.values.firstWhere((t) => t.name == json['type'], orElse: () => GoalType.time),
    (json['value'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) => other is RunGoal && other.type == type && other.value == value;

  @override
  int get hashCode => Object.hash(type, value);

  @override
  String toString() => isTime ? '${(value / 60).round()} min' : '${(value / 1000).toStringAsFixed(1)} km';
}
