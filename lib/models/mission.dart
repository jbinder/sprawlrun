import 'goal.dart';

/// A single spoken line inside a story beat.
///
/// [speaker] drives both the on-screen colour and the synthesised voice, so a
/// runner with the phone in their pocket can still tell who is talking.
class StoryLine {
  const StoryLine({
    required this.speaker,
    required this.text,
    this.sfxBefore,
    this.sfxAfter,
    this.pauseAfterMs = 260,
  });

  final String speaker;
  final String text;

  /// Sound effect filename (without extension) played before/after the line.
  final String? sfxBefore;
  final String? sfxAfter;

  final int pauseAfterMs;

  factory StoryLine.fromJson(Map<String, dynamic> json) => StoryLine(
    speaker: json['speaker'] as String? ?? 'SYSTEM',
    text: json['text'] as String? ?? '',
    sfxBefore: json['sfxBefore'] as String?,
    sfxAfter: json['sfxAfter'] as String?,
    pauseAfterMs: (json['pauseAfterMs'] as num?)?.toInt() ?? 260,
  );

  Map<String, dynamic> toJson() => {
    'speaker': speaker,
    'text': text,
    if (sfxBefore != null) 'sfxBefore': sfxBefore,
    if (sfxAfter != null) 'sfxAfter': sfxAfter,
    'pauseAfterMs': pauseAfterMs,
  };
}

/// A timed chase attached to a beat: run harder for [duration] or lose ground.
///
/// Success is judged on distance covered during the window versus the runner's
/// own recent pace multiplied by [paceFactor] — never an absolute speed. A
/// 7 min/km jogger and a 4 min/km racer both get a chase that is hard for them
/// and neither gets one that is impossible.
class ChaseSpec {
  const ChaseSpec({
    required this.duration,
    this.paceFactor = 1.12,
    this.pursuer = 'unknown',
    this.escapedLines = const [],
    this.caughtLines = const [],
  });

  final Duration duration;
  final double paceFactor;

  /// Shown on the HUD during the chase ("VANTAR DRONE").
  final String pursuer;

  final List<StoryLine> escapedLines;
  final List<StoryLine> caughtLines;

  factory ChaseSpec.fromJson(Map<String, dynamic> json) => ChaseSpec(
    duration: Duration(seconds: (json['seconds'] as num?)?.toInt() ?? 60),
    paceFactor: (json['paceFactor'] as num?)?.toDouble() ?? 1.12,
    pursuer: json['pursuer'] as String? ?? 'unknown',
    escapedLines: _lines(json['escaped']),
    caughtLines: _lines(json['caught']),
  );

  Map<String, dynamic> toJson() => {
    'seconds': duration.inSeconds,
    'paceFactor': paceFactor,
    'pursuer': pursuer,
    'escaped': escapedLines.map((l) => l.toJson()).toList(),
    'caught': caughtLines.map((l) => l.toJson()).toList(),
  };
}

List<StoryLine> _lines(Object? raw) =>
    (raw as List?)?.map((e) => StoryLine.fromJson(Map<String, dynamic>.from(e as Map))).toList() ?? const [];

/// When a beat fires. A beat triggers as soon as *any* configured threshold is
/// crossed, so an author can pin an intro to t=0, space the middle of a mission
/// by goal fraction, and still force a line at a hard 5-minute mark.
class BeatTrigger {
  const BeatTrigger({this.fraction, this.seconds, this.meters});

  final double? fraction;
  final double? seconds;
  final double? meters;

  bool isReady({required double progress, required double elapsedSeconds, required double distanceMeters}) {
    if (fraction != null && progress >= fraction!) return true;
    if (seconds != null && elapsedSeconds >= seconds!) return true;
    if (meters != null && distanceMeters >= meters!) return true;
    return false;
  }

  factory BeatTrigger.fromJson(Map<String, dynamic> json) => BeatTrigger(
    fraction: (json['fraction'] as num?)?.toDouble(),
    seconds: (json['seconds'] as num?)?.toDouble(),
    meters: (json['meters'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    if (fraction != null) 'fraction': fraction,
    if (seconds != null) 'seconds': seconds,
    if (meters != null) 'meters': meters,
  };
}

/// One interlude: a burst of dialogue that ducks the runner's own music,
/// optionally followed by a chase.
class StoryBeat {
  const StoryBeat({
    required this.id,
    required this.trigger,
    required this.lines,
    this.chase,
    this.unlocksCodex,
    this.headline,
  });

  final String id;
  final BeatTrigger trigger;
  final List<StoryLine> lines;
  final ChaseSpec? chase;

  /// Codex entry id revealed once this beat plays.
  final String? unlocksCodex;

  /// Short banner flashed on the HUD while the beat plays.
  final String? headline;

  factory StoryBeat.fromJson(Map<String, dynamic> json) => StoryBeat(
    id: json['id'] as String,
    trigger: BeatTrigger.fromJson(Map<String, dynamic>.from(json['at'] as Map)),
    lines: _lines(json['lines']),
    chase: json['chase'] == null ? null : ChaseSpec.fromJson(Map<String, dynamic>.from(json['chase'] as Map)),
    unlocksCodex: json['unlocksCodex'] as String?,
    headline: json['headline'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': trigger.toJson(),
    'lines': lines.map((l) => l.toJson()).toList(),
    if (chase != null) 'chase': chase!.toJson(),
    if (unlocksCodex != null) 'unlocksCodex': unlocksCodex,
    if (headline != null) 'headline': headline,
  };
}

/// A world-building entry unlocked by playing through the story.
class CodexEntry {
  const CodexEntry({required this.id, required this.title, required this.category, required this.body});

  final String id;
  final String title;
  final String category;
  final String body;

  factory CodexEntry.fromJson(Map<String, dynamic> json) => CodexEntry(
    id: json['id'] as String,
    title: json['title'] as String,
    category: json['category'] as String? ?? 'INTEL',
    body: json['body'] as String,
  );
}

class Mission {
  const Mission({
    required this.id,
    required this.packId,
    required this.order,
    required this.codename,
    required this.title,
    required this.location,
    required this.brief,
    required this.objective,
    required this.debrief,
    required this.suggestedGoal,
    required this.beats,
    this.codex = const [],
    this.epilogue,
  });

  final String id;
  final String packId;

  /// 1-based position in the campaign; drives the locked/unlocked chain.
  final int order;

  /// Short operation name, e.g. "DEAD DROP".
  final String codename;
  final String title;
  final String location;

  /// Pre-run mission text shown on the brief screen.
  final String brief;

  /// One-line statement of what the runner is doing.
  final String objective;

  /// Shown after a successful run.
  final String debrief;

  /// Shown after the final mission of a pack, if present.
  final String? epilogue;

  final RunGoal suggestedGoal;
  final List<StoryBeat> beats;
  final List<CodexEntry> codex;

  /// Every beat that carries a chase, in trigger order.
  Iterable<StoryBeat> get chaseBeats => beats.where((b) => b.chase != null);

  factory Mission.fromJson(Map<String, dynamic> json, {required String packId}) => Mission(
    id: json['id'] as String,
    packId: packId,
    order: (json['order'] as num).toInt(),
    codename: json['codename'] as String,
    title: json['title'] as String,
    location: json['location'] as String? ?? '',
    brief: json['brief'] as String? ?? '',
    objective: json['objective'] as String? ?? '',
    debrief: json['debrief'] as String? ?? '',
    epilogue: json['epilogue'] as String?,
    suggestedGoal: RunGoal.fromJson(Map<String, dynamic>.from(json['suggestedGoal'] as Map)),
    beats: (json['beats'] as List? ?? [])
        .map((e) => StoryBeat.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    codex: (json['codex'] as List? ?? [])
        .map((e) => CodexEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

/// A shippable bundle of missions. The app loads the bundled pack plus any
/// packs dropped into the documents directory, which is how future story
/// content arrives without an app update.
class MissionPack {
  const MissionPack({required this.id, required this.title, required this.tagline, required this.missions});

  final String id;
  final String title;
  final String tagline;
  final List<Mission> missions;

  factory MissionPack.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final missions = (json['missions'] as List? ?? [])
        .map((e) => Mission.fromJson(Map<String, dynamic>.from(e as Map), packId: id))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return MissionPack(
      id: id,
      title: json['title'] as String? ?? id,
      tagline: json['tagline'] as String? ?? '',
      missions: missions,
    );
  }
}
