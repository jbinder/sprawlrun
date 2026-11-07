// A song, as data. Every song the app plays, shipped or not, is one JSON file in
// the format described in docs/SONGS.md: nothing about any song is in the code.
//
// Parsing checks everything, because a file is the only thing between a stranger
// and the runner's ears and CPU: fixed voices and effects, and every value in a
// range. No Flutter here, so tool/gen_music.dart can use it from `dart run`.

import 'dart:convert';

/// A song file this version can't play, or that breaks the format. The message
/// names what is wrong, for whoever is writing the file.
class SongFormatException implements Exception {
  const SongFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

const int beatsPerBar = 4;

/// Choices in the music setting that are not songs, present and planned. It
/// stores either these or a song id in one field, so a song can't be called one.
const Set<String> reservedSongIds = {'off', 'ambient', 'shuffle', 'best', 'folder'};

/// The longest note, in seconds, that a bus can hold.
const double maxNoteSeconds = 9;

/// How much of a song plays. A track plays at its own level and above.
enum MusicLevel { low, normal, high }

enum VoiceType { saw, dsaw, prophet, blade, pulse, triangle, sub, drum, riser }

/// One note or drum hit in a bar, whichever way the file wrote it.
class PatternEvent {
  const PatternEvent({required this.beat, this.note, required this.beats, this.amp, this.shareOf = 1, this.rate});

  final double beat;

  /// MIDI note. Null for a drum hit.
  final int? note;
  final double beats;

  /// Overrides the clip's and voice's amp. A drum roll sets this per step.
  final double? amp;

  /// How many notes share the amp, since `play` on a chord divides it.
  final int shareOf;

  /// Overrides the voice's sample rate.
  final double? rate;
}

/// A cycle of bars, indexed by the song's bar number, so patterns of the same
/// length stay aligned wherever a clip starts.
class SongPattern {
  const SongPattern(this.bars);

  final List<List<PatternEvent>> bars;

  List<PatternEvent> at(int songBar) => bars[songBar % bars.length];
}

/// A value held, or moving in a line over the clip's bars.
class Ramp {
  const Ramp(this.from, this.to);

  final double from, to;

  double at(double progress) => from + (to - from) * progress;
}

/// When a track plays which pattern, from bar [from] up to but not including
/// bar [to].
class Clip {
  const Clip({required this.from, required this.to, required this.pattern, this.cutoff, this.amp, this.transpose = 0});

  final int from, to;
  final SongPattern pattern;
  final Ramp? cutoff;
  final double? amp;
  final int transpose;

  bool playsAt(int bar) => bar >= from && bar < to;

  double progress(int bar) => (bar - from) / (to - from);
}

class Voice {
  const Voice({
    required this.type,
    this.amp = 1,
    this.attack = 0,
    this.sustain = 0,
    this.release = 0,
    this.attackOfNote = 0,
    this.sustainOfNote = 0,
    this.releaseOfNote = 0,
    this.cutoff = 100,
    this.detune = 0,
    this.vibratoRate = 0,
    this.vibratoDepth = 0,
    this.duty = 0.5,
    this.drum,
    this.rate = 1,
    this.drumCutoff,
    this.cutoffTo = 100,
    this.slide = 0,
  });

  final VoiceType type;
  final double amp;

  /// Envelope, in beats: this much, plus a share of the note's own length.
  final double attack, sustain, release, attackOfNote, sustainOfNote, releaseOfNote;
  final double cutoff, detune, vibratoRate, vibratoDepth;

  /// How much of a `pulse` wave's cycle is high.
  final double duty;
  final String? drum;
  final double rate;
  final double? drumCutoff;

  /// A riser's cutoff at the end of its [slide], in beats.
  final double cutoffTo, slide;
}

class Track {
  const Track({required this.id, required this.bus, required this.voice, required this.clips, this.level = MusicLevel.low});

  final String id, bus;

  /// The lowest level this track plays at. By default it always plays, so a song
  /// that names no levels sounds the same whatever the runner is doing.
  final MusicLevel level;
  final Voice voice;
  final List<Clip> clips;
}

/// A range of bars where an effect's mix differs from its usual one.
class MixClip {
  const MixClip(this.from, this.to, this.mix);

  final int from, to;
  final double mix;
}

sealed class Effect {
  const Effect();
}

/// A falling saw over each beat, so what goes through it is struck and fades.
class SlicerEffect extends Effect {
  const SlicerEffect({required this.mix, this.mixClips = const []});

  final double mix;
  final List<MixClip> mixClips;

  double mixAt(int bar) {
    for (final c in mixClips) {
      if (bar >= c.from && bar < c.to) return c.mix;
    }
    return mix;
  }
}

class EchoEffect extends Effect {
  const EchoEffect({required this.phase, required this.decay, required this.mix});

  final double phase, decay, mix;
}

/// Overdrive: pushes what goes through into a soft limit, for a harder edge.
class DriveEffect extends Effect {
  const DriveEffect({required this.amount, required this.mix, this.level = 1});

  /// [level] is what comes out, since turning down what goes in hardly changes
  /// the loudness of something already driven into its limit.
  final double amount, mix, level;
}

/// Width: one side of the bus heard a few milliseconds after the other.
class SpreadEffect extends Effect {
  const SpreadEffect({required this.ms});

  /// Positive delays the right, negative the left.
  final double ms;
}

class ReverbEffect extends Effect {
  const ReverbEffect({required this.room, required this.damp, required this.mix});

  final double room, damp, mix;
}

class Bus {
  const Bus(this.id, this.effects);

  final String id;

  /// In order. A reverb, being what makes a bus stereo, can only come last.
  final List<Effect> effects;
}

class SongSection {
  const SongSection(this.name, this.from);

  final String name;
  final int from;
}

class Song {
  const Song({
    required this.id,
    required this.name,
    this.names = const {},
    this.author,
    this.licence,
    required this.bpm,
    this.lowTempo = 1,
    this.highTempo = 1,
    this.key,
    this.moods = const [],
    this.energy = 0.5,
    required this.seed,
    required this.bars,
    required this.loopFrom,
    required this.sections,
    required this.buses,
    required this.tracks,
  });

  /// The newest format this version plays. Old formats keep playing as they
  /// did, which is why a synth's sound can't simply change.
  static const int currentFormat = 1;

  static const int maxBytes = 256 * 1024;

  final String id, name;
  final Map<String, String> names;
  final String? author, licence;
  final double bpm;

  /// How much of its tempo the song keeps at [MusicLevel.low]. Stops at 0.88: a
  /// note slows with the song, and a bus has to outlast the longest one.
  final double lowTempo;

  /// How much of its tempo the song plays at at [MusicLevel.high].
  final double highTempo;
  final String? key;
  final List<String> moods;

  /// How hard the song drives, 0 to 1. For choosing one, not for playing it.
  final double energy;
  final int seed;

  /// Bars in the first pass, and where the song goes back to after them.
  final int bars, loopFrom;
  final List<SongSection> sections;
  final List<Bus> buses;
  final List<Track> tracks;

  double get secondsPerBeat => 60 / bpm;

  String nameIn(String language) => names[language] ?? name;

  /// The song's own bar for the [n]th bar played, past the first pass looping.
  int songBar(int n) => n < bars ? n : loopFrom + ((n - bars) % (bars - loopFrom));

  /// Throws [SongFormatException] if [source] isn't a song this version plays.
  static Song parse(String source) {
    if (source.length > maxBytes) throw const SongFormatException('The file is too large for a song');
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const SongFormatException('The file is not JSON');
    }
    if (decoded is! Map<String, dynamic>) throw const SongFormatException('The file is not a song');
    return _SongParser(decoded).parse();
  }
}

class _SongParser {
  _SongParser(this.json);

  final Map<String, dynamic> json;

  static final RegExp _idPattern = RegExp(r'^[a-z0-9_-]{1,40}$');
  static final RegExp _notePattern = RegExp(r'^([a-g])(#|b)?(-?\d)$');
  static const Map<String, int> _pitchClass = {'c': 0, 'd': 2, 'e': 4, 'f': 5, 'g': 7, 'a': 9, 'b': 11};
  static const Set<String> _drums = {
    'kick',
    'snare',
    'dubSnare',
    'hat',
    'splash',
    'boom',
    'taiko',
    'taikoHigh',
    'chipKick',
    'chipSnare',
    'chipHat',
  };

  static const int _maxBars = 512;
  static const int _maxTracks = 32;
  static const int _maxBuses = 10;
  static const int _maxEventsPerBar = 64;

  Song parse() {
    final format = _int(json, 'format', 1, 1000);
    if (format > Song.currentFormat) throw const SongFormatException('This song needs a newer version of the app');

    final id = _string(json, 'id');
    if (!_idPattern.hasMatch(id)) throw SongFormatException('Bad id "$id": use a-z, 0-9, _ and -');
    if (reservedSongIds.contains(id)) throw SongFormatException('The id "$id" is taken by the music setting');
    final bars = _int(json, 'bars', 1, _maxBars);
    final loopFrom = _int(json, 'loopFrom', 0, bars - 1);
    final buses = _buses(bars);
    final patterns = _patterns();
    final tracks = _tracks(buses, patterns, bars);

    final bpm = _double(json, 'bpm', 60, 200);
    final song = Song(
      id: id,
      name: _string(json, 'name'),
      names: _names(),
      lowTempo: json.containsKey('lowTempo') ? _double(json, 'lowTempo', 0.88, 1) : 1,
      highTempo: json.containsKey('highTempo') ? _double(json, 'highTempo', 1, 1.15) : 1,
      author: _optionalString(json, 'author'),
      licence: _optionalString(json, 'licence'),
      bpm: bpm,
      key: _optionalString(json, 'key'),
      moods: [for (final m in _list(json, 'moods', required: false)) _asString(m, 'moods')],
      energy: json.containsKey('energy') ? _double(json, 'energy', 0, 1) : 0.5,
      seed: _int(json, 'seed', 0, 1 << 30),
      bars: bars,
      loopFrom: loopFrom,
      sections: _sections(bars),
      buses: buses,
      tracks: tracks,
    );
    _checkNoteLengths(song);
    return song;
  }

  /// A bus can only hold so much, so a note past that would be cut off.
  void _checkNoteLengths(Song song) {
    for (final track in song.tracks) {
      final v = track.voice;
      if (v.type == VoiceType.drum || v.type == VoiceType.riser) continue;
      for (final clip in track.clips) {
        for (final bar in clip.pattern.bars) {
          for (final e in bar) {
            final beats =
                v.attack +
                v.sustain +
                v.release +
                (v.attackOfNote + v.sustainOfNote + v.releaseOfNote) * e.beats;
            if (beats * song.secondsPerBeat > maxNoteSeconds) {
              throw SongFormatException('A note in track "${track.id}" is longer than $maxNoteSeconds seconds');
            }
          }
        }
      }
    }
  }

  Map<String, String> _names() {
    final raw = json['names'];
    if (raw == null) return const {};
    if (raw is! Map) throw const SongFormatException('"names" must map languages to names');
    return {for (final e in raw.entries) '${e.key}': _asString(e.value, 'names')};
  }

  List<SongSection> _sections(int bars) {
    final sections = <SongSection>[];
    var last = -1;
    for (final raw in _list(json, 'sections', required: false)) {
      final s = _map(raw, 'sections');
      final from = _int(s, 'from', 0, bars - 1);
      if (from <= last) throw const SongFormatException('"sections" must be in order');
      last = from;
      sections.add(SongSection(_string(s, 'name'), from));
    }
    return sections;
  }

  List<Bus> _buses(int bars) {
    final raw = _list(json, 'buses');
    if (raw.isEmpty || raw.length > _maxBuses) throw const SongFormatException('A song has 1 to $_maxBuses buses');
    final seen = <String>{};
    return [
      for (final b in raw)
        () {
          final bus = _map(b, 'buses');
          final id = _string(bus, 'id');
          if (!seen.add(id)) throw SongFormatException('Bus "$id" is defined twice');
          final effects = [for (final e in _list(bus, 'effects', required: false)) _effect(_map(e, 'effects'), bars)];
          for (var i = 0; i < effects.length - 1; i++) {
            if (effects[i] is ReverbEffect) throw SongFormatException('On bus "$id", a reverb must come last');
          }
          return Bus(id, effects);
        }(),
    ];
  }

  Effect _effect(Map<String, dynamic> e, int bars) {
    final type = _string(e, 'type');
    return switch (type) {
      'slicer' => SlicerEffect(
        mix: _double(e, 'mix', 0, 1),
        mixClips: [
          for (final raw in _list(e, 'mixClips', required: false))
            () {
              final c = _map(raw, 'mixClips');
              return MixClip(_int(c, 'from', 0, bars), _int(c, 'to', 0, bars), _double(c, 'mix', 0, 1));
            }(),
        ],
      ),
      'echo' => EchoEffect(
        phase: _double(e, 'phase', 0.05, 4),
        decay: _double(e, 'decay', 0.1, 16),
        mix: _double(e, 'mix', 0, 1),
      ),
      'drive' => DriveEffect(
        amount: _double(e, 'amount', 1, 20),
        mix: _double(e, 'mix', 0, 1),
        level: e.containsKey('level') ? _double(e, 'level', 0, 1) : 1,
      ),
      'spread' => SpreadEffect(ms: _double(e, 'ms', -40, 40)),
      'reverb' => ReverbEffect(
        room: _double(e, 'room', 0, 1),
        damp: _double(e, 'damp', 0, 1),
        mix: _double(e, 'mix', 0, 1),
      ),
      _ => throw SongFormatException('Unknown effect "$type"'),
    };
  }

  Map<String, SongPattern> _patterns() {
    final raw = json['patterns'];
    if (raw is! Map) throw const SongFormatException('"patterns" is missing');
    return {
      for (final e in raw.entries)
        '${e.key}': () {
          final bars = <List<PatternEvent>>[];
          for (final barRaw in _asList(e.value, 'pattern "${e.key}"')) {
            final bar = _map(barRaw, 'pattern "${e.key}"');
            final events = _events(bar, '${e.key}');
            final repeat = bar.containsKey('repeat') ? _int(bar, 'repeat', 1, _maxBars) : 1;
            for (var i = 0; i < repeat; i++) {
              bars.add(events);
            }
          }
          if (bars.isEmpty || bars.length > _maxBars) {
            throw SongFormatException('Pattern "${e.key}" has no bars, or too many');
          }
          return SongPattern(bars);
        }(),
    };
  }

  /// A bar is one of: `hits`, a grid of drum hits; `notes`, a grid of notes,
  /// null for a rest; `phrase`, notes one after another; `chord`, notes
  /// together; or `rest`.
  List<PatternEvent> _events(Map<String, dynamic> bar, String pattern) {
    final events = <PatternEvent>[];
    final every = bar.containsKey('every') ? _double(bar, 'every', 0.0625, beatsPerBar.toDouble()) : null;

    if (bar['hits'] != null) {
      final hits = _string(bar, 'hits');
      final step = every ?? 0.25;
      final amp = bar.containsKey('amp') ? _double(bar, 'amp', 0, 2) : null;
      final ampStep = bar.containsKey('ampStep') ? _double(bar, 'ampStep', -1, 1) : 0.0;
      final rate = bar.containsKey('rate') ? _double(bar, 'rate', 0.25, 4) : null;
      for (var i = 0; i < hits.length; i++) {
        final c = hits[i];
        if (c == '.') continue;
        if (c != 'x') throw SongFormatException('In pattern "$pattern", hits use only x and .');
        events.add(
          PatternEvent(
            beat: i * step,
            beats: step,
            amp: amp == null ? null : (amp + i * ampStep).clamp(0.0, 2.0),
            rate: rate,
          ),
        );
      }
    } else if (bar['notes'] != null) {
      final step = every ?? 0.5;
      final notes = _list(bar, 'notes');
      for (var i = 0; i < notes.length; i++) {
        if (notes[i] == null) continue;
        events.add(PatternEvent(beat: i * step, note: _note(notes[i]), beats: step));
      }
    } else if (bar['phrase'] != null) {
      var at = 0.0;
      for (final raw in _list(bar, 'phrase')) {
        final pair = _asList(raw, 'phrase');
        if (pair.length != 2) throw SongFormatException('In pattern "$pattern", a phrase step is [note, beats]');
        final beats = _asDouble(pair[1], 'phrase', 0.03125, beatsPerBar.toDouble());
        if (pair[0] != null) events.add(PatternEvent(beat: at, note: _note(pair[0]), beats: beats));
        at += beats;
      }
    } else if (bar['chord'] != null) {
      final notes = _list(bar, 'chord');
      for (final n in notes) {
        events.add(PatternEvent(beat: 0, note: _note(n), beats: beatsPerBar.toDouble(), shareOf: notes.length));
      }
    } else if (bar['rest'] != true) {
      throw SongFormatException('In pattern "$pattern", a bar needs hits, notes, phrase, chord or rest');
    }

    if (events.length > _maxEventsPerBar) {
      throw SongFormatException('Pattern "$pattern" has more than $_maxEventsPerBar events in a bar');
    }
    for (final e in events) {
      if (e.beat >= beatsPerBar) throw SongFormatException('Pattern "$pattern" runs past the end of its bar');
    }
    return events;
  }

  int _note(Object? raw) {
    final name = _asString(raw, 'note');
    final m = _notePattern.firstMatch(name);
    if (m == null) throw SongFormatException('Bad note "$name"');
    final accidental = switch (m.group(2)) {
      '#' => 1,
      'b' => -1,
      _ => 0,
    };
    final note = _pitchClass[m.group(1)]! + accidental + 12 * (int.parse(m.group(3)!) + 1);
    if (note < 12 || note > 108) throw SongFormatException('Note "$name" is out of range');
    return note;
  }

  List<Track> _tracks(List<Bus> buses, Map<String, SongPattern> patterns, int bars) {
    final raw = _list(json, 'tracks');
    if (raw.isEmpty || raw.length > _maxTracks) throw const SongFormatException('A song has 1 to $_maxTracks tracks');
    final busIds = {for (final b in buses) b.id};
    return [
      for (final t in raw)
        () {
          final track = _map(t, 'tracks');
          final id = _string(track, 'id');
          final bus = _string(track, 'bus');
          if (!busIds.contains(bus)) throw SongFormatException('Track "$id" uses unknown bus "$bus"');
          final voice = _voice(_map(track['voice'], 'voice'));
          final clips = [
            for (final c in _list(track, 'clips')) _clip(_map(c, 'clips'), patterns, bars, id, voice),
          ];
          return Track(id: id, bus: bus, voice: voice, clips: clips, level: _level(track, id));
        }(),
    ];
  }

  MusicLevel _level(Map<String, dynamic> track, String id) {
    if (!track.containsKey('level')) return MusicLevel.low;
    final name = _string(track, 'level');
    final level = MusicLevel.values.where((l) => l.name == name).firstOrNull;
    if (level == null) throw SongFormatException('Track "$id": unknown level "$name"');
    return level;
  }

  Clip _clip(Map<String, dynamic> c, Map<String, SongPattern> patterns, int bars, String track, Voice voice) {
    final from = _int(c, 'from', 0, bars - 1);
    final to = _int(c, 'to', from + 1, bars);
    final patternName = _string(c, 'pattern');
    final pattern = patterns[patternName];
    if (pattern == null) throw SongFormatException('Track "$track" uses unknown pattern "$patternName"');
    final isDrum = voice.type == VoiceType.drum;
    for (final bar in pattern.bars) {
      for (final e in bar) {
        if (isDrum != (e.note == null)) {
          throw SongFormatException('Track "$track": drums use hits, and synths use notes');
        }
      }
    }
    return Clip(
      from: from,
      to: to,
      pattern: pattern,
      cutoff: _ramp(c['cutoff']),
      amp: c.containsKey('amp') ? _double(c, 'amp', 0, 2) : null,
      transpose: c.containsKey('transpose') ? _int(c, 'transpose', -48, 48) : 0,
    );
  }

  Ramp? _ramp(Object? raw) {
    if (raw == null) return null;
    if (raw is num) {
      final v = _asDouble(raw, 'cutoff', 0, 130);
      return Ramp(v, v);
    }
    final r = _map(raw, 'cutoff');
    return Ramp(_double(r, 'from', 0, 130), _double(r, 'to', 0, 130));
  }

  Voice _voice(Map<String, dynamic> v) {
    final name = _string(v, 'type');
    final type = VoiceType.values.where((t) => t.name == name).firstOrNull;
    if (type == null) throw SongFormatException('Unknown voice "$name"');
    double beats(String key) => v.containsKey(key) ? _double(v, key, 0, 64) : 0;
    double share(String key) => v.containsKey(key) ? _double(v, key, 0, 4) : 0;
    final drum = type == VoiceType.drum ? _string(v, 'drum') : null;
    if (drum != null && !_drums.contains(drum)) throw SongFormatException('Unknown drum "$drum"');
    return Voice(
      type: type,
      amp: v.containsKey('amp') ? _double(v, 'amp', 0, 2) : 1,
      attack: beats('attack'),
      sustain: beats('sustain'),
      release: beats('release'),
      attackOfNote: share('attackOfNote'),
      sustainOfNote: share('sustainOfNote'),
      releaseOfNote: share('releaseOfNote'),
      cutoff: v.containsKey('cutoff') ? _double(v, 'cutoff', 0, 130) : 100,
      detune: v.containsKey('detune') ? _double(v, 'detune', 0, 2) : 0,
      vibratoRate: v.containsKey('vibratoRate') ? _double(v, 'vibratoRate', 0, 20) : 0,
      vibratoDepth: v.containsKey('vibratoDepth') ? _double(v, 'vibratoDepth', 0, 2) : 0,
      duty: v.containsKey('duty') ? _double(v, 'duty', 0.05, 0.95) : 0.5,
      drum: drum,
      rate: v.containsKey('rate') ? _double(v, 'rate', 0.25, 4) : 1,
      drumCutoff: type == VoiceType.drum && v.containsKey('cutoff') ? _double(v, 'cutoff', 0, 130) : null,
      cutoffTo: v.containsKey('cutoffTo') ? _double(v, 'cutoffTo', 0, 130) : 100,
      slide: beats('slide'),
    );
  }

  // Readers. Each names what it wanted, for whoever is writing the file.

  static String _string(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is! String || v.isEmpty) throw SongFormatException('"$key" must be text');
    return v;
  }

  static String? _optionalString(Map<String, dynamic> m, String key) => m[key] == null ? null : _string(m, key);

  static String _asString(Object? v, String what) {
    if (v is! String) throw SongFormatException('$what must be text');
    return v;
  }

  static int _int(Map<String, dynamic> m, String key, int min, int max) {
    final v = m[key];
    if (v is! int || v < min || v > max) throw SongFormatException('"$key" must be a whole number, $min to $max');
    return v;
  }

  static double _double(Map<String, dynamic> m, String key, double min, double max) =>
      _asDouble(m[key], '"$key"', min, max);

  static double _asDouble(Object? v, String what, double min, double max) {
    if (v is! num || !v.isFinite || v < min || v > max) throw SongFormatException('$what must be $min to $max');
    return v.toDouble();
  }

  static List<Object?> _list(Map<String, dynamic> m, String key, {bool required = true}) {
    final v = m[key];
    if (v == null && !required) return const [];
    return _asList(v, '"$key"');
  }

  static List<Object?> _asList(Object? v, String what) {
    if (v is! List) throw SongFormatException('$what must be a list');
    return v;
  }

  static Map<String, dynamic> _map(Object? v, String what) {
    if (v is! Map<String, dynamic>) throw SongFormatException('$what must be an object');
    return v;
  }
}
