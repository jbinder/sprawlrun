import 'goal.dart';

enum RunOutcome {
  /// Goal met and the runner closed the mission out.
  success,

  /// Ended before the goal was met.
  failed,

  /// Ended with too little data to be worth scoring (< 60 s or < 100 m).
  discarded,
}

/// One GPS fix, trimmed to what the summary trace and stats actually need.
class TracePoint {
  const TracePoint({
    required this.lat,
    required this.lon,
    required this.elapsedSeconds,
    this.speedMps = 0,
  });

  final double lat;
  final double lon;
  final double elapsedSeconds;
  final double speedMps;

  factory TracePoint.fromJson(List<dynamic> json) => TracePoint(
    lat: (json[0] as num).toDouble(),
    lon: (json[1] as num).toDouble(),
    elapsedSeconds: (json[2] as num).toDouble(),
    speedMps: json.length > 3 ? (json[3] as num).toDouble() : 0,
  );

  /// Stored as a positional array — a 60-minute run is thousands of points and
  /// key names would triple the file size for nothing.
  List<double> toJson() => [
    double.parse(lat.toStringAsFixed(5)),
    double.parse(lon.toStringAsFixed(5)),
    elapsedSeconds.roundToDouble(),
    double.parse(speedMps.toStringAsFixed(2)),
  ];
}

/// The permanent record of one completed (or abandoned) run.
class RunRecord {
  const RunRecord({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.elapsedSeconds,
    required this.movingSeconds,
    required this.distanceMeters,
    required this.calories,
    required this.goal,
    required this.outcome,
    this.missionId,
    this.missionCodename,
    this.missionOrder,
    this.chasesTotal = 0,
    this.chasesEvaded = 0,
    this.beatsHeard = 0,
    this.trace = const [],
  });

  final String id;
  final DateTime startedAt;
  final DateTime endedAt;

  /// Wall-clock seconds between start and finish, minus paused time.
  final double elapsedSeconds;

  /// Seconds where the runner was actually moving. Used for honest pace.
  final double movingSeconds;

  final double distanceMeters;
  final double calories;
  final RunGoal goal;
  final RunOutcome outcome;

  /// Null for a free run with no story attached.
  final String? missionId;
  final String? missionCodename;
  final int? missionOrder;

  final int chasesTotal;
  final int chasesEvaded;
  final int beatsHeard;
  final List<TracePoint> trace;

  bool get isMission => missionId != null;
  bool get isSuccess => outcome == RunOutcome.success;
  bool get countsForStats => outcome != RunOutcome.discarded;

  double get km => distanceMeters / 1000.0;

  /// Seconds per kilometre, based on moving time. Zero-distance runs report 0
  /// rather than infinity so the UI never has to special-case them.
  double get paceSecondsPerKm => distanceMeters < 10 ? 0 : movingSeconds / (distanceMeters / 1000.0);

  double get avgSpeedMps => elapsedSeconds <= 0 ? 0 : distanceMeters / elapsedSeconds;

  RunRecord copyWith({RunOutcome? outcome}) => RunRecord(
    id: id,
    startedAt: startedAt,
    endedAt: endedAt,
    elapsedSeconds: elapsedSeconds,
    movingSeconds: movingSeconds,
    distanceMeters: distanceMeters,
    calories: calories,
    goal: goal,
    outcome: outcome ?? this.outcome,
    missionId: missionId,
    missionCodename: missionCodename,
    missionOrder: missionOrder,
    chasesTotal: chasesTotal,
    chasesEvaded: chasesEvaded,
    beatsHeard: beatsHeard,
    trace: trace,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    'elapsedSeconds': elapsedSeconds,
    'movingSeconds': movingSeconds,
    'distanceMeters': distanceMeters,
    'calories': calories,
    'goal': goal.toJson(),
    'outcome': outcome.name,
    if (missionId != null) 'missionId': missionId,
    if (missionCodename != null) 'missionCodename': missionCodename,
    if (missionOrder != null) 'missionOrder': missionOrder,
    'chasesTotal': chasesTotal,
    'chasesEvaded': chasesEvaded,
    'beatsHeard': beatsHeard,
    'trace': trace.map((p) => p.toJson()).toList(),
  };

  factory RunRecord.fromJson(Map<String, dynamic> json) => RunRecord(
    id: json['id'] as String,
    startedAt: DateTime.parse(json['startedAt'] as String),
    endedAt: DateTime.parse(json['endedAt'] as String),
    elapsedSeconds: (json['elapsedSeconds'] as num).toDouble(),
    movingSeconds: (json['movingSeconds'] as num?)?.toDouble() ?? (json['elapsedSeconds'] as num).toDouble(),
    distanceMeters: (json['distanceMeters'] as num).toDouble(),
    calories: (json['calories'] as num?)?.toDouble() ?? 0,
    goal: RunGoal.fromJson(Map<String, dynamic>.from(json['goal'] as Map)),
    outcome: RunOutcome.values.firstWhere((o) => o.name == json['outcome'], orElse: () => RunOutcome.failed),
    missionId: json['missionId'] as String?,
    missionCodename: json['missionCodename'] as String?,
    missionOrder: (json['missionOrder'] as num?)?.toInt(),
    chasesTotal: (json['chasesTotal'] as num?)?.toInt() ?? 0,
    chasesEvaded: (json['chasesEvaded'] as num?)?.toInt() ?? 0,
    beatsHeard: (json['beatsHeard'] as num?)?.toInt() ?? 0,
    trace: (json['trace'] as List? ?? []).map((e) => TracePoint.fromJson(e as List)).toList(),
  );
}
