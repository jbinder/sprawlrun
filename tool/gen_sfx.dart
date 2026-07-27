// Synthesises every sound effect shipped in assets/sfx/.
//
// The app is fully offline and ships no licensed audio, so the whole SFX bed is
// generated from first principles here. Re-run after editing:
//
//     dart run tool/gen_sfx.dart
//
// Output: 16-bit mono 44.1 kHz WAV, which just_audio plays on every platform.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const int kSampleRate = 44100;

void main(List<String> args) {
  final outDir = Directory(args.isNotEmpty ? args.first : 'assets/sfx');
  outDir.createSync(recursive: true);

  final bank = <String, List<double>>{
    'ui_tap': uiTap(),
    'ui_back': uiBack(),
    'comm_open': commOpen(),
    'comm_close': commClose(),
    'objective': objective(),
    'alert': alert(),
    'chase_start': chaseStart(),
    'chase_clear': chaseClear(),
    'chase_failed': chaseFailed(),
    'glitch': glitch(),
    'unlock': unlock(),
    'goal_reached': goalReached(),
    'mission_success': missionSuccess(),
    'mission_fail': missionFail(),
    'heartbeat': heartbeat(),
    'drone': drone(),
  };

  bank.forEach((name, samples) {
    final file = File('${outDir.path}/$name.wav');
    file.writeAsBytesSync(encodeWav(normalise(samples, 0.89)));
    final seconds = (samples.length / kSampleRate).toStringAsFixed(2);
    stdout.writeln('  ${file.path.padRight(34)} ${seconds}s');
  });
  stdout.writeln('Generated ${bank.length} sounds.');
}

// ---------------------------------------------------------------------------
// Sound designs
// ---------------------------------------------------------------------------

/// Dry, short blip. Every button in the UI.
List<double> uiTap() {
  final buf = Buffer(0.06);
  buf.add(square(freq: 1180, duration: 0.035), env: perc(0.001, 0.035));
  buf.add(noise(0.012, seed: 7), env: perc(0.0005, 0.012), gain: 0.25);
  return buf.samples;
}

/// Descending sibling of [uiTap] for "back"/dismiss gestures.
List<double> uiBack() {
  final buf = Buffer(0.08);
  buf.add(sweepSquare(from: 900, to: 420, duration: 0.055), env: perc(0.001, 0.055));
  return buf.samples;
}

/// Squelch-open. Fires just before any voice line so the runner has a
/// half-second of warning that their music is about to drop out.
List<double> commOpen() {
  final buf = Buffer(0.32);
  buf.add(noise(0.05, seed: 11, lowpass: 0.35), env: perc(0.002, 0.05), gain: 0.5);
  buf.add(sweepSquare(from: 720, to: 1560, duration: 0.09), env: perc(0.003, 0.09), gain: 0.35, at: 0.03);
  buf.add(sine(freq: 1860, duration: 0.05), env: perc(0.002, 0.05), gain: 0.18, at: 0.13);
  buf.add(sine(freq: 2480, duration: 0.06), env: perc(0.002, 0.06), gain: 0.14, at: 0.18);
  return buf.samples;
}

/// Squelch-close. Signals "channel down, your music is coming back".
List<double> commClose() {
  final buf = Buffer(0.26);
  buf.add(sweepSquare(from: 1560, to: 480, duration: 0.1), env: perc(0.002, 0.1), gain: 0.3);
  buf.add(noise(0.08, seed: 23, lowpass: 0.25), env: perc(0.002, 0.08), gain: 0.35, at: 0.06);
  return buf.samples;
}

/// Bright three-note data chime — objective logged, intel acquired.
List<double> objective() {
  final buf = Buffer(0.5);
  const notes = [880.0, 1318.5, 1760.0];
  for (var i = 0; i < notes.length; i++) {
    buf.add(
      square(freq: notes[i], duration: 0.16, pulseWidth: 0.35),
      env: perc(0.004, 0.16),
      gain: 0.32,
      at: i * 0.075,
    );
    buf.add(sine(freq: notes[i] * 2, duration: 0.14), env: perc(0.004, 0.14), gain: 0.1, at: i * 0.075);
  }
  return buf.samples;
}

/// Two-pulse warning klaxon. Something is about to go wrong.
List<double> alert() {
  final buf = Buffer(0.85);
  for (var i = 0; i < 2; i++) {
    final at = i * 0.36;
    buf.add(square(freq: 622, duration: 0.24, pulseWidth: 0.5), env: adsr(0.01, 0.05, 0.7, 0.12, 0.24), gain: 0.3, at: at);
    buf.add(square(freq: 932, duration: 0.24, pulseWidth: 0.5), env: adsr(0.01, 0.05, 0.7, 0.12, 0.24), gain: 0.18, at: at);
  }
  return buf.samples;
}

/// Rising threat sting. Plays the instant a chase segment opens.
List<double> chaseStart() {
  final buf = Buffer(1.6);
  buf.add(sweepSaw(from: 110, to: 900, duration: 1.25), env: adsr(0.05, 0.2, 0.85, 0.3, 1.25), gain: 0.32);
  buf.add(sweepSaw(from: 111.6, to: 907, duration: 1.25), env: adsr(0.05, 0.2, 0.85, 0.3, 1.25), gain: 0.26);
  buf.add(sine(freq: 55, duration: 1.4), env: adsr(0.02, 0.4, 0.6, 0.5, 1.4), gain: 0.4);
  buf.add(noise(1.1, seed: 31, lowpass: 0.12), env: adsr(0.3, 0.4, 0.7, 0.3, 1.1), gain: 0.18, at: 0.2);
  buf.add(square(freq: 1244, duration: 0.12), env: perc(0.002, 0.12), gain: 0.22, at: 1.3);
  return buf.samples;
}

/// Warm falling resolve. You outran it.
List<double> chaseClear() {
  final buf = Buffer(1.3);
  const notes = [1174.7, 880.0, 587.3, 440.0];
  for (var i = 0; i < notes.length; i++) {
    buf.add(sine(freq: notes[i], duration: 0.6), env: perc(0.006, 0.6), gain: 0.3, at: i * 0.1);
    buf.add(sine(freq: notes[i] * 1.5, duration: 0.5), env: perc(0.006, 0.5), gain: 0.09, at: i * 0.1);
  }
  buf.add(sine(freq: 220, duration: 0.7), env: perc(0.02, 0.7), gain: 0.25, at: 0.4);
  return buf.samples;
}

/// Sour, detuned stab. They caught up with you.
List<double> chaseFailed() {
  final buf = Buffer(1.2);
  buf.add(sweepSaw(from: 320, to: 90, duration: 0.9), env: adsr(0.005, 0.2, 0.5, 0.4, 0.9), gain: 0.3);
  buf.add(sweepSaw(from: 331, to: 86, duration: 0.9), env: adsr(0.005, 0.2, 0.5, 0.4, 0.9), gain: 0.28);
  buf.add(noise(0.35, seed: 41, lowpass: 0.5), env: perc(0.002, 0.35), gain: 0.22);
  return buf.samples;
}

/// Bitcrushed noise tear. Used for interference, transitions, ICE contact.
List<double> glitch() {
  final buf = Buffer(0.55);
  final rnd = Random(97);
  var t = 0.0;
  while (t < 0.45) {
    final slice = 0.012 + rnd.nextDouble() * 0.05;
    if (rnd.nextDouble() > 0.32) {
      final crushed = bitcrush(noise(slice, seed: rnd.nextInt(9999), lowpass: 0.3 + rnd.nextDouble() * 0.6), 4);
      buf.add(crushed, env: perc(0.001, slice), gain: 0.2 + rnd.nextDouble() * 0.35, at: t);
      if (rnd.nextBool()) {
        buf.add(square(freq: 200 + rnd.nextDouble() * 2400, duration: slice), env: perc(0.001, slice), gain: 0.14, at: t);
      }
    }
    t += slice;
  }
  return buf.samples;
}

/// Achievement unlocked — ascending pentatonic bell.
List<double> unlock() {
  final buf = Buffer(1.5);
  const notes = [523.3, 659.3, 784.0, 1046.5, 1318.5];
  for (var i = 0; i < notes.length; i++) {
    final at = i * 0.085;
    buf.add(sine(freq: notes[i], duration: 1.0), env: perc(0.004, 1.0), gain: 0.26, at: at);
    buf.add(sine(freq: notes[i] * 2.01, duration: 0.6), env: perc(0.004, 0.6), gain: 0.09, at: at);
    buf.add(sine(freq: notes[i] * 3.02, duration: 0.35), env: perc(0.004, 0.35), gain: 0.04, at: at);
  }
  return buf.samples;
}

/// The moment the run target is met — short, bright, unmistakable.
List<double> goalReached() {
  final buf = Buffer(1.0);
  const notes = [659.3, 880.0, 1318.5];
  for (var i = 0; i < notes.length; i++) {
    buf.add(square(freq: notes[i], duration: 0.5, pulseWidth: 0.4), env: perc(0.004, 0.5), gain: 0.24, at: i * 0.09);
    buf.add(sine(freq: notes[i], duration: 0.7), env: perc(0.004, 0.7), gain: 0.2, at: i * 0.09);
  }
  return buf.samples;
}

/// Mission complete fanfare — major-ish, synthetic, triumphant but cold.
List<double> missionSuccess() {
  final buf = Buffer(2.4);
  const chord = [
    [261.6, 0.0],
    [392.0, 0.11],
    [523.3, 0.22],
    [659.3, 0.33],
    [784.0, 0.44],
    [1046.5, 0.55],
  ];
  for (final entry in chord) {
    final f = entry[0];
    final at = entry[1];
    buf.add(saw(freq: f, duration: 1.6), env: adsr(0.01, 0.25, 0.45, 0.9, 1.6), gain: 0.15, at: at);
    buf.add(sine(freq: f, duration: 1.7), env: adsr(0.01, 0.3, 0.5, 1.0, 1.7), gain: 0.17, at: at);
  }
  buf.add(sine(freq: 130.8, duration: 2.0), env: adsr(0.01, 0.4, 0.5, 1.2, 2.0), gain: 0.3);
  buf.add(noise(0.25, seed: 5, lowpass: 0.9), env: perc(0.002, 0.25), gain: 0.12);
  return buf.samples;
}

/// Mission failed — the lights going out.
List<double> missionFail() {
  final buf = Buffer(2.2);
  buf.add(sweepSaw(from: 220, to: 55, duration: 1.8), env: adsr(0.02, 0.3, 0.6, 0.8, 1.8), gain: 0.26);
  buf.add(sweepSaw(from: 226, to: 52, duration: 1.8), env: adsr(0.02, 0.3, 0.6, 0.8, 1.8), gain: 0.24);
  buf.add(sine(freq: 61.7, duration: 2.0), env: adsr(0.05, 0.5, 0.5, 1.0, 2.0), gain: 0.3, at: 0.15);
  buf.add(noise(0.6, seed: 61, lowpass: 0.15), env: perc(0.05, 0.6), gain: 0.15, at: 0.05);
  return buf.samples;
}

/// Double thump. Layered under high-pressure moments.
List<double> heartbeat() {
  final buf = Buffer(1.1);
  for (final at in [0.0, 0.3]) {
    buf.add(sweepSine(from: 88, to: 42, duration: 0.22), env: perc(0.004, 0.22), gain: at == 0.0 ? 0.55 : 0.42, at: at);
  }
  return buf.samples;
}

/// Six-second loopable ambient bed: detuned sub-saws plus filtered wind.
/// Played at low volume under the run HUD when the runner has no music of
/// their own.
List<double> drone() {
  const dur = 6.0;
  final buf = Buffer(dur);
  for (final f in [55.0, 55.4, 82.5, 110.3]) {
    buf.add(saw(freq: f, duration: dur), env: adsr(1.2, 0.5, 0.9, 1.5, dur), gain: 0.09);
  }
  buf.add(noise(dur, seed: 77, lowpass: 0.05), env: adsr(1.5, 0.5, 0.9, 1.5, dur), gain: 0.12);
  // Slow pulsing overtone so the bed never sits completely still.
  final pulse = List<double>.generate(_n(dur), (i) {
    final t = i / kSampleRate;
    final lfo = 0.5 + 0.5 * sin(2 * pi * 0.13 * t);
    return sin(2 * pi * 330 * t) * lfo * 0.035;
  });
  buf.add(pulse, env: adsr(1.5, 0.5, 0.9, 1.5, dur), gain: 1.0);
  return buf.samples;
}

// ---------------------------------------------------------------------------
// Tiny synthesis kit
// ---------------------------------------------------------------------------

int _n(double seconds) => (seconds * kSampleRate).round();

/// Fixed-length mix bus. [add] lays a voice down at an offset with an envelope.
class Buffer {
  Buffer(double seconds) : samples = List<double>.filled(_n(seconds), 0.0);

  final List<double> samples;

  void add(List<double> voice, {List<double>? env, double gain = 1.0, double at = 0.0}) {
    final offset = _n(at);
    for (var i = 0; i < voice.length; i++) {
      final target = offset + i;
      if (target >= samples.length) break;
      final e = env == null ? 1.0 : (i < env.length ? env[i] : 0.0);
      samples[target] += voice[i] * e * gain;
    }
  }
}

List<double> sine({required double freq, required double duration}) =>
    List<double>.generate(_n(duration), (i) => sin(2 * pi * freq * i / kSampleRate));

List<double> saw({required double freq, required double duration}) => List<double>.generate(_n(duration), (i) {
  final phase = (freq * i / kSampleRate) % 1.0;
  return 2 * phase - 1;
});

List<double> square({required double freq, required double duration, double pulseWidth = 0.5}) =>
    List<double>.generate(_n(duration), (i) {
      final phase = (freq * i / kSampleRate) % 1.0;
      return phase < pulseWidth ? 1.0 : -1.0;
    });

/// Exponential frequency glide, which reads as more musical than a linear one.
double _glide(double from, double to, double p) => from * pow(to / from, p).toDouble();

List<double> sweepSine({required double from, required double to, required double duration}) =>
    _sweep(from, to, duration, (ph) => sin(2 * pi * ph));

List<double> sweepSaw({required double from, required double to, required double duration}) =>
    _sweep(from, to, duration, (ph) => 2 * (ph % 1.0) - 1);

List<double> sweepSquare({required double from, required double to, required double duration}) =>
    _sweep(from, to, duration, (ph) => (ph % 1.0) < 0.5 ? 1.0 : -1.0);

/// Integrates the glide into a continuous phase so sweeps never click.
List<double> _sweep(double from, double to, double duration, double Function(double phase) shape) {
  final n = _n(duration);
  final out = List<double>.filled(n, 0.0);
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    phase += _glide(from, to, i / n) / kSampleRate;
    out[i] = shape(phase);
  }
  return out;
}

/// White noise run through a one-pole lowpass. [lowpass] 1.0 is unfiltered.
List<double> noise(double duration, {int seed = 0, double lowpass = 1.0}) {
  final rnd = Random(seed);
  final n = _n(duration);
  final out = List<double>.filled(n, 0.0);
  var last = 0.0;
  for (var i = 0; i < n; i++) {
    final white = rnd.nextDouble() * 2 - 1;
    last += (white - last) * lowpass.clamp(0.001, 1.0);
    out[i] = last;
  }
  return out;
}

/// Quantises amplitude to [bits] — the classic "damaged data" texture.
List<double> bitcrush(List<double> input, int bits) {
  final levels = pow(2, bits).toDouble();
  return input.map((s) => (s * levels).roundToDouble() / levels).toList();
}

/// Percussive envelope: fast attack, exponential decay.
List<double> perc(double attack, double duration) {
  final n = _n(duration);
  final a = max(1, _n(attack));
  return List<double>.generate(n, (i) {
    if (i < a) return i / a;
    final p = (i - a) / max(1, n - a);
    return exp(-5.0 * p) * (1 - p);
  });
}

List<double> adsr(double attack, double decay, double sustain, double release, double duration) {
  final n = _n(duration);
  final a = _n(attack);
  final d = _n(decay);
  final r = _n(release);
  return List<double>.generate(n, (i) {
    if (i < a) return a == 0 ? 1.0 : i / a;
    if (i < a + d) return d == 0 ? sustain : 1.0 - (1.0 - sustain) * ((i - a) / d);
    final releaseStart = n - r;
    if (i >= releaseStart && r > 0) return sustain * (1.0 - (i - releaseStart) / r);
    return sustain;
  });
}

/// Scales to [peak] and soft-clips, so nothing ever hits digital full scale.
List<double> normalise(List<double> samples, double peak) {
  var maxAbs = 0.0;
  for (final s in samples) {
    maxAbs = max(maxAbs, s.abs());
  }
  if (maxAbs == 0) return samples;
  final scale = peak / maxAbs;
  return samples.map((s) {
    final v = s * scale;
    return (v - (v * v * v) / 3).clamp(-1.0, 1.0).toDouble();
  }).toList();
}

/// 16-bit mono PCM RIFF/WAVE.
Uint8List encodeWav(List<double> samples) {
  const bitsPerSample = 16;
  const channels = 1;
  final dataBytes = samples.length * 2;
  final out = BytesBuilder();

  void ascii(String s) => out.add(s.codeUnits);
  void u32(int v) => out.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void u16(int v) => out.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));

  ascii('RIFF');
  u32(36 + dataBytes);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1); // PCM
  u16(channels);
  u32(kSampleRate);
  u32(kSampleRate * channels * bitsPerSample ~/ 8); // byte rate
  u16(channels * bitsPerSample ~/ 8); // block align
  u16(bitsPerSample);
  ascii('data');
  u32(dataBytes);

  final pcm = Uint8List(dataBytes);
  final view = pcm.buffer.asByteData();
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  out.add(pcm);
  return out.toBytes();
}
