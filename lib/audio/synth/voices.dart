// The synths a song can name. Each writes one whole note into a bus, or as much
// of it as fits. Times arrive in seconds, already scaled by the song's tempo.

import 'dart:math';
import 'dart:typed_data';

import 'dsp.dart';

/// Renders notes for one stream. Holds the scratch space they share and the
/// noise behind `:prophet`'s slow wander, so a seed always gives the same song.
class Voices {
  Voices(this._noise);

  final Random _noise;
  Float64List _raw = Float64List(0), _normal = Float64List(0);

  void _scratch(int size) {
    if (_raw.length < size) {
      _raw = Float64List(size);
      _normal = Float64List(size);
    }
  }

  /// Replays a drum table, resampled like `sample` with `rate:`.
  void hit(Float64List table, Float32List bus, int start, {required double amp, double rate = 1}) {
    final gain = amp * centre;
    final count = min(((table.length - 1) / rate).floor(), bus.length - start);
    for (var i = 0; i < count; i++) {
      final at = i * rate;
      final whole = at.floor();
      final part = at - whole;
      bus[start + i] += (table[whole] * (1 - part) + table[whole + 1] * part) * gain;
    }
  }

  /// `:saw`.
  void saw(
    Float32List bus,
    int start,
    double note, {
    required Envelope env,
    required double cutoff,
    required double amp,
  }) {
    final count = env.length;
    _scratch(count);
    final raw = _raw;
    final dt = midiHz(note) / sampleRate;
    final filter = Biquad.lpf(midiHz(cutoff));
    var phase = 0.0;
    for (var i = 0; i < count; i++) {
      final v = 2 * phase - 1 - blep(phase, dt);
      raw[i] = filter.tick(v);
      phase += dt;
      if (phase >= 1) phase -= 1;
    }
    lookahead(raw, _normal, count);
    _out(env, count, bus, start, 0.8 * amp * centre);
  }

  /// `:dsaw`.
  void dsaw(
    Float32List bus,
    int start,
    double note, {
    required Envelope env,
    required double cutoff,
    required double detune,
    required double amp,
  }) {
    final count = env.length;
    _scratch(count);
    final raw = _raw;
    final dt1 = midiHz(note) / sampleRate;
    final dt2 = midiHz(note + detune) / sampleRate;
    final filter = Biquad.lpf(midiHz(cutoff));
    var p1 = 0.0, p2 = 0.0;
    for (var i = 0; i < count; i++) {
      final v = 2 * p1 - 1 - blep(p1, dt1) + 2 * p2 - 1 - blep(p2, dt2);
      raw[i] = filter.tick(v);
      p1 += dt1;
      if (p1 >= 1) p1 -= 1;
      p2 += dt2;
      if (p2 >= 1) p2 -= 1;
    }
    lookahead(raw, _normal, count);
    _out(env, count, bus, start, 1.1 * amp * centre);
  }

  /// A square wave of a set width, as an early sound chip made. Unlike the Sonic
  /// Pi voices it has no normaliser in front of it, so it speaks on the beat, and
  /// any vibrato waits a moment, the way those tunes played it.
  void pulse(
    Float32List bus,
    int start,
    double note, {
    required Envelope env,
    required double duty,
    double detune = 0,
    required double vibratoRate,
    required double vibratoDepth,
    required double amp,
  }) {
    final count = env.length;
    final end = min(count, bus.length - start);
    final gain = 0.6 * amp * centre;
    final still = midiHz(note) / sampleRate;
    final swing = 2 * pi * vibratoRate / sampleRate;
    final delay = (0.18 * sampleRate).round();
    // A second wave a little off the first, for weight. Costs nothing when unused.
    final second = detune > 0 ? midiHz(note + detune) / sampleRate : 0.0;
    var phase = 0.0, phase2 = 0.0;
    for (var i = 0; i < end; i++) {
      final dt = vibratoDepth > 0 && i > delay ? midiHz(note + vibratoDepth * sin(swing * (i - delay))) / sampleRate : still;
      var fall = phase + 1 - duty;
      if (fall >= 1) fall -= 1;
      var v = (phase < duty ? 1.0 : -1.0) + blep(phase, dt) - blep(fall, dt);
      if (second > 0) {
        var fall2 = phase2 + 1 - duty;
        if (fall2 >= 1) fall2 -= 1;
        v += (phase2 < duty ? 1.0 : -1.0) + blep(phase2, second) - blep(fall2, second);
        phase2 += second;
        if (phase2 >= 1) phase2 -= 1;
      }
      bus[start + i] += v * env.at(i) * gain;
      phase += dt;
      if (phase >= 1) phase -= 1;
    }
  }

  /// A triangle in sixteen steps, which is where those chips' bass got its grain.
  void triangle(Float32List bus, int start, double note, {required Envelope env, required double amp}) {
    final count = env.length;
    final end = min(count, bus.length - start);
    final gain = 0.9 * amp * centre;
    final dt = midiHz(note) / sampleRate;
    var phase = 0.25;
    for (var i = 0; i < end; i++) {
      final smooth = 1 - 4 * (phase - 0.5).abs();
      final v = (smooth * 7.5).roundToDouble() / 7.5;
      bus[start + i] += v * env.at(i) * gain;
      phase += dt;
      if (phase >= 1) phase -= 1;
    }
  }

  /// A sine for the very bottom, with a touch of its octave so that small
  /// speakers and earphones still show it is there.
  void sub(Float32List bus, int start, double note, {required Envelope env, required double amp}) {
    final count = env.length;
    final end = min(count, bus.length - start);
    final gain = amp * centre;
    final step = 2 * pi * midiHz(note) / sampleRate;
    for (var i = 0; i < end; i++) {
      final phase = step * i;
      bus[start + i] += (sin(phase) + 0.15 * sin(2 * phase)) * env.at(i) * gain;
    }
  }

  void _out(Envelope env, int count, Float32List bus, int start, double gain) {
    final end = min(count, bus.length - start);
    final normal = _normal;
    for (var i = 0; i < end; i++) {
      bus[start + i] += normal[i] * env.at(i) * gain;
    }
  }

  /// `:prophet`: five width-modulated pulses, normalised, then the envelope
  /// twice around a squared signal in a resonant filter.
  void prophet(
    Float32List bus,
    int start,
    double note, {
    required Envelope env,
    required double cutoff,
    required double amp,
  }) {
    final count = env.length;
    _scratch(count);
    final raw = _raw;
    final dt = midiHz(note) / sampleRate;
    final p1 = Pulse(), p2 = Pulse(), p3 = Pulse(), p4 = Pulse();
    final low = Pulse();
    var lowLfo = 0.0, wander = 0.0, wanderTo = _noise.nextDouble() * 2 - 1;
    var wanderFrom = 0.0;
    var w1 = 0.0, w2 = 0.0, w3 = 0.0, w4 = 0.0, w5 = 0.0;
    const control = 32;
    for (var i = 0; i < count; i++) {
      if (i % control == 0) {
        final t = i / sampleRate;
        final held = t * 0.2;
        final part = held - held.floorToDouble();
        if (i > 0 && part < control / sampleRate * 0.2) {
          wanderFrom = wanderTo;
          wanderTo = _noise.nextDouble() * 2 - 1;
        }
        wander = wanderFrom + (wanderTo - wanderFrom) * part * part * (3 - 2 * part);
        lowLfo += (2 + wander) * control / sampleRate;
        w1 = 0.1 / (1.2 + sin(2 * pi * t));
        w2 = 0.8 * (1.2 + sin(2 * pi * 0.3 * t) + 0.7) / 2;
        w3 = 0.8 * (1.2 + _tri(0.4 * t)) / 2;
        w4 = 0.8 * (1.2 + _tri(0.4 * t + 0.19 / 4)) / 2;
        w5 = 0.8 * (1.2 + _tri(lowLfo)) / 2;
      }
      raw[i] = p1.tick(dt, w1) + p2.tick(dt, w2) + p3.tick(dt, w3) + p4.tick(dt, w4) + 0.5 * low.tick(dt / 2, w5);
    }
    lookahead(raw, _normal, count);
    final normal = _normal;
    final filter = Biquad.rlpf(midiHz(cutoff), 0.3);
    final end = min(count, bus.length - start);
    final gain = 1.5 * amp * centre;
    var xPrevious = 0.0, yPrevious = 0.0;
    for (var i = 0; i < end; i++) {
      final e = env.at(i);
      final v = normal[i];
      final y = filter.tick(e * v * v) * e;
      yPrevious = y - xPrevious + 0.995 * yPrevious; // LeakDC
      xPrevious = y;
      bus[start + i] += yPrevious * gain;
    }
  }

  /// LFTri from phase 0, for a position in cycles.
  double _tri(double cycles) {
    final p = (cycles - cycles.floorToDouble()) * 4;
    if (p < 1) return p;
    if (p < 3) return 2 - p;
    return p - 4;
  }

  /// `:blade`: a saw through three formants, with vibrato that waits half a
  /// beat. `vibratoRate` is in hertz, not scaled by the tempo.
  void blade(
    Float32List bus,
    int start,
    double note, {
    required Envelope env,
    required double secondsPerBeat,
    required double vibratoRate,
    required double vibratoDepth,
    required double amp,
  }) {
    final end = min(env.length, bus.length - start);
    final tone = Biquad.lpf(midiHz(100));
    final band1 = Biquad.bpf(300, 1 / 3.5);
    final band2 = Biquad.bpf(700, 1 / 3.5);
    final band3 = Biquad.bpf(3000, 0.5);
    final rumble = Biquad.hpf(30);
    final base = midiHz(note);
    final delay = 0.5 * secondsPerBeat, onset = 0.1 * secondsPerBeat;
    final gain = 1.1 * 1.1 * amp * centre;
    var phase = 0.0, dt = base / sampleRate;
    for (var i = 0; i < end; i++) {
      if (i % 16 == 0) {
        final t = i / sampleRate;
        final depth = t < delay ? 0.0 : vibratoDepth * min(1.0, (t - delay) / onset);
        final bend = depth * sin(2 * pi * vibratoRate * t);
        dt = base * pow(2, bend / 12) / sampleRate;
      }
      final v = tone.tick(2 * phase - 1 - blep(phase, dt));
      phase += dt;
      if (phase >= 1) phase -= 1;
      final y = rumble.tick(band1.tick(v) + band2.tick(v) + band3.tick(v));
      bus[start + i] += y * env.at(i) * gain;
    }
  }
}

/// White noise through a resonant filter whose cutoff slides, for a build. Far
/// longer than a bus, so unlike a note it is generated a bar at a time.
class Riser {
  Riser({
    required this.bus,
    required this.env,
    required double slideSeconds,
    required double fromCutoff,
    required double toCutoff,
    required double amp,
    required this.noise,
  }) : _slide = slideSeconds * sampleRate,
       _from = fromCutoff,
       _to = toCutoff,
       _gain = amp * centre,
       _filter = Biquad.rlpf(midiHz(fromCutoff), 1);

  final Float32List bus;
  final Envelope env;
  final Random noise;
  final double _slide, _from, _to, _gain;
  final Biquad _filter;
  int _at = 0;

  /// Writes the next [count] samples. False once it has finished.
  bool render(int count) {
    final total = env.length;
    for (var i = 0; i < count; i++) {
      final at = _at + i;
      if (at >= total) return false;
      if (at % 32 == 0) {
        _filter.setRlpf(midiHz(_from + (_to - _from) * min(1.0, at / _slide)), 1);
      }
      final x = _filter.tick(noise.nextDouble() * 2 - 1);
      bus[i] += x * env.at(at) * _gain;
    }
    _at += count;
    return true;
  }
}
