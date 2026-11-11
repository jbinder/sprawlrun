// Plays any [Song] as an endless stream, one bar per call. Nothing here knows
// about a particular song.

import 'dart:math';
import 'dart:typed_data';

import 'song.dart';
import 'synth/dsp.dart';
import 'synth/drums.dart';
import 'synth/effects.dart';
import 'synth/voices.dart';

class RenderedBar {
  RenderedBar(this.left, this.right);

  final Float32List left, right;

  double get seconds => left.length / sampleRate;
}

/// Notes are computed whole when their bar comes up, so a bus holds the bar being
/// produced and the tails running past it. [_window] has to outlast the longest
/// sound written in one go, and keeps memory flat however long a run lasts.
class SongStream {
  SongStream(this.song, {this.fromBar = 0, MusicLevel level = MusicLevel.normal})
    : _level = level,
      _nextLevel = level,
      _tempo = _tempoAt(song, level),
      _voices = Voices(Random(song.seed)),
      _riserNoise = Random(song.seed + 1) {
    for (final bus in song.buses) {
      _buses[bus.id] = _RunningBus.of(bus, song.secondsPerBeat);
    }
  }

  static final int _window = (10.5 * sampleRate).round();

  /// A level changes only where a phrase starts, or it would cut across one. Two
  /// bars, three seconds or so: four kept a runner waiting.
  static const int phraseBars = 2;

  final Song song;
  final int fromBar;
  final Voices _voices;
  final Random _riserNoise;
  final Map<String, _RunningBus> _buses = {};
  final Map<(String, double?), Float64List> _drumTables = {};
  final List<Riser> _risers = [];
  final Master _masterLeft = Master(), _masterRight = Master();

  int _bar = 0;
  MusicLevel _level, _nextLevel;
  bool _changeAtOnce = false;

  /// The share of the song's tempo now playing. It glides, a bar at a time, so a
  /// change of tempo reads as the song easing off and not as a jump.
  double _tempo;
  static const double _tempoStepPerBar = 0.02;

  /// Where this bar starts, in samples and in beats, kept apart from the bar
  /// number because a bar's length depends on the tempo it was played at.
  double _position = 0, _beats = 0;

  static double _tempoAt(Song song, MusicLevel level) => switch (level) {
    MusicLevel.low => song.lowTempo,
    MusicLevel.normal => 1.0,
    MusicLevel.high => song.highTempo,
  };

  /// The level of the bar made last.
  MusicLevel get level => _level;

  /// Plays [level] from the next phrase, or from the next bar with [atOnce].
  /// What has already been made keeps ringing, so a layer leaves on its own tail.
  void setLevel(MusicLevel level, {bool atOnce = false}) {
    _nextLevel = level;
    _changeAtOnce = atOnce;
  }

  /// The sample, since the stream began, that index 0 of every bus stands for.
  int _base = 0;

  /// The song's own bar for the [played]th bar this stream has produced.
  int _songBarAt(int played) => song.songBar(fromBar + played);

  /// How far through its bars the song has been made, from 0 to 1.
  double get position {
    if (_bar == 0) return song.songBar(fromBar) / song.bars;
    return (song.songBar(fromBar + _bar - 1) + 1) / song.bars;
  }

  /// Whether the song has played through to where it would go back and repeat.
  bool get firstPassDone => fromBar + _bar >= song.bars;

  /// One more bar with nothing new in it, fading away, so that what is still
  /// ringing ends rather than being cut off when another song takes over.
  RenderedBar ringOut() {
    final bar = nextBar(silent: true);
    final frames = bar.left.length;
    for (var i = 0; i < frames; i++) {
      final gain = 1 - i / frames;
      bar.left[i] *= gain;
      bar.right[i] *= gain;
    }
    return bar;
  }

  /// Produces the next bar, and leaves every tail in place for the one after.
  RenderedBar nextBar({bool silent = false}) {
    final b = _songBarAt(_bar);
    final changing = _changeAtOnce || b % phraseBars == 0;
    final snap = _changeAtOnce;
    if (changing) {
      _level = _nextLevel;
      _changeAtOnce = false;
    }
    final tempoTarget = _tempoAt(song, _level);
    // At once means back to the song's own tempo at the next bar; going faster
    // than that still glides, or the song would lurch just as a chase begins.
    _tempo = snap
        ? (tempoTarget > 1 ? max(_tempo, 1.0) : tempoTarget)
        : _tempo < tempoTarget
        ? min(tempoTarget, _tempo + _tempoStepPerBar)
        : max(tempoTarget, _tempo - _tempoStepPerBar);
    final spb = song.secondsPerBeat / _tempo;
    final samplesPerBeat = spb * sampleRate;
    final barStart = _position;
    _position += beatsPerBar * samplesPerBeat;
    final end = _position.round();
    final count = end - _base;

    for (final track in silent ? const <Track>[] : song.tracks) {
      if (track.level.index > _level.index) continue;
      final bus = _buses[track.bus]!;
      for (final clip in track.clips) {
        if (clip.playsAt(b)) _playClip(track.voice, clip, b, barStart, spb, bus);
      }
    }
    _risers.removeWhere((r) => !r.render(count));

    final left = Float32List(count), right = Float32List(count);
    for (final bus in _buses.values) {
      // A bar starts on a whole sample, up to half of one off where the beat falls.
      bus.mixInto(left, right, count, samplesPerBeat, _beats + (_base - barStart) / samplesPerBeat, b);
    }
    _masterLeft.process(left, count);
    _masterRight.process(right, count);

    for (final bus in _buses.values) {
      bus.advance(count);
    }
    _base = end;
    _beats += beatsPerBar;
    _bar++;
    return RenderedBar(left, right);
  }

  void _playClip(Voice voice, Clip clip, int b, double barStart, double spb, _RunningBus running) {
    final bus = running.samples;
    final progress = clip.progress(b);
    final cutoff = clip.cutoff?.at(progress) ?? voice.cutoff;
    for (final e in clip.pattern.at(b)) {
      final start = (barStart + e.beat * spb * sampleRate).round() - _base;
      final amp = (e.amp ?? clip.amp ?? voice.amp) / e.shareOf;
      if (voice.type == VoiceType.drum) {
        final table = _drum(voice);
        final rate = e.rate ?? voice.rate;
        _voices.hit(table, bus, start, amp: amp, rate: rate);
        running.reach(start + (table.length / rate).ceil() + 1);
        continue;
      }
      final note = (e.note! + clip.transpose).toDouble();
      final env = Envelope(
        (voice.attack + voice.attackOfNote * e.beats) * spb,
        (voice.sustain + voice.sustainOfNote * e.beats) * spb,
        (voice.release + voice.releaseOfNote * e.beats) * spb,
      );
      running.reach(start + env.length + 1);
      switch (voice.type) {
        case VoiceType.saw:
          _voices.saw(bus, start, note, env: env, cutoff: cutoff, amp: amp);
        case VoiceType.dsaw:
          _voices.dsaw(bus, start, note, env: env, cutoff: cutoff, detune: voice.detune, amp: amp);
        case VoiceType.prophet:
          _voices.prophet(bus, start, note, env: env, cutoff: cutoff, amp: amp);
        case VoiceType.blade:
          _voices.blade(
            bus,
            start,
            note,
            env: env,
            secondsPerBeat: spb,
            vibratoRate: voice.vibratoRate,
            vibratoDepth: voice.vibratoDepth,
            amp: amp,
          );
        case VoiceType.pulse:
          _voices.pulse(
            bus,
            start,
            note,
            env: env,
            duty: voice.duty,
            detune: voice.detune,
            vibratoRate: voice.vibratoRate,
            vibratoDepth: voice.vibratoDepth,
            amp: amp,
          );
        case VoiceType.triangle:
          _voices.triangle(bus, start, note, env: env, amp: amp);
        case VoiceType.sub:
          _voices.sub(bus, start, note, env: env, amp: amp);
        case VoiceType.riser:
          _risers.add(
            Riser(
              bus: bus,
              env: env,
              slideSeconds: voice.slide * spb,
              fromCutoff: voice.cutoff,
              toCutoff: voice.cutoffTo,
              amp: amp,
              noise: _riserNoise,
            ),
          );
        case VoiceType.drum:
          break;
      }
    }
  }

  Float64List _drum(Voice voice) {
    final name = voice.drum!;
    final cutoff = voice.drumCutoff;
    return _drumTables[(name, cutoff)] ??= () {
      final table = drumBuilders[name]!();
      return cutoff == null ? table : filteredDrum(table, cutoff);
    }();
  }
}

/// Songs one after another. Each plays once through, rings out and hands over,
/// back to the first after the last. Only ever one at a time, so the cost of the
/// music is the cost of a song. A single song simply repeats as it always has.
class SongSequence {
  SongSequence(this.songs, {MusicLevel level = MusicLevel.normal})
    : assert(songs.isNotEmpty),
      _level = level,
      _stream = SongStream(songs.first, level: level);

  final List<Song> songs;
  SongStream _stream;
  MusicLevel _level;
  int _index = 0;
  bool _rungOut = false;

  /// The song playing now.
  Song get current => songs[_index];

  int get currentIndex => _index;

  /// How far through the current song, from 0 to 1. One bar is a [barShare] of it.
  double get position => _rungOut ? 1 : _stream.position;

  double get barShare => 1 / current.bars;

  /// The level of the bar made last.
  MusicLevel get level => _stream.level;

  void setLevel(MusicLevel level, {bool atOnce = false}) {
    _level = level;
    _stream.setLevel(level, atOnce: atOnce);
  }

  RenderedBar nextBar() {
    if (songs.length > 1 && _stream.firstPassDone) {
      if (!_rungOut) {
        _rungOut = true;
        return _stream.ringOut();
      }
      _index = (_index + 1) % songs.length;
      _rungOut = false;
      _stream = SongStream(songs[_index], level: _level);
    }
    return _stream.nextBar();
  }
}

/// A bus and its effects, running for as long as the stream does.
class _RunningBus {
  _RunningBus(this.samples, this.slicer, this.drive, this.echo, this.reverb, this.spread);

  factory _RunningBus.of(Bus bus, double spb) {
    SlicerEffect? slicer;
    Drive? drive;
    Echo? echo;
    Reverb? reverb;
    Spread? spread;
    for (final effect in bus.effects) {
      switch (effect) {
        case SlicerEffect():
          slicer = effect;
        case SpreadEffect():
          spread = Spread(ms: effect.ms);
        case DriveEffect():
          drive = Drive(amount: effect.amount, mix: effect.mix, level: effect.level);
        case EchoEffect():
          echo = Echo(secondsPerBeat: spb, phaseBeats: effect.phase, decayBeats: effect.decay, mix: effect.mix);
        case ReverbEffect():
          reverb = Reverb(room: effect.room, damp: effect.damp, mix: effect.mix);
      }
    }
    return _RunningBus(Float32List(SongStream._window), slicer, drive, echo, reverb, spread);
  }

  final Float32List samples;

  /// Everything from here on is silence, so moving on a bar need not touch it.
  /// Shifting the whole ten-second window every bar was a real share of the cost.
  int _used = 0;

  /// Notes reach up to [end], not counting a reverb or echo tail, which lives in
  /// the effect and not here.
  void reach(int end) {
    if (end > _used) _used = min(end, samples.length);
  }

  /// Drops the bar just played and brings what rings past it to the front.
  void advance(int count) {
    // An echo writes into the bar itself, so that much is always cleared.
    final used = max(_used, min(count, samples.length));
    final keep = used - count;
    if (keep > 0) samples.setRange(0, keep, samples, count);
    samples.fillRange(max(keep, 0), used, 0);
    _used = max(keep, 0);
  }

  final SlicerEffect? slicer;
  final Drive? drive;
  final Echo? echo;
  final Reverb? reverb;
  final Spread? spread;

  void mixInto(Float32List l, Float32List r, int count, double samplesPerBeat, double beats, int songBar) {
    if (slicer != null) _slice(slicer!, count, samplesPerBeat, beats, songBar);
    drive?.process(samples, count);
    echo
      ?..setSamplesPerBeat(samplesPerBeat)
      ..process(samples, count);
    final spread = this.spread;
    if (spread == null) {
      _mix(l, r, count);
      return;
    }
    final ownLeft = Float32List(count), ownRight = Float32List(count);
    _mix(ownLeft, ownRight, count);
    spread.process(ownLeft, ownRight, count);
    for (var i = 0; i < count; i++) {
      l[i] += ownLeft[i];
      r[i] += ownRight[i];
    }
  }

  void _mix(Float32List l, Float32List r, int count) {
    if (reverb != null) {
      reverb!.process(samples, count, l, r);
      return;
    }
    for (var i = 0; i < count; i++) {
      final x = samples[i];
      l[i] += x;
      r[i] += x;
    }
  }

  void _slice(SlicerEffect effect, int count, double samplesPerBeat, double beats, int songBar) {
    final mix = effect.mixAt(songBar);
    final cosine = cos(mix * pi / 2), sine = sin(mix * pi / 2);
    for (var k = 0; k < count; k++) {
      final position = beats + k / samplesPerBeat;
      final slice = 1 - (position - position.floorToDouble());
      final s = samples[k];
      samples[k] = s * cosine + s * slice * sine;
    }
  }
}
