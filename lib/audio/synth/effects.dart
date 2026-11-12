// The effects a song's buses can use. Each is one instance per bus, kept
// running between bars so its tail carries over.

import 'dart:math';
import 'dart:typed_data';

import 'dsp.dart';

/// Widens a bus by holding one channel back a few milliseconds, which the ear
/// hears as width and not as an echo. Two buses spread opposite ways make a wall.
///
/// Only what is above [crossoverHz] moves. Bass stays in the centre, or a phone
/// speaker summing the two sides would cancel part of it.
class Spread {
  Spread({required double ms}) : _delayRight = ms > 0, _line = Float32List(max(1, (ms.abs() / 1000 * sampleRate).round()));

  static const double crossoverHz = 180;
  static final double _smoothing = 1 - exp(-2 * pi * crossoverHz / sampleRate);

  final bool _delayRight;
  final Float32List _line;
  int _at = 0;
  double _low = 0;

  void process(Float32List left, Float32List right, int count) {
    final held = _delayRight ? right : left;
    for (var i = 0; i < count; i++) {
      final x = held[i];
      _low += (x - _low) * _smoothing;
      held[i] = _low + _line[_at];
      _line[_at] = x - _low;
      if (++_at == _line.length) _at = 0;
    }
  }
}

/// Overdrive, as a soft limit that gets harder with [amount] and leaves a full
/// signal about where it found it. Keeps no state, so it can't ring on.
class Drive {
  Drive({required this.amount, required this.mix, this.level = 1}) : _makeUp = 1 / _limit(amount);

  final double amount, mix, level;
  final double _makeUp;

  /// A rational stand-in for tanh, close from 0 to 3 and flat beyond.
  static double _limit(double x) {
    if (x >= 3) return 1;
    if (x <= -3) return -1;
    final square = x * x;
    return x * (27 + square) / (27 + 9 * square);
  }

  void process(Float32List bus, int count) {
    for (var i = 0; i < count; i++) {
      final x = bus[i];
      bus[i] = (x * (1 - mix) + _limit(x * amount) * _makeUp * mix) * level;
    }
  }
}

/// `CombN`: delayed output only, the decay given as a 60 dB time.
class Echo {
  Echo({
    required double secondsPerBeat,
    required double phaseBeats,
    required double decayBeats,
    required double mix,
  }) : _phaseBeats = phaseBeats,
       _delay = (phaseBeats * secondsPerBeat * sampleRate).round(),
       _target = (phaseBeats * secondsPerBeat * sampleRate).round(),
       _line = Float64List((phaseBeats * secondsPerBeat * sampleRate / slowestTempo).ceil() + 2),
       _feedback = pow(0.001, phaseBeats / decayBeats).toDouble(),
       _dry = cos(mix * pi / 2),
       _wet = sin(mix * pi / 2);

  /// As slow as a song may play, which sets how long the line has to be.
  static const double slowestTempo = 0.88;

  /// How many samples pass between each single-sample move of the delay, so the
  /// echo drifts onto a new tempo rather than jumping and clicking.
  static const int _samplesPerMove = 64;

  final double _phaseBeats;
  final Float64List _line;
  final double _feedback, _dry, _wet;
  int _delay, _target;
  int _at = 0, _untilMove = 0;

  /// Keeps the echo on the beat when the tempo changes.
  void setSamplesPerBeat(double samplesPerBeat) => _target = (_phaseBeats * samplesPerBeat).round();

  /// Replaces the first [count] samples of [bus] with their echoed selves.
  void process(Float32List bus, int count) {
    final line = _line;
    for (var i = 0; i < count; i++) {
      if (_delay != _target && --_untilMove <= 0) {
        _delay += _delay < _target ? 1 : -1;
        _untilMove = _samplesPerMove;
      }
      final x = bus[i];
      var from = _at - _delay;
      if (from < 0) from += line.length;
      final delayed = line[from];
      line[_at] = x + delayed * _feedback;
      if (++_at == line.length) _at = 0;
      bus[i] = x * _dry + (x + delayed) * _wet;
    }
  }
}

/// A damped comb: a delay line fed back through a one-pole low-pass.
class _Comb {
  _Comb(int size, this.feedback, this.damp) : line = Float64List(size);

  final Float64List line;
  final double feedback, damp;
  int at = 0;
  double state = 0;
}

/// Adds four combs' output for each of the first [count] of [input] to [out], in
/// the order given. A bar in one loop, four combs to a pass and their state in
/// locals, is what makes a reverb affordable on a phone. The sum is taken in the
/// same order as one comb and one sample at a time, so the sound is unchanged.
void _addCombs(_Comb a, _Comb b, _Comb c, _Comb d, Float64List input, Float64List out, int count) {
  final la = a.line, lb = b.line, lc = c.line, ld = d.line;
  final na = la.length, nb = lb.length, nc = lc.length, nd = ld.length;
  final fa = a.feedback, fb = b.feedback, fc = c.feedback, fd = d.feedback;
  final da = a.damp, db = b.damp, dc = c.damp, dd = d.damp;
  var ia = a.at, ib = b.at, ic = c.at, id = d.at;
  var sa = a.state, sb = b.state, sc = c.state, sd = d.state;
  for (var i = 0; i < count; i++) {
    final x = input[i];
    final ya = la[ia];
    sa = ya * (1 - da) + sa * da;
    la[ia] = x + sa * fa;
    if (++ia == na) ia = 0;
    final yb = lb[ib];
    sb = yb * (1 - db) + sb * db;
    lb[ib] = x + sb * fb;
    if (++ib == nb) ib = 0;
    final yc = lc[ic];
    sc = yc * (1 - dc) + sc * dc;
    lc[ic] = x + sc * fc;
    if (++ic == nc) ic = 0;
    final yd = ld[id];
    sd = yd * (1 - dd) + sd * dd;
    ld[id] = x + sd * fd;
    if (++id == nd) id = 0;
    out[i] = out[i] + ya + yb + yc + yd;
  }
  a
    ..at = ia
    ..state = sa;
  b
    ..at = ib
    ..state = sb;
  c
    ..at = ic
    ..state = sc;
  d
    ..at = id
    ..state = sd;
}

class _Allpass {
  _Allpass(int size) : line = Float64List(size);

  final Float64List line;
  int _at = 0;

  /// Passes the first [count] of [signal] through, in place.
  void process(Float64List signal, int count) {
    final line = this.line, size = line.length;
    var at = _at;
    for (var i = 0; i < count; i++) {
      final x = signal[i];
      final y = line[at];
      line[at] = x + y * 0.5;
      if (++at == size) at = 0;
      signal[i] = y - x;
    }
    _at = at;
  }
}

/// `FreeVerb2` inside Sonic Pi's reverb, which crossfades by [mix] twice: once
/// in the reverb and once in the effect wrapped around it.
class Reverb {
  Reverb({required double room, required double damp, required this.mix})
    : _outerDry = cos(mix * pi / 2),
      _outerWet = sin(mix * pi / 2) {
    final feedback = 0.7 + 0.28 * room;
    final dampen = 0.4 * damp;
    for (final c in _combs) {
      _leftCombs.add(_Comb(c, feedback, dampen));
      _rightCombs.add(_Comb(c + _spread, feedback, dampen));
    }
    for (final a in _allpasses) {
      _leftPass.add(_Allpass(a));
      _rightPass.add(_Allpass(a + _spread));
    }
  }

  static const _combs = [1557, 1617, 1491, 1422, 1277, 1356, 1188, 1116];
  static const _allpasses = [556, 441, 341, 225];
  static const _spread = 23;

  final double mix, _outerDry, _outerWet;
  final List<_Comb> _leftCombs = [], _rightCombs = [];
  final List<_Allpass> _leftPass = [], _rightPass = [];
  Float64List _input = Float64List(0), _wetL = Float64List(0), _wetR = Float64List(0);

  /// Whether every line is empty, so silence in gives exactly silence out.
  bool _empty = true;

  /// A tail below this is a hundred decibels under the quietest step a 16-bit
  /// sample can take, so it is let go rather than worked out to the end.
  static const double _inaudible = 1e-9;

  /// Adds the first [count] samples of [bus], reverberated, to [l] and [r].
  ///
  /// A bus is often silent for bars at a time, a layer the level leaves out most
  /// of all, and a reverb running on nothing was a real share of a song's cost.
  void process(Float32List bus, int count, Float32List l, Float32List r) {
    if (_silent(bus, count)) {
      if (_empty) return;
      if (_tailGone()) {
        _clear();
        return;
      }
    } else {
      _empty = false;
    }
    if (_input.length < count) {
      _input = Float64List(count);
      _wetL = Float64List(count);
      _wetR = Float64List(count);
    }
    final input = _input, wetL = _wetL, wetR = _wetR;
    for (var i = 0; i < count; i++) {
      final x = bus[i];
      input[i] = 0.015 * (x + x);
    }
    wetL.fillRange(0, count, 0);
    wetR.fillRange(0, count, 0);
    final cl = _leftCombs, cr = _rightCombs;
    _addCombs(cl[0], cl[1], cl[2], cl[3], input, wetL, count);
    _addCombs(cl[4], cl[5], cl[6], cl[7], input, wetL, count);
    _addCombs(cr[0], cr[1], cr[2], cr[3], input, wetR, count);
    _addCombs(cr[4], cr[5], cr[6], cr[7], input, wetR, count);
    for (var a = 0; a < _allpasses.length; a++) {
      _leftPass[a].process(wetL, count);
      _rightPass[a].process(wetR, count);
    }
    final mix = this.mix, dry = _outerDry, wet = _outerWet;
    for (var i = 0; i < count; i++) {
      final x = bus[i];
      final direct = (1 - mix) * x;
      l[i] += x * dry + (direct + mix * wetL[i]) * wet;
      r[i] += x * dry + (direct + mix * wetR[i]) * wet;
    }
  }

  static bool _silent(Float32List bus, int count) {
    for (var i = 0; i < count; i++) {
      if (bus[i] != 0) return false;
    }
    return true;
  }

  bool _tailGone() {
    for (final comb in [..._leftCombs, ..._rightCombs]) {
      if (comb.state.abs() >= _inaudible || !_quiet(comb.line)) return false;
    }
    for (final pass in [..._leftPass, ..._rightPass]) {
      if (!_quiet(pass.line)) return false;
    }
    return true;
  }

  static bool _quiet(Float64List line) {
    for (var i = 0; i < line.length; i++) {
      if (line[i].abs() >= _inaudible) return false;
    }
    return true;
  }

  void _clear() {
    for (final comb in [..._leftCombs, ..._rightCombs]) {
      comb.line.fillRange(0, comb.line.length, 0);
      comb.state = 0;
    }
    for (final pass in [..._leftPass, ..._rightPass]) {
      pass.line.fillRange(0, pass.line.length, 0);
    }
    _empty = true;
  }
}

/// Sonic Pi's mixer for one channel: a 29 Hz high-pass, `Limiter.ar`, then
/// LeakDC and a clip. The limiter is `lookahead`'s, kept running between calls.
class Master {
  final Biquad _highPass = Biquad.hpf(midiHz(22));
  final Float64List _delay = Float64List(2 * normalizerWindow);
  int _at = 0, _inWindow = 0;
  double _gain = 1, _slope = 0, _previous = 0, _peak = 0;
  double _xPrevious = 0, _yPrevious = 0;

  void process(Float32List channel, int count) {
    const level = 0.99;
    final delay = _delay;
    for (var i = 0; i < count; i++) {
      final x = _highPass.tick(channel[i]);
      final limited = delay[_at] * _gain;
      _gain += _slope;
      delay[_at] = x;
      if (++_at == delay.length) _at = 0;
      final v = x.abs();
      if (v > _peak) _peak = v;
      if (++_inWindow == normalizerWindow) {
        final seen = max(_previous, _peak);
        _previous = _peak;
        _peak = 0;
        _inWindow = 0;
        _slope =
            ((seen > level ? level / seen : 1.0) - _gain) / normalizerWindow;
      }
      _yPrevious = limited - _xPrevious + 0.995 * _yPrevious;
      _xPrevious = limited;
      channel[i] = _yPrevious.clamp(-1.0, 1.0);
    }
  }
}

/// What a level does to the whole mix, so the three can be told apart where no
/// melody comes or goes: easing off closes a low-pass, so the song sounds further
/// away, and lifting adds air above [airHz] and a wider stereo image. At 0 it does
/// nothing at all, so a song at its own level is exactly as written.
///
/// [target] runs from -1, fully eased off, through 0 to 1, fully lifted, and the
/// sound glides there over [glideSeconds] rather than jumping.
class LevelTone {
  LevelTone(double amount) : _amount = amount, target = amount;

  /// Where the low-pass ends up when fully eased off.
  static const double closedHz = 1500;

  /// Where it starts closing from: above anything a song holds.
  static const double openHz = 20000;

  static const double airHz = 5000, airGain = 0.5, widthGain = 0.35;
  static const double glideSeconds = 1.5;

  static const int _block = 64;
  static final double _stepPerBlock = _block / (glideSeconds * sampleRate);

  double target;
  double _amount;
  final Biquad _lowLeft = Biquad.lpf(openHz), _lowRight = Biquad.lpf(openHz);
  final Biquad _airLeft = Biquad.hpf(airHz), _airRight = Biquad.hpf(airHz);

  void process(Float32List left, Float32List right, int count) {
    if (_amount == 0 && target == 0) return;
    for (var start = 0; start < count; start += _block) {
      final end = min(start + _block, count);
      _amount = _amount < target ? min(target, _amount + _stepPerBlock) : max(target, _amount - _stepPerBlock);
      if (_amount < 0) {
        final hz = openHz * pow(closedHz / openHz, -_amount);
        _airLeft.reset();
        _airRight.reset();
        _lowLeft.setLpf(hz);
        _lowRight.setLpf(hz);
        for (var i = start; i < end; i++) {
          left[i] = _lowLeft.tick(left[i]);
          right[i] = _lowRight.tick(right[i]);
        }
      } else if (_amount > 0) {
        _lowLeft.reset();
        _lowRight.reset();
        final air = airGain * _amount, width = 1 + widthGain * _amount;
        for (var i = start; i < end; i++) {
          final l = left[i] + air * _airLeft.tick(left[i]);
          final r = right[i] + air * _airRight.tick(right[i]);
          final mid = (l + r) / 2, side = (r - l) / 2 * width;
          left[i] = mid - side;
          right[i] = mid + side;
        }
      }
      if (_amount == 0 && target == 0) {
        // Back to the song as written: the filters start clean next time.
        for (final f in [_lowLeft, _lowRight, _airLeft, _airRight]) {
          f.reset();
        }
        return;
      }
    }
  }
}
