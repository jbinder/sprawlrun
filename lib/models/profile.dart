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

/// Which weekly target applied in a given week.
///
/// A streak is judged week by week, and each week against the target that was
/// in force *then*. Judging every past week against today's target meant that
/// raising it — once by accident, to 135 min — erased a whole streak with
/// every run still in the log.
///
/// A plain [StreakGoal] is the simplest answer: the same target every week.
abstract interface class WeeklyTargets {
  /// The target for the week starting [weekStart] (a Monday, midnight).
  StreakGoal goalFor(DateTime weekStart);

  /// The target in force now.
  StreakGoal get current;
}

/// One change of the weekly target: [goal] applies from the week starting
/// [from] until the next change.
class StreakGoalChange {
  const StreakGoalChange({required this.from, required this.goal});

  final DateTime from;
  final StreakGoal goal;

  Map<String, dynamic> toJson() => {'from': from.toIso8601String(), 'goal': goal.toJson()};

  /// Null for anything malformed, so one bad entry costs only itself.
  static StreakGoalChange? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final from = DateTime.tryParse(raw['from'] as String? ?? '');
    final goal = raw['goal'];
    if (from == null || goal is! Map) return null;
    return StreakGoalChange(from: from, goal: StreakGoal.fromJson(Map<String, dynamic>.from(goal)));
  }
}

/// The targets a runner has had, oldest first. Before the first recorded
/// change — and always, for a profile written before changes were recorded —
/// the earliest known target applies.
class StreakGoalHistory implements WeeklyTargets {
  const StreakGoalHistory({required this.current, required this.changes});

  @override
  final StreakGoal current;
  final List<StreakGoalChange> changes;

  @override
  StreakGoal goalFor(DateTime weekStart) {
    if (changes.isEmpty) return current;
    var goal = changes.first.goal;
    for (final c in changes) {
      if (c.from.isAfter(weekStart)) break;
      goal = c.goal;
    }
    return goal;
  }
}

/// The weekly commitment that keeps a streak alive.
class StreakGoal implements WeeklyTargets {
  const StreakGoal({this.metric = StreakMetric.minutes, this.target = 30});

  final StreakMetric metric;
  final double target;

  /// The target as Settings shows it, under the label "Weekly target" — so no
  /// "/ week" of its own, which only repeated the label.
  String get label => switch (metric) {
    StreakMetric.minutes => '${target.round()} min',
    StreakMetric.kilometres => '${target.toStringAsFixed(1)} km',
    StreakMetric.missions => '${target.round()} mission${target == 1 ? '' : 's'}',
  };

  String get unitLabel => switch (metric) {
    StreakMetric.minutes => 'MIN',
    StreakMetric.kilometres => 'KM',
    StreakMetric.missions => 'OPS',
  };

  StreakGoal copyWith({StreakMetric? metric, double? target}) =>
      StreakGoal(metric: metric ?? this.metric, target: target ?? this.target);

  /// The same target every week.
  @override
  StreakGoal goalFor(DateTime weekStart) => this;

  @override
  StreakGoal get current => this;

  @override
  bool operator ==(Object other) => other is StreakGoal && other.metric == metric && other.target == target;

  @override
  int get hashCode => Object.hash(metric, target);

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
    this.debriefEnabled = true,
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

  /// Whether the handlers send anything at all between runs. Gates the
  /// timeline as well as the schedule: with every signal off there is nothing
  /// of theirs to read back.
  bool get anyEnabled => remindersEnabled || ambientPerWeek > 0 || debriefEnabled;

  /// Whether the handler sends a readout when the week closes.
  ///
  /// On by default, deliberately unlike [remindersEnabled]. Reminders are
  /// several messages a week that an upgrade has no business starting unasked;
  /// a debrief is one, it reports the runner's own target back to them, and it
  /// is the kind of thing nobody goes looking for in settings. It can be
  /// switched off there, or silenced on its own Android channel.
  final bool debriefEnabled;

  int get hour => minutesFromMidnight ~/ 60;
  int get minute => minutesFromMidnight % 60;

  /// `07:00`, for the settings readout.
  String get label => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  SignalSettings copyWith({
    bool? remindersEnabled,
    Set<int>? weekdays,
    int? minutesFromMidnight,
    int? ambientPerWeek,
    bool? debriefEnabled,
  }) => SignalSettings(
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    weekdays: weekdays ?? this.weekdays,
    minutesFromMidnight: minutesFromMidnight ?? this.minutesFromMidnight,
    ambientPerWeek: ambientPerWeek ?? this.ambientPerWeek,
    debriefEnabled: debriefEnabled ?? this.debriefEnabled,
  );

  Map<String, dynamic> toJson() => {
    'remindersEnabled': remindersEnabled,
    'weekdays': weekdays.toList()..sort(),
    'minutesFromMidnight': minutesFromMidnight,
    'ambientPerWeek': ambientPerWeek,
    'debriefEnabled': debriefEnabled,
  };

  factory SignalSettings.fromJson(Map<String, dynamic> json) => SignalSettings(
    remindersEnabled: json['remindersEnabled'] as bool? ?? false,
    weekdays: ((json['weekdays'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .where((d) => d >= DateTime.monday && d <= DateTime.sunday)
        .toSet(),
    minutesFromMidnight: ((json['minutesFromMidnight'] as num?)?.toInt() ?? 7 * 60).clamp(0, 24 * 60 - 1),
    ambientPerWeek: ((json['ambientPerWeek'] as num?)?.toInt() ?? 0).clamp(0, 21),
    debriefEnabled: json['debriefEnabled'] as bool? ?? true,
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
    this.streakGoalChanges = const [],
    this.audioInterrupt = AudioInterrupt.pause,
    this.resumeMusic = true,
    this.voiceEnabled = true,
    this.speechRate = 0.52,
    this.sfxVolume = 0.9,
    this.ambientBed = false,
    this.chasesEnabled = true,
    this.autoPause = true,
    this.keepScreenOn = true,
    this.splitsEnabled = true,
    this.activePackId,
    this.completedMissions = const <String>{},
    this.unlockedAchievements = const <String, DateTime>{},
    this.unlockedCodex = const <String>{},
    this.missionAttempts = const <String, int>{},
    this.lastGoalByMission = const <String, Map<String, dynamic>>{},
    this.signals = const SignalSettings(),
    this.dataVersion = 0,
    this.lastExportAt,
    this.backupNudgeSnoozedAt,
  });

  final String callsign;
  final double weightKg;
  final UnitSystem units;
  final StreakGoal streakGoal;

  /// Every change of [streakGoal], oldest first, so each week of a streak is
  /// judged against the target of its own time — see [WeeklyTargets]. Empty
  /// for a profile from before changes were recorded, which then judges every
  /// week against [streakGoal] as it always did.
  final List<StreakGoalChange> streakGoalChanges;

  /// What stats and achievements judge the streak by.
  WeeklyTargets get streakTargets => StreakGoalHistory(current: streakGoal, changes: streakGoalChanges);

  /// Sets the weekly target from the week starting [thisWeek] on, leaving
  /// every earlier week judged against what applied then. Several changes in
  /// one week are one change; changing back undoes it.
  Profile withStreakGoal(StreakGoal next, {required DateTime thisWeek}) {
    if (next == streakGoal) return this;
    // The first change ever also records what came before, from the start of
    // time, or earlier weeks would fall back to the new target.
    final changes = streakGoalChanges.isEmpty
        ? [StreakGoalChange(from: DateTime(2000), goal: streakGoal)]
        : [...streakGoalChanges.where((c) => c.from.isBefore(thisWeek))];
    if (changes.isEmpty || changes.last.goal != next) {
      changes.add(StreakGoalChange(from: thisWeek, goal: next));
    }
    return copyWith(streakGoal: next, streakGoalChanges: changes);
  }

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

  /// Whether each kilometre (or mile) is read out as it passes. On a mission
  /// the readout waits for any beat or pursuit to finish: a dry readout
  /// mid-scene would both delay the story and break the mood.
  final bool splitsEnabled;

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

  /// When a backup was last *attempted*, not when one was last kept.
  ///
  /// The export hands the file to the system share sheet, which cannot tell the
  /// app whether the runner saved it — Android reports a dismissal even after a
  /// real save with some file managers. Nagging somebody who did back up is
  /// worse than missing somebody who did not, so an attempt counts. Null means
  /// no export has ever been made from this device.
  final DateTime? lastExportAt;

  /// When the runner last dismissed the backup nudge. A dismissal older than
  /// [lastExportAt] is spent, since the export answered it.
  final DateTime? backupNudgeSnoozedAt;

  bool get isMetric => units == UnitSystem.metric;

  Profile copyWith({
    String? callsign,
    double? weightKg,
    UnitSystem? units,
    StreakGoal? streakGoal,
    List<StreakGoalChange>? streakGoalChanges,
    AudioInterrupt? audioInterrupt,
    bool? resumeMusic,
    bool? voiceEnabled,
    double? speechRate,
    double? sfxVolume,
    bool? ambientBed,
    bool? chasesEnabled,
    bool? autoPause,
    bool? keepScreenOn,
    bool? splitsEnabled,
    String? activePackId,
    Set<String>? completedMissions,
    Map<String, DateTime>? unlockedAchievements,
    Set<String>? unlockedCodex,
    Map<String, int>? missionAttempts,
    Map<String, Map<String, dynamic>>? lastGoalByMission,
    SignalSettings? signals,
    int? dataVersion,
    DateTime? lastExportAt,
    DateTime? backupNudgeSnoozedAt,
  }) => Profile(
    callsign: callsign ?? this.callsign,
    weightKg: weightKg ?? this.weightKg,
    units: units ?? this.units,
    streakGoal: streakGoal ?? this.streakGoal,
    streakGoalChanges: streakGoalChanges ?? this.streakGoalChanges,
    audioInterrupt: audioInterrupt ?? this.audioInterrupt,
    resumeMusic: resumeMusic ?? this.resumeMusic,
    voiceEnabled: voiceEnabled ?? this.voiceEnabled,
    speechRate: speechRate ?? this.speechRate,
    sfxVolume: sfxVolume ?? this.sfxVolume,
    ambientBed: ambientBed ?? this.ambientBed,
    chasesEnabled: chasesEnabled ?? this.chasesEnabled,
    autoPause: autoPause ?? this.autoPause,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    splitsEnabled: splitsEnabled ?? this.splitsEnabled,
    activePackId: activePackId ?? this.activePackId,
    completedMissions: completedMissions ?? this.completedMissions,
    unlockedAchievements: unlockedAchievements ?? this.unlockedAchievements,
    unlockedCodex: unlockedCodex ?? this.unlockedCodex,
    missionAttempts: missionAttempts ?? this.missionAttempts,
    lastGoalByMission: lastGoalByMission ?? this.lastGoalByMission,
    signals: signals ?? this.signals,
    dataVersion: dataVersion ?? this.dataVersion,
    lastExportAt: lastExportAt ?? this.lastExportAt,
    backupNudgeSnoozedAt: backupNudgeSnoozedAt ?? this.backupNudgeSnoozedAt,
  );

  Map<String, dynamic> toJson() => {
    'callsign': callsign,
    'weightKg': weightKg,
    'units': units.name,
    'streakGoal': streakGoal.toJson(),
    'streakGoalChanges': [for (final c in streakGoalChanges) c.toJson()],
    'audioInterrupt': audioInterrupt.name,
    'resumeMusic': resumeMusic,
    'voiceEnabled': voiceEnabled,
    'speechRate': speechRate,
    'sfxVolume': sfxVolume,
    'ambientBed': ambientBed,
    'chasesEnabled': chasesEnabled,
    'autoPause': autoPause,
    'keepScreenOn': keepScreenOn,
    'splitsEnabled': splitsEnabled,
    if (activePackId != null) 'activePackId': activePackId,
    'completedMissions': completedMissions.toList(),
    'unlockedAchievements': unlockedAchievements.map((k, v) => MapEntry(k, v.toIso8601String())),
    'unlockedCodex': unlockedCodex.toList(),
    'missionAttempts': missionAttempts,
    'lastGoalByMission': lastGoalByMission,
    'signals': signals.toJson(),
    'dataVersion': dataVersion,
    if (lastExportAt != null) 'lastExportAt': lastExportAt!.toIso8601String(),
    if (backupNudgeSnoozedAt != null) 'backupNudgeSnoozedAt': backupNudgeSnoozedAt!.toIso8601String(),
  };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    callsign: json['callsign'] as String? ?? 'RUNNER',
    weightKg: (json['weightKg'] as num?)?.toDouble() ?? 72,
    units: UnitSystem.values.firstWhere((u) => u.name == json['units'], orElse: () => UnitSystem.metric),
    streakGoal: json['streakGoal'] == null
        ? const StreakGoal()
        : StreakGoal.fromJson(Map<String, dynamic>.from(json['streakGoal'] as Map)),
    streakGoalChanges: [
      for (final raw in json['streakGoalChanges'] as List? ?? const []) ?StreakGoalChange.tryParse(raw),
    ]..sort((a, b) => a.from.compareTo(b.from)),
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
    splitsEnabled: json['splitsEnabled'] as bool? ?? true,
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
    lastExportAt: DateTime.tryParse(json['lastExportAt'] as String? ?? ''),
    backupNudgeSnoozedAt: DateTime.tryParse(json['backupNudgeSnoozedAt'] as String? ?? ''),
  );
}
