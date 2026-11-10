// The arithmetic every voice and effect is made of, on SuperCollider's
// coefficient formulas. No dart:io and no Flutter, so it runs in an isolate on
// a phone and from `dart run` in tool/gen_music.dart alike.
//
// The DSP follows Sonic Pi's own definitions, including what shapes the sound
// without looking as if it would. See docs/SONGS.md.

import 'dart:math';

const int sampleRate = 44100;

/// What every layer loses to `Pan2` at centre.
const double centre = sqrt1_2;

const int normalizerWindow = 441; // 10 ms, for Normalizer and Limiter alike.

double midiHz(double note) => 440 * pow(2, (note - 69) / 12).toDouble();

/// A second-order filter. Its factories are SuperCollider's LPF, HPF, BPF and RLPF.
class Biquad {
  Biquad(this.a0, this.a1, this.a2, this.b1, this.b2);

  factory Biquad.lpf(double hz) {
    final c = 1 / tan(pi * hz / sampleRate);
    final a0 = 1 / (1 + sqrt2 * c + c * c);
    return Biquad(
      a0,
      2 * a0,
      a0,
      -2 * a0 * (1 - c * c),
      -a0 * (1 - sqrt2 * c + c * c),
    );
  }

  factory Biquad.hpf(double hz) {
    final c = tan(pi * hz / sampleRate);
    final a0 = 1 / (1 + sqrt2 * c + c * c);
    return Biquad(
      a0,
      -2 * a0,
      a0,
      -2 * a0 * (c * c - 1),
      -a0 * (1 - sqrt2 * c + c * c),
    );
  }

  factory Biquad.bpf(double hz, double rq) {
    final w = 2 * pi * hz / sampleRate;
    final c = 1 / tan(rq * w * 0.5);
    final a0 = 1 / (1 + c);
    return Biquad(a0, 0, -a0, c * 2 * cos(w) * a0, (1 - c) * a0);
  }

  factory Biquad.rlpf(double hz, double rq) =>
      Biquad(0, 0, 0, 0, 0)..setRlpf(hz, rq);

  double a0, a1, a2, b1, b2;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  /// For a filter whose cutoff moves, without losing its state.
  void setRlpf(double hz, double rq) {
    final w = 2 * pi * hz / sampleRate;
    final d = tan(w * rq * 0.5);
    final c = (1 - d) / (1 + d);
    b1 = (1 + c) * cos(w);
    b2 = -c;
    a0 = (1 + c - b1) * 0.25;
    a1 = 2 * a0;
    a2 = a0;
  }

  double tick(double x) {
    final y = a0 * x + a1 * _x1 + a2 * _x2 + b1 * _y1 + b2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }
}

/// Band-limits a phase-wrap discontinuity. [t] is phase in 0..1.
double blep(double t, double dt) {
  if (t < dt) {
    final x = t / dt;
    return x + x - x * x - 1;
  }
  if (t > 1 - dt) {
    final x = (t - 1) / dt;
    return x * x + x + x + 1;
  }
  return 0;
}

/// `Normalizer.ar`. Reads [x] and writes [out], each [length] long, 20 ms late.
void lookahead(List<double> x, List<double> out, int length) {
  const w = normalizerWindow;
  const level = 1.0;
  var gain = 1.0, slope = 0.0, previous = 0.0;
  for (var start = 0; start < length; start += w) {
    final end = min(start + w, length);
    final from = start - 2 * w;
    for (var i = start; i < end; i++) {
      out[i] = from < 0 ? 0.0 : x[i - 2 * w] * gain;
      gain += slope;
    }
    var peak = 0.0;
    for (var i = start; i < end; i++) {
      final v = x[i].abs();
      if (v > peak) peak = v;
    }
    final seen = max(previous, peak);
    previous = peak;
    slope = ((seen <= 0.00001 ? 100000 * level : level / seen) - gain) / w;
  }
}

/// Linear attack, sustain, release, in samples.
class Envelope {
  Envelope(double attack, double sustain, double release)
    : _a = attack * sampleRate,
      _s = sustain * sampleRate,
      _r = release * sampleRate;

  final double _a, _s, _r;

  int get length => (_a + _s + _r).ceil();

  double at(int i) {
    if (i < _a) return i / _a;
    final past = i - _a - _s;
    if (past <= 0) return 1;
    return past >= _r ? 0 : 1 - past / _r;
  }
}
