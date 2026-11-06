// The effects a song's buses can use. Each is one instance per bus, kept
// running between bars so its tail carries over.

import 'dart:math';
import 'dart:typed_data';

import 'dsp.dart';

/// `CombN`: delayed output only, the decay given as a 60 dB time.
class Echo {
  Echo({
    required double secondsPerBeat,
    required double phaseBeats,
    required double decayBeats,
    required double mix,
  }) : _line = Float64List((phaseBeats * secondsPerBeat * sampleRate).round()),
       _feedback = pow(0.001, phaseBeats / decayBeats).toDouble(),
       _dry = cos(mix * pi / 2),
       _wet = sin(mix * pi / 2);

  final Float64List _line;
  final double _feedback, _dry, _wet;
  int _at = 0;

  /// Replaces the first [count] samples of [bus] with their echoed selves.
  void process(Float32List bus, int count) {
    final line = _line;
    for (var i = 0; i < count; i++) {
      final x = bus[i];
      final delayed = line[_at];
      line[_at] = x + delayed * _feedback;
      if (++_at == line.length) _at = 0;
      bus[i] = x * _dry + (x + delayed) * _wet;
    }
  }
}

class _Comb {
  _Comb(int size, this.feedback, this.damp) : _line = Float64List(size);

  final Float64List _line;
  final double feedback, damp;
  int _at = 0;
  double _state = 0;

  double tick(double x) {
    final y = _line[_at];
    _state = y * (1 - damp) + _state * damp;
    _line[_at] = x + _state * feedback;
    if (++_at == _line.length) _at = 0;
    return y;
  }
}

class _Allpass {
  _Allpass(int size) : _line = Float64List(size);

  final Float64List _line;
  int _at = 0;

  double tick(double x) {
    final y = _line[_at];
    _line[_at] = x + y * 0.5;
    if (++_at == _line.length) _at = 0;
    return y - x;
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

  /// Adds the first [count] samples of [bus], reverberated, to [l] and [r].
  void process(Float32List bus, int count, Float32List l, Float32List r) {
    for (var i = 0; i < count; i++) {
      final x = bus[i];
      final input = 0.015 * (x + x);
      var wetL = 0.0, wetR = 0.0;
      for (var c = 0; c < _combs.length; c++) {
        wetL += _leftCombs[c].tick(input);
        wetR += _rightCombs[c].tick(input);
      }
      for (var a = 0; a < _allpasses.length; a++) {
        wetL = _leftPass[a].tick(wetL);
        wetR = _rightPass[a].tick(wetR);
      }
      final direct = (1 - mix) * x;
      l[i] += x * _outerDry + (direct + mix * wetL) * _outerWet;
      r[i] += x * _outerDry + (direct + mix * wetR) * _outerWet;
    }
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
