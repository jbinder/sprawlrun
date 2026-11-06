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
  SongStream(this.song, {this.fromBar = 0})
    : _spb = song.secondsPerBeat,
      _voices = Voices(Random(song.seed)),
      _riserNoise = Random(song.seed + 1) {
    for (final bus in song.buses) {
      _buses[bus.id] = _RunningBus.of(bus, _spb);
    }
  }

  static final int _window = (10.5 * sampleRate).round();

  final Song song;
  final int fromBar;
  final double _spb;
  final Voices _voices;
  final Random _riserNoise;
  final Map<String, _RunningBus> _buses = {};
  final Map<(String, double?), Float64List> _drumTables = {};
  final List<Riser> _risers = [];
  final Master _masterLeft = Master(), _masterRight = Master();

  int _bar = 0;

  /// The sample, since the stream began, that index 0 of every bus stands for.
  int _base = 0;

  /// The song's own bar for the [played]th bar this stream has produced.
  int _songBarAt(int played) => song.songBar(fromBar + played);

  /// Produces the next bar, and leaves every tail in place for the one after.
  RenderedBar nextBar() {
    final b = _songBarAt(_bar);
    final beat = _bar * beatsPerBar.toDouble();
    final end = ((_bar + 1) * beatsPerBar * _spb * sampleRate).round();
    final count = end - _base;

    for (final track in song.tracks) {
      final bus = _buses[track.bus]!.samples;
      for (final clip in track.clips) {
        if (clip.playsAt(b)) _playClip(track.voice, clip, b, beat, bus);
      }
    }
    _risers.removeWhere((r) => !r.render(count));

    final left = Float32List(count), right = Float32List(count);
    for (final bus in _buses.values) {
      bus.mixInto(left, right, count, _base, _spb, (bar) => _songBarAt(bar));
    }
    _masterLeft.process(left, count);
    _masterRight.process(right, count);

    for (final bus in _buses.values) {
      final samples = bus.samples;
      samples.setRange(0, _window - count, samples, count);
      samples.fillRange(_window - count, _window, 0);
    }
    _base = end;
    _bar++;
    return RenderedBar(left, right);
  }

  void _playClip(Voice voice, Clip clip, int b, double barBeat, Float32List bus) {
    final progress = clip.progress(b);
    final cutoff = clip.cutoff?.at(progress) ?? voice.cutoff;
    for (final e in clip.pattern.at(b)) {
      final start = ((barBeat + e.beat) * _spb * sampleRate).round() - _base;
      final amp = (e.amp ?? clip.amp ?? voice.amp) / e.shareOf;
      if (voice.type == VoiceType.drum) {
        _voices.hit(_drum(voice), bus, start, amp: amp, rate: e.rate ?? voice.rate);
        continue;
      }
      final note = (e.note! + clip.transpose).toDouble();
      final env = Envelope(
        (voice.attack + voice.attackOfNote * e.beats) * _spb,
        (voice.sustain + voice.sustainOfNote * e.beats) * _spb,
        (voice.release + voice.releaseOfNote * e.beats) * _spb,
      );
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
            secondsPerBeat: _spb,
            vibratoRate: voice.vibratoRate,
            vibratoDepth: voice.vibratoDepth,
            amp: amp,
          );
        case VoiceType.riser:
          _risers.add(
            Riser(
              bus: bus,
              env: env,
              slideSeconds: voice.slide * _spb,
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

/// A bus and its effects, running for as long as the stream does.
class _RunningBus {
  _RunningBus(this.samples, this.slicer, this.echo, this.reverb);

  factory _RunningBus.of(Bus bus, double spb) {
    SlicerEffect? slicer;
    Echo? echo;
    Reverb? reverb;
    for (final effect in bus.effects) {
      switch (effect) {
        case SlicerEffect():
          slicer = effect;
        case EchoEffect():
          echo = Echo(secondsPerBeat: spb, phaseBeats: effect.phase, decayBeats: effect.decay, mix: effect.mix);
        case ReverbEffect():
          reverb = Reverb(room: effect.room, damp: effect.damp, mix: effect.mix);
      }
    }
    return _RunningBus(Float32List(SongStream._window), slicer, echo, reverb);
  }

  final Float32List samples;
  final SlicerEffect? slicer;
  final Echo? echo;
  final Reverb? reverb;

  void mixInto(Float32List l, Float32List r, int count, int base, double spb, int Function(int) songBar) {
    if (slicer != null) _slice(slicer!, count, base, spb, songBar);
    echo?.process(samples, count);
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

  void _slice(SlicerEffect effect, int count, int base, double spb, int Function(int) songBar) {
    final perBeat = spb * sampleRate;
    final barSamples = perBeat * beatsPerBar;
    var barAt = -1;
    var cosine = 0.0, sine = 0.0;
    for (var k = 0; k < count; k++) {
      final i = base + k;
      final bar = i ~/ barSamples;
      if (bar != barAt) {
        barAt = bar;
        final mix = effect.mixAt(songBar(bar));
        cosine = cos(mix * pi / 2);
        sine = sin(mix * pi / 2);
      }
      final position = i / perBeat;
      final slice = 1 - (position - position.floorToDouble());
      final s = samples[k];
      samples[k] = s * cosine + s * slice * sine;
    }
  }
}
