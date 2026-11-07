import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../audio/song.dart';
import '../audio/song_stream.dart';
import '../data/song_library.dart';

/// Plays a song during a run. Takes no audio focus: that is `AudioNarrator`'s
/// alone, and this only ever makes sound.
abstract class MusicPlayer {
  /// False if the song could not be started. Never throws for a bad song.
  Future<bool> start(String songId);

  /// Holds playback in place, with the song's position and what is queued kept.
  Future<void> setPaused(bool paused);

  /// Lowers the music at once, under a story line.
  Future<void> setDucked(bool ducked);

  Future<void> setVolume(double volume);

  /// How much of the song to play, from its next phrase or with [atOnce] its next
  /// bar. What is already queued plays out first, which is about four seconds.
  Future<void> setLevel(MusicLevel level, {bool atOnce = false});

  /// Fades out and lets go of everything.
  Future<void> stop();
}

/// For a device with nothing to play with, and anything that needs no sound.
class SilentMusicPlayer implements MusicPlayer {
  const SilentMusicPlayer();

  @override
  Future<bool> start(String songId) async => false;

  @override
  Future<void> setPaused(bool paused) async {}

  @override
  Future<void> setDucked(bool ducked) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setLevel(MusicLevel level, {bool atOnce = false}) async {}

  @override
  Future<void> stop() async {}
}

/// Whether the phone is keeping up with the song, over the last few bars. One
/// slow bar is what the queue is there for; only falling behind for good means
/// the song can't be played here.
class RenderBudget {
  RenderBudget({this.bars = 8, this.limit = 0.9});

  final int bars;
  final double limit;
  final List<double> _shares = [];

  /// Records a bar that took [renderMs] to make and lasts [barMs].
  void record(double renderMs, double barMs) {
    _shares.add(renderMs / barMs);
    if (_shares.length > bars) _shares.removeAt(0);
  }

  /// Starts judging afresh, after something has changed what a bar costs.
  void clear() => _shares.clear();

  bool get exceeded =>
      _shares.length == bars && _shares.reduce((a, b) => a + b) / bars > limit;
}

/// Makes a song in an isolate and feeds it to an `AudioTrack` in Kotlin.
///
/// Not through just_audio: its `StreamAudioSource` serves audio from a loopback
/// HTTP server, which needs the INTERNET permission this app does not have. The
/// isolate is what keeps a song from slowing the run down, and anything going
/// wrong in it ends the music and nothing else.
class LiveMusicPlayer implements MusicPlayer {
  LiveMusicPlayer(this._library, {MethodChannel? channel, this.pumpEvery = const Duration(milliseconds: 250)})
    : _channel = channel ?? const MethodChannel('io.github.jbinder.sprawlrun/music');

  /// How much sound to keep ready. A stall shorter than this is never heard.
  static const int targetQueueMs = 4000;

  final SongLibrary _library;
  final MethodChannel _channel;
  final Duration pumpEvery;

  Isolate? _isolate;
  ReceivePort? _port, _errors;
  SendPort? _requests;
  Timer? _pump, _report;
  bool _waiting = false, _pumping = false;
  final RenderBudget _budget = RenderBudget();

  /// The level asked for, and the most this phone has shown it can keep up with.
  MusicLevel _wanted = MusicLevel.normal, _ceiling = MusicLevel.high;

  @visibleForTesting
  MusicLevel get level => _wanted.index < _ceiling.index ? _wanted : _ceiling;

  // Figures for logcat, so a report of a gap can be read against them.
  int _bars = 0;
  double _worstBar = 0;
  int _minQueue = 1 << 30;

  @override
  Future<bool> start(String songId) async {
    await stop();
    final source = await _library.sourceOf(songId);
    if (source == null) {
      debugPrint('Music: no song "$songId"');
      return false;
    }
    try {
      await _channel.invokeMethod<void>('start');
      final port = ReceivePort(), errors = ReceivePort();
      _port = port;
      _errors = errors;
      errors.listen((e) => _fail('generator: $e'));
      port.listen(_fromGenerator);
      _isolate = await Isolate.spawn(_generate, (port.sendPort, source), onError: errors.sendPort);
      _pump = Timer.periodic(pumpEvery, (_) => _tick());
      _report = Timer.periodic(const Duration(minutes: 1), (_) => _logFigures());
      return true;
    } on Object catch (e) {
      debugPrint('Music failed to start: $e');
      await stop();
      return false;
    }
  }

  void _fromGenerator(Object? message) {
    if (message is SendPort) {
      _requests = message;
      _sendLevel(atOnce: true);
      return;
    }
    if (message case (final TransferableTypedData data, final double renderMs, final double barMs)) {
      _waiting = false;
      _bars++;
      if (renderMs > _worstBar) _worstBar = renderMs;
      _budget.record(renderMs, barMs);
      if (_budget.exceeded) {
        if (!stepDown()) {
          _fail('this phone cannot keep up with the song');
          return;
        }
      }
      unawaited(_guarded(() => _channel.invokeMethod<void>('write', data.materialize().asUint8List())));
      _tick();
    }
  }

  /// Fewer layers cost less, so a phone falling behind loses those before the
  /// music. For the rest of the run: it would only fall behind again. False when
  /// there is nothing left to take away.
  @visibleForTesting
  bool stepDown() {
    final current = level;
    if (current == MusicLevel.low) return false;
    _ceiling = MusicLevel.values[current.index - 1];
    _budget.clear();
    debugPrint('Music: falling behind, staying at or below ${_ceiling.name}');
    _sendLevel(atOnce: true);
    return true;
  }

  void _sendLevel({required bool atOnce}) => _requests?.send((level.index, atOnce));

  Future<void> _tick() async {
    if (_pumping || _requests == null) return;
    _pumping = true;
    await _guarded(() async {
      final queued = await _channel.invokeMethod<int>('queuedMs') ?? 0;
      if (_bars > 3 && queued < _minQueue) _minQueue = queued;
      if (queued < targetQueueMs && !_waiting) {
        _waiting = true;
        _requests?.send(null);
      }
    });
    _pumping = false;
  }

  Future<void> _logFigures() => _guarded(() async {
    final underruns = await _channel.invokeMethod<int>('underruns');
    debugPrint(
      'Music: bars=$_bars worstBar=${_worstBar.round()}ms '
      'minQueue=${_minQueue == 1 << 30 ? '-' : _minQueue}ms underruns=$underruns',
    );
    _worstBar = 0;
    _minQueue = 1 << 30;
  });

  /// Everything that crosses to Kotlin goes through here, so that nothing about
  /// the music can throw into a run.
  Future<void> _guarded(Future<void> Function() call) async {
    try {
      await call();
    } on Object catch (e) {
      _fail('$e');
    }
  }

  void _fail(String why) {
    debugPrint('Music stopped: $why');
    unawaited(stop());
  }

  @override
  Future<void> setPaused(bool paused) => _quietly(paused ? 'pause' : 'resume');

  @override
  Future<void> setDucked(bool ducked) => _quietly('duck', ducked);

  @override
  Future<void> setVolume(double volume) => _quietly('volume', volume);

  @override
  Future<void> setLevel(MusicLevel level, {bool atOnce = false}) async {
    _wanted = level;
    debugPrint('Music: level ${this.level.name}${atOnce ? ' at once' : ''}');
    _sendLevel(atOnce: atOnce);
  }

  Future<void> _quietly(String method, [Object? argument]) async {
    try {
      await _channel.invokeMethod<void>(method, argument);
    } on Object catch (e) {
      debugPrint('Music $method failed: $e');
    }
  }

  @override
  Future<void> stop() async {
    _pump?.cancel();
    _report?.cancel();
    _pump = _report = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port?.close();
    _errors?.close();
    _port = _errors = null;
    _requests = null;
    _waiting = false;
    _wanted = MusicLevel.normal;
    _ceiling = MusicLevel.high;
    _budget.clear();
    _bars = 0;
    _worstBar = 0;
    _minQueue = 1 << 30;
    await _quietly('stop');
  }
}

/// The isolate: makes the next bar each time it is asked.
void _generate((SendPort, String) start) {
  final (out, source) = start;
  final requests = ReceivePort();
  out.send(requests.sendPort);
  final song = Song.parse(source);
  final stream = SongStream(song);
  requests.listen((request) {
    if (request case (final int level, final bool atOnce)) {
      stream.setLevel(MusicLevel.values[level], atOnce: atOnce);
      return;
    }
    final clock = Stopwatch()..start();
    final bar = stream.nextBar();
    final frames = bar.left.length;
    final bytes = ByteData(frames * 4);
    for (var i = 0; i < frames; i++) {
      bytes.setInt16(i * 4, (bar.left[i] * 32767).round(), Endian.little);
      bytes.setInt16(i * 4 + 2, (bar.right[i] * 32767).round(), Endian.little);
    }
    out.send((
      TransferableTypedData.fromList([bytes.buffer.asUint8List()]),
      clock.elapsedMicroseconds / 1000,
      bar.seconds * 1000,
    ));
  });
}
