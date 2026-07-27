enum UnitSystem { metric, imperial }

enum StreakMetric { minutes, kilometres, missions }

/// How the app treats whatever the runner is already listening to when a story
/// beat fires.
enum AudioInterrupt {
  /// Take full focus: Spotify and friends pause, then resume. Most dramatic.
  pause,

  /// Take transient focus: the other app drops to a low volume underneath.
  duck,
}

/// The weekly commitment that keeps a streak alive.
class StreakGoal {
  const StreakGoal({this.metric = StreakMetric.minutes, this.target = 30});

  final StreakMetric metric;
  final double target;

  String get label => switch (metric) {
    StreakMetric.minutes => '${target.round()} min / week',
    StreakMetric.kilometres => '${target.toStringAsFixed(1)} km / week',
    StreakMetric.missions => '${target.round()} mission${target == 1 ? '' : 's'} / week',
  };

  String get unitLabel => switch (metric) {
    StreakMetric.minutes => 'MIN',
    StreakMetric.kilometres => 'KM',
    StreakMetric.missions => 'OPS',
  };

  StreakGoal copyWith({StreakMetric? metric, double? target}) =>
      StreakGoal(metric: metric ?? this.metric, target: target ?? this.target);

  Map<String, dynamic> toJson() => {'metric': metric.name, 'target': target};

  factory StreakGoal.fromJson(Map<String, dynamic> json) => StreakGoal(
    metric: StreakMetric.values.firstWhere((m) => m.name == json['metric'], orElse: () => StreakMetric.minutes),
    target: (json['target'] as num?)?.toDouble() ?? 30,
  );
}

/// Everything about the runner: identity, settings, and campaign progress.
///
/// Immutable — mutations go through [copyWith] and are persisted as a whole,
/// which keeps the on-disk state consistent even if the app dies mid-run.
class Profile {
  const Profile({
    this.callsign = 'RUNNER',
    this.weightKg = 72,
    this.units = UnitSystem.metric,
    this.streakGoal = const StreakGoal(),
    this.audioInterrupt = AudioInterrupt.pause,
    this.voiceEnabled = true,
    this.speechRate = 0.52,
    this.sfxVolume = 0.9,
    this.ambientBed = false,
    this.chasesEnabled = true,
    this.autoPause = true,
    this.keepScreenOn = true,
    this.completedMissions = const <String>{},
    this.unlockedAchievements = const <String, DateTime>{},
    this.unlockedCodex = const <String>{},
    this.missionAttempts = const <String, int>{},
    this.lastGoalByMission = const <String, Map<String, dynamic>>{},
  });

  final String callsign;
  final double weightKg;
  final UnitSystem units;
  final StreakGoal streakGoal;

  final AudioInterrupt audioInterrupt;
  final bool voiceEnabled;

  /// flutter_tts rate, 0..1. 0.5 is roughly natural on Android.
  final double speechRate;
  final double sfxVolume;

  /// Low ambient drone under the HUD for runners with no music of their own.
  final bool ambientBed;

  final bool chasesEnabled;
  final bool autoPause;
  final bool keepScreenOn;

  final Set<String> completedMissions;
  final Map<String, DateTime> unlockedAchievements;
  final Set<String> unlockedCodex;
  final Map<String, int> missionAttempts;

  /// Remembers the goal the runner last chose per mission, so a retry starts
  /// from what they already decided rather than the author's suggestion.
  final Map<String, Map<String, dynamic>> lastGoalByMission;

  bool get isMetric => units == UnitSystem.metric;

  Profile copyWith({
    String? callsign,
    double? weightKg,
    UnitSystem? units,
    StreakGoal? streakGoal,
    AudioInterrupt? audioInterrupt,
    bool? voiceEnabled,
    double? speechRate,
    double? sfxVolume,
    bool? ambientBed,
    bool? chasesEnabled,
    bool? autoPause,
    bool? keepScreenOn,
    Set<String>? completedMissions,
    Map<String, DateTime>? unlockedAchievements,
    Set<String>? unlockedCodex,
    Map<String, int>? missionAttempts,
    Map<String, Map<String, dynamic>>? lastGoalByMission,
  }) => Profile(
    callsign: callsign ?? this.callsign,
    weightKg: weightKg ?? this.weightKg,
    units: units ?? this.units,
    streakGoal: streakGoal ?? this.streakGoal,
    audioInterrupt: audioInterrupt ?? this.audioInterrupt,
    voiceEnabled: voiceEnabled ?? this.voiceEnabled,
    speechRate: speechRate ?? this.speechRate,
    sfxVolume: sfxVolume ?? this.sfxVolume,
    ambientBed: ambientBed ?? this.ambientBed,
    chasesEnabled: chasesEnabled ?? this.chasesEnabled,
    autoPause: autoPause ?? this.autoPause,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    completedMissions: completedMissions ?? this.completedMissions,
    unlockedAchievements: unlockedAchievements ?? this.unlockedAchievements,
    unlockedCodex: unlockedCodex ?? this.unlockedCodex,
    missionAttempts: missionAttempts ?? this.missionAttempts,
    lastGoalByMission: lastGoalByMission ?? this.lastGoalByMission,
  );

  Map<String, dynamic> toJson() => {
    'callsign': callsign,
    'weightKg': weightKg,
    'units': units.name,
    'streakGoal': streakGoal.toJson(),
    'audioInterrupt': audioInterrupt.name,
    'voiceEnabled': voiceEnabled,
    'speechRate': speechRate,
    'sfxVolume': sfxVolume,
    'ambientBed': ambientBed,
    'chasesEnabled': chasesEnabled,
    'autoPause': autoPause,
    'keepScreenOn': keepScreenOn,
    'completedMissions': completedMissions.toList(),
    'unlockedAchievements': unlockedAchievements.map((k, v) => MapEntry(k, v.toIso8601String())),
    'unlockedCodex': unlockedCodex.toList(),
    'missionAttempts': missionAttempts,
    'lastGoalByMission': lastGoalByMission,
  };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    callsign: json['callsign'] as String? ?? 'RUNNER',
    weightKg: (json['weightKg'] as num?)?.toDouble() ?? 72,
    units: UnitSystem.values.firstWhere((u) => u.name == json['units'], orElse: () => UnitSystem.metric),
    streakGoal: json['streakGoal'] == null
        ? const StreakGoal()
        : StreakGoal.fromJson(Map<String, dynamic>.from(json['streakGoal'] as Map)),
    audioInterrupt: AudioInterrupt.values.firstWhere(
      (a) => a.name == json['audioInterrupt'],
      orElse: () => AudioInterrupt.pause,
    ),
    voiceEnabled: json['voiceEnabled'] as bool? ?? true,
    speechRate: (json['speechRate'] as num?)?.toDouble() ?? 0.52,
    sfxVolume: (json['sfxVolume'] as num?)?.toDouble() ?? 0.9,
    ambientBed: json['ambientBed'] as bool? ?? false,
    chasesEnabled: json['chasesEnabled'] as bool? ?? true,
    autoPause: json['autoPause'] as bool? ?? true,
    keepScreenOn: json['keepScreenOn'] as bool? ?? true,
    completedMissions: ((json['completedMissions'] as List?) ?? const []).map((e) => e as String).toSet(),
    unlockedAchievements: ((json['unlockedAchievements'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k as String, DateTime.parse(v as String)),
    ),
    unlockedCodex: ((json['unlockedCodex'] as List?) ?? const []).map((e) => e as String).toSet(),
    missionAttempts: ((json['missionAttempts'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k as String, (v as num).toInt()),
    ),
    lastGoalByMission: ((json['lastGoalByMission'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map)),
    ),
  );
}
