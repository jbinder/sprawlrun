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
/// When the handlers get in touch between runs.
///
/// Times are plain ints rather than `TimeOfDay` so that `models/` stays free of
/// Flutter imports and the whole thing is JSON-primitive.
class SignalSettings {
  const SignalSettings({
    this.remindersEnabled = false,
    this.weekdays = const {DateTime.monday, DateTime.wednesday, DateTime.friday},
    this.minutesFromMidnight = 7 * 60,
    this.ambientPerWeek = 0,
  });

  /// Off until the runner asks for it: an app that starts messaging you
  /// unprompted is an app that gets its notifications muted wholesale.
  final bool remindersEnabled;

  /// `DateTime.monday`..`DateTime.sunday`.
  final Set<int> weekdays;

  final int minutesFromMidnight;

  /// Ambient traffic, 0 for none. Quiet hours apply to these and not to
  /// reminders, which fire at the time the runner chose.
  final int ambientPerWeek;

  int get hour => minutesFromMidnight ~/ 60;
  int get minute => minutesFromMidnight % 60;

  /// `07:00`, for the settings readout.
  String get label => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  SignalSettings copyWith({
    bool? remindersEnabled,
    Set<int>? weekdays,
    int? minutesFromMidnight,
    int? ambientPerWeek,
  }) => SignalSettings(
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    weekdays: weekdays ?? this.weekdays,
    minutesFromMidnight: minutesFromMidnight ?? this.minutesFromMidnight,
    ambientPerWeek: ambientPerWeek ?? this.ambientPerWeek,
  );

  Map<String, dynamic> toJson() => {
    'remindersEnabled': remindersEnabled,
    'weekdays': weekdays.toList()..sort(),
    'minutesFromMidnight': minutesFromMidnight,
    'ambientPerWeek': ambientPerWeek,
  };

  factory SignalSettings.fromJson(Map<String, dynamic> json) => SignalSettings(
    remindersEnabled: json['remindersEnabled'] as bool? ?? false,
    weekdays: ((json['weekdays'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .where((d) => d >= DateTime.monday && d <= DateTime.sunday)
        .toSet(),
    minutesFromMidnight: ((json['minutesFromMidnight'] as num?)?.toInt() ?? 7 * 60).clamp(0, 24 * 60 - 1),
    ambientPerWeek: ((json['ambientPerWeek'] as num?)?.toInt() ?? 0).clamp(0, 21),
  );
}

/// Immutable — mutations go through [copyWith] and are persisted as a whole,
/// which keeps the on-disk state consistent even if the app dies mid-run.
class Profile {
  const Profile({
    this.callsign = 'RUNNER',
    this.weightKg = 72,
    this.units = UnitSystem.metric,
    this.streakGoal = const StreakGoal(),
    this.audioInterrupt = AudioInterrupt.pause,
    this.resumeMusic = true,
    this.voiceEnabled = true,
    this.speechRate = 0.52,
    this.sfxVolume = 0.9,
    this.ambientBed = false,
    this.chasesEnabled = true,
    this.autoPause = true,
    this.keepScreenOn = true,
    this.activePackId,
    this.completedMissions = const <String>{},
    this.unlockedAchievements = const <String, DateTime>{},
    this.unlockedCodex = const <String>{},
    this.missionAttempts = const <String, int>{},
    this.lastGoalByMission = const <String, Map<String, dynamic>>{},
    this.signals = const SignalSettings(),
    this.dataVersion = 0,
  });

  final String callsign;
  final double weightKg;
  final UnitSystem units;
  final StreakGoal streakGoal;

  final AudioInterrupt audioInterrupt;

  /// Whether to send a media-button PLAY when a music app fails to resume by
  /// itself after a transmission. See [MusicResumeGuard] for why that happens
  /// and how narrowly the nudge is aimed.
  final bool resumeMusic;

  final bool voiceEnabled;

  /// flutter_tts rate, 0..1. 0.5 is roughly natural on Android.
  final double speechRate;
  final double sfxVolume;

  /// Low ambient drone under the HUD for runners with no music of their own.
  final bool ambientBed;

  final bool chasesEnabled;
  final bool autoPause;
  final bool keepScreenOn;

  /// The mission pack the ops screen shows. Null means the first loaded pack,
  /// which is also what every profile from before packs were selectable
  /// resolves to.
  final String? activePackId;

  final Set<String> completedMissions;
  final Map<String, DateTime> unlockedAchievements;
  final Set<String> unlockedCodex;
  final Map<String, int> missionAttempts;

  /// Remembers the goal the runner last chose per mission, so a retry starts
  /// from what they already decided rather than the author's suggestion.
  final Map<String, Map<String, dynamic>> lastGoalByMission;

  /// When the handlers get in touch between runs.
  final SignalSettings signals;

  /// How far `Migrations` has brought this profile. 0 is anything written
  /// before migrations existed, which is the state that needs all of them.
  final int dataVersion;

  bool get isMetric => units == UnitSystem.metric;

  Profile copyWith({
    String? callsign,
    double? weightKg,
    UnitSystem? units,
    StreakGoal? streakGoal,
    AudioInterrupt? audioInterrupt,
    bool? resumeMusic,
    bool? voiceEnabled,
    double? speechRate,
    double? sfxVolume,
    bool? ambientBed,
    bool? chasesEnabled,
    bool? autoPause,
    bool? keepScreenOn,
    String? activePackId,
    Set<String>? completedMissions,
    Map<String, DateTime>? unlockedAchievements,
    Set<String>? unlockedCodex,
    Map<String, int>? missionAttempts,
    Map<String, Map<String, dynamic>>? lastGoalByMission,
    SignalSettings? signals,
    int? dataVersion,
  }) => Profile(
    callsign: callsign ?? this.callsign,
    weightKg: weightKg ?? this.weightKg,
    units: units ?? this.units,
    streakGoal: streakGoal ?? this.streakGoal,
    audioInterrupt: audioInterrupt ?? this.audioInterrupt,
    resumeMusic: resumeMusic ?? this.resumeMusic,
    voiceEnabled: voiceEnabled ?? this.voiceEnabled,
    speechRate: speechRate ?? this.speechRate,
    sfxVolume: sfxVolume ?? this.sfxVolume,
    ambientBed: ambientBed ?? this.ambientBed,
    chasesEnabled: chasesEnabled ?? this.chasesEnabled,
    autoPause: autoPause ?? this.autoPause,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    activePackId: activePackId ?? this.activePackId,
    completedMissions: completedMissions ?? this.completedMissions,
    unlockedAchievements: unlockedAchievements ?? this.unlockedAchievements,
    unlockedCodex: unlockedCodex ?? this.unlockedCodex,
    missionAttempts: missionAttempts ?? this.missionAttempts,
    lastGoalByMission: lastGoalByMission ?? this.lastGoalByMission,
    signals: signals ?? this.signals,
    dataVersion: dataVersion ?? this.dataVersion,
  );

  Map<String, dynamic> toJson() => {
    'callsign': callsign,
    'weightKg': weightKg,
    'units': units.name,
    'streakGoal': streakGoal.toJson(),
    'audioInterrupt': audioInterrupt.name,
    'resumeMusic': resumeMusic,
    'voiceEnabled': voiceEnabled,
    'speechRate': speechRate,
    'sfxVolume': sfxVolume,
    'ambientBed': ambientBed,
    'chasesEnabled': chasesEnabled,
    'autoPause': autoPause,
    'keepScreenOn': keepScreenOn,
    if (activePackId != null) 'activePackId': activePackId,
    'completedMissions': completedMissions.toList(),
    'unlockedAchievements': unlockedAchievements.map((k, v) => MapEntry(k, v.toIso8601String())),
    'unlockedCodex': unlockedCodex.toList(),
    'missionAttempts': missionAttempts,
    'lastGoalByMission': lastGoalByMission,
    'signals': signals.toJson(),
    'dataVersion': dataVersion,
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
    resumeMusic: json['resumeMusic'] as bool? ?? true,
    voiceEnabled: json['voiceEnabled'] as bool? ?? true,
    speechRate: (json['speechRate'] as num?)?.toDouble() ?? 0.52,
    sfxVolume: (json['sfxVolume'] as num?)?.toDouble() ?? 0.9,
    ambientBed: json['ambientBed'] as bool? ?? false,
    chasesEnabled: json['chasesEnabled'] as bool? ?? true,
    autoPause: json['autoPause'] as bool? ?? true,
    keepScreenOn: json['keepScreenOn'] as bool? ?? true,
    activePackId: json['activePackId'] as String?,
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
    signals: json['signals'] == null
        ? const SignalSettings()
        : SignalSettings.fromJson(Map<String, dynamic>.from(json['signals'] as Map)),
    // Absent in anything written before migrations existed, which is exactly
    // the state that still needs them.
    dataVersion: (json['dataVersion'] as num?)?.toInt() ?? 0,
  );
}
