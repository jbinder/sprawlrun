// Drums: synthesised to fit measurements of the Sonic Pi samples' pitch, level,
// envelope and spectrum. No sample is read at any point. Each is built once per
// stream, when a song first uses it, and replayed like a sample.

import 'dart:math';
import 'dart:typed_data';

import 'dsp.dart';

/// The drums a song can name, and how to build each.
const Map<String, Float64List Function()> drumBuilders = {
  'kick': _kick,
  'snare': _snare,
  'dubSnare': _dubSnare,
  'hat': _hat,
  'splash': _splash,
  'boom': _boom,
};

/// [table], with its own copy run through a low-pass at MIDI note [cutoff], as
/// `sample` does with `cutoff:`.
Float64List filteredDrum(Float64List table, double cutoff) {
  final filter = Biquad.lpf(midiHz(cutoff));
  final out = Float64List(table.length);
  for (var i = 0; i < table.length; i++) {
    out[i] = filter.tick(table[i]);
  }
  return out;
}

Float64List _table(double seconds) =>
    Float64List((seconds * sampleRate).round());

/// :bd_tek. A sine from 355 Hz to 55 Hz, flat for 190 ms, then cut off, after
/// a 4 ms click. This fits the sample as it is on disk; a song's
/// `cutoff` is applied once, in [filteredDrum].
Float64List _kick() {
  final x = _table(0.24);
  final noise = Random(101);
  var phase = 0.0;
  const onset = 0.004;
  for (var i = 0; i < x.length; i++) {
    final t = i / sampleRate;
    if (t < onset) {
      x[i] += (noise.nextDouble() * 2 - 1) * 0.5;
      continue;
    }
    final b = t - onset;
    final hz = 55 + 300 * exp(-b / 0.012) + 70 * exp(-b / 0.06);
    phase += 2 * pi * hz / sampleRate;
    final fadeIn = min(1.0, b / 0.001);
    final fadeOut = t < 0.195 ? 1.0 : max(0.0, 1 - (t - 0.195) / 0.04);
    x[i] += sin(phase) * exp(-b * 4.7) * fadeIn * fadeOut;
  }
  return x;
}

/// :drum_snare_hard. A 200 Hz shell under noise with about equal energy in each
/// octave from 250 Hz up, as the sample has.
Float64List _snare() {
  final x = _table(0.44);
  final noise = Random(102);
  final tone = Biquad.hpf(300);
  final dark = Biquad.lpf(900);
  var phase = 0.0;
  for (var i = 0; i < x.length; i++) {
    final t = i / sampleRate;
    phase += 2 * pi * (172 + 45 * exp(-t / 0.03)) / sampleRate;
    final body = sin(phase) * exp(-t / 0.058);
    final n = noise.nextDouble() * 2 - 1;
    final hiss = tone.tick(2.2 * dark.tick(n) + 0.95 * n) * exp(-t / 0.07);
    x[i] = 0.84 * body + 0.72 * hiss;
  }
  return x;
}

/// :sn_dub. A 290 Hz body, with hiss that outlasts it.
Float64List _dubSnare() {
  final x = _table(0.278);
  final noise = Random(103);
  final tone = Biquad.bpf(6000, 1.4);
  var phase = 0.0;
  for (var i = 0; i < x.length; i++) {
    final t = i / sampleRate;
    phase += 2 * pi * (275 + 30 * exp(-t / 0.02)) / sampleRate;
    final body = sin(phase) * exp(-t / 0.09);
    final hiss = tone.tick(noise.nextDouble() * 2 - 1) * exp(-t / 0.11);
    final end = t < 0.23 ? 1.0 : (0.278 - t) / 0.048;
    x[i] = (0.56 * body + 0.56 * hiss) * end;
  }
  return x;
}

/// Six detuned squares, the classic drum-machine metal, for hat and cymbal.
double _metal(double t) {
  const partials = [2052.0, 3069.0, 4158.0, 5352.0, 6636.0, 8212.0];
  var sum = 0.0;
  for (final hz in partials) {
    sum += (t * hz) % 1 < 0.5 ? 1.0 : -1.0;
  }
  return sum / partials.length;
}

/// :drum_cymbal_closed.
Float64List _hat() {
  final x = _table(0.2);
  final noise = Random(104);
  final high = Biquad.hpf(6500);
  final top = Biquad.lpf(13000);
  final sheen = Biquad.hpf(1200);
  for (var i = 0; i < x.length; i++) {
    final t = i / sampleRate;
    final hiss = top.tick(high.tick(noise.nextDouble() * 2 - 1));
    final ring = sheen.tick(_metal(t));
    x[i] = (0.46 * hiss + 0.2 * ring) * exp(-t / 0.042);
  }
  return x;
}

/// :drum_splash_hard. Swells for 100 ms, then falls about 21 dB a second.
Float64List _splash() {
  final x = _table(2.6);
  final noise = Random(105);
  final body = Biquad.bpf(5200, 1.5);
  final air = Biquad.hpf(8000);
  final sheen = Biquad.hpf(1800);
  for (var i = 0; i < x.length; i++) {
    final t = i / sampleRate;
    final n = noise.nextDouble() * 2 - 1;
    final swell = t < 0.1 ? 0.55 + 0.45 * t / 0.1 : exp(-(t - 0.1) / 0.41);
    final sum = 0.75 * body.tick(n) + 0.24 * air.tick(n);
    x[i] = (sum + 0.1 * sheen.tick(_metal(t * 0.73))) * swell;
  }
  return x;
}

/// :misc_cineboom. Not a hit: mid noise swells for 1.5 s and hands over to a
/// 43 Hz rumble that holds until about 5 s, so it lands well after its bar.
Float64List _boom() {
  final x = _table(7.9);
  final noise = Random(106);
  final mid = Biquad.bpf(800, 1.5);
  final rumble = Biquad.lpf(90);
  var phase = 0.0;
  for (var i = 0; i < x.length; i++) {
    final t = i / sampleRate;
    final n = noise.nextDouble() * 2 - 1;
    phase += 2 * pi * 43 / sampleRate;
    final rise = t < 1.5 ? pow(10, -2.4 * (1.5 - t) / 1.5).toDouble() : 1.0;
    final swell = t < 1.5 ? rise : max(0.0, 1 - (t - 1.5) / 0.6);
    final fall = t < 5 ? 1.0 : pow(10, -2.2 * (t - 5) / 2.9).toDouble();
    final low = t < 1.2 ? 0.0 : min(1.0, (t - 1.2) / 0.6) * fall;
    x[i] =
        0.42 * swell * mid.tick(n) +
        low * (0.2 * sin(phase) + 0.9 * rumble.tick(n));
  }
  return x;
}
