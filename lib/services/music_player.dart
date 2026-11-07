import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../audio/song.dart';
import '../audio/song_stream.dart';
import '../data/song_library.dart';

/// Plays a song during a run. Takes no audio focus: that is `AudioNarrator`'s
/// alone, and this only ever makes sound.
abstract class MusicPlayer {
  /// Plays [songId] and then each of [then], going round again after the last.
  /// With nothing to follow, the song repeats by itself. False if nothing could
  /// be started. Never throws for a bad song, and one bad song costs only itself.
  Future<bool> start(String songId, {List<String> then = const []});

  /// Holds playback in place, with the song's position and what is queued kept.
  Future<void> setPaused(bool paused);

  /// Lowers the music at once, under a story line.
  Future<void> setDucked(bool ducked);

  Future<void> setVolume(double volume);

  /// How much of the song to play, from its next phrase or with [atOnce] its next
  /// bar. What is already queued plays out first, which is about four seconds.
  Future<void> setLevel(MusicLevel level, {bool atOnce = false});

  /// The song being heard, as each one starts, and null once there is none. Comes
  /// when the sound does, not when it was made, which is seconds earlier.
  Stream<String?> get nowPlaying;

  /// How far through what is being heard, from 0 to 1, and null once nothing is.
  Stream<double?> get progress;

  /// Fades out and lets go of everything.
  Future<void> stop();
}

/// For a device with nothing to play with, and anything that needs no sound.
class SilentMusicPlayer implements MusicPlayer {
  const SilentMusicPlayer();

  @override
  Future<bool> start(String songId, {List<String> then = const []}) async => false;

  @override
  Future<void> setPaused(bool paused) async {}

  @override
  Future<void> setDucked(bool ducked) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setLevel(MusicLevel level, {bool atOnce = false}) async {}

  @override
  Stream<String?> get nowPlaying => const Stream.empty();

  @override
  Stream<double?> get progress => const Stream.empty();

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
  Timer? _pump, _report, _announcing;
  List<String> _ids = const [];
  int _songAt = -1;
  final StreamController<String?> _nowPlaying = StreamController<String?>.broadcast();

  @override
  Stream<String?> get nowPlaying => _nowPlaying.stream;

  final StreamController<double?> _progress = StreamController<double?>.broadcast();

  @override
  Stream<double?> get progress => _progress.stream;

  // Where the song has been made up to, what one bar of it is worth, and how long
  // a bar lasts: enough to take the queue off and say where it is being heard.
  double _madeTo = 0, _barShare = 0, _barMs = 1, _lastProgress = -1;

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
  Future<bool> start(String songId, {List<String> then = const []}) async {
    await stop();
    final sources = <String>[];
    final ids = <String>[];
    for (final id in [songId, ...then]) {
      final source = await _library.sourceOf(id);
      if (source == null) {
        debugPrint('Music: no song "$id"');
      } else {
        sources.add(source);
        ids.add(id);
      }
    }
    if (sources.isEmpty) return false;
    _ids = ids;
    _songAt = -1;
    try {
      await _channel.invokeMethod<void>('start');
      final port = ReceivePort(), errors = ReceivePort();
      _port = port;
      _errors = errors;
      errors.listen((e) => _fail('generator: $e'));
      port.listen(_fromGenerator);
      _isolate = await Isolate.spawn(_generate, (port.sendPort, sources), onError: errors.sendPort);
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
    if (message case (
      final TransferableTypedData data,
      final double renderMs,
      final double barMs,
      final int songAt,
      final double madeTo,
      final double barShare,
    )) {
      _waiting = false;
      _madeTo = madeTo;
      _barShare = barShare;
      _barMs = barMs;
      if (songAt != _songAt) unawaited(_announce(songAt));
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

  /// A new figure only when the line would visibly move, which keeps this from
  /// redrawing anything four times a second for nothing.
  @visibleForTesting
  void reportProgress(int queuedMs, {required double madeTo, required double barShare, required double barMs}) {
    _madeTo = madeTo;
    _barShare = barShare;
    _barMs = barMs;
    _reportProgress(queuedMs);
  }

  void _reportProgress(int queuedMs) {
    if (_barShare <= 0) return;
    final heard = (_madeTo - queuedMs / _barMs * _barShare).clamp(0.0, 1.0);
    if ((heard - _lastProgress).abs() < 0.002) return;
    _lastProgress = heard;
    _progress.add(heard);
  }

  /// What was just made is heard once the queue ahead of it has played.
  Future<void> _announce(int songAt) async {
    final first = _songAt < 0;
    _songAt = songAt;
    final id = _ids[songAt];
    if (first) {
      _nowPlaying.add(id);
      return;
    }
    var queued = 0;
    await _guarded(() async => queued = await _channel.invokeMethod<int>('queuedMs') ?? 0);
    _announcing?.cancel();
    _announcing = Timer(Duration(milliseconds: queued), () => _nowPlaying.add(id));
  }

  Future<void> _tick() async {
    if (_pumping || _requests == null) return;
    _pumping = true;
    await _guarded(() async {
      final queued = await _channel.invokeMethod<int>('queuedMs') ?? 0;
      if (_bars > 3 && queued < _minQueue) _minQueue = queued;
      _reportProgress(queued);
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
    _announcing?.cancel();
    _pump = _report = _announcing = null;
    if (_songAt >= 0) {
      _nowPlaying.add(null);
      _progress.add(null);
    }
    _songAt = -1;
    _barShare = 0;
    _lastProgress = -1;
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

/// Plays the runner's own files from `content://` addresses.
///
/// Through just_audio, which reads those directly, with no loopback server and so
/// no INTERNET. Built without session activation, like every player here: focus
/// is `AudioNarrator`'s. A recording can't change with the run, so levels do
/// nothing here. A file that will not play is skipped.
class FolderMusicPlayer implements MusicPlayer {
  FolderMusicPlayer({@visibleForTesting ja.AudioPlayer? player}) : _given = player;

  static const double _duckGain = 0.2;

  final ja.AudioPlayer? _given;
  ja.AudioPlayer? _built;
  ja.AudioPlayer get _player =>
      _given ?? (_built ??= ja.AudioPlayer(handleAudioSessionActivation: false, androidApplyAudioAttributes: false));

  final StreamController<String?> _nowPlaying = StreamController<String?>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];
  List<String> _uris = const [];
  double _volume = 1;
  bool _ducked = false;
  int _failures = 0;

  @override
  Stream<String?> get nowPlaying => _nowPlaying.stream;

  final StreamController<double?> _progress = StreamController<double?>.broadcast();
  double _lastProgress = -1;

  @override
  Stream<double?> get progress => _progress.stream;

  void _position(Duration position) {
    final total = _player.duration;
    if (total == null || total.inMilliseconds <= 0) return;
    final share = (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    if ((share - _lastProgress).abs() < 0.002) return;
    _lastProgress = share;
    _progress.add(share);
  }

  double get _gain => _volume * (_ducked ? _duckGain : 1);

  @override
  Future<bool> start(String songId, {List<String> then = const []}) async {
    await stop();
    _uris = [songId, ...then];
    _failures = 0;
    _ducked = false;
    final player = _player;
    try {
      await player.setLoopMode(ja.LoopMode.all);
      await player.setVolume(_gain);
      _subs
        ..add(player.currentIndexStream.listen(_heard))
        ..add(player.positionStream.listen(_position))
        ..add(player.playbackEventStream.listen(_played, onError: (Object e, StackTrace _) => _failed(e)));
      await player.setAudioSources(
        [for (final uri in _uris) ja.AudioSource.uri(Uri.parse(uri))],
        preload: false,
      );
      _resume();
      return true;
    } on Object catch (e) {
      debugPrint('Folder music failed to start: $e');
      await stop();
      return false;
    }
  }

  void _heard(int? index) {
    if (index != null && index < _uris.length) {
      _nowPlaying.add(_uris[index]);
      _lastProgress = -1;
    }
  }

  void _played(ja.PlaybackEvent event) {
    if (event.processingState == ja.ProcessingState.ready) _failures = 0;
  }

  void _failed(Object error) {
    debugPrint('Folder music: skipping a file: $error');
    _failures++;
    if (_failures >= _uris.length) {
      debugPrint('Folder music: nothing in the folder plays');
      unawaited(stop());
      return;
    }
    unawaited(_skip());
  }

  Future<void> _skip() async {
    try {
      await _player.seekToNext();
      _resume();
    } on Object catch (e) {
      debugPrint('Folder music: $e');
    }
  }

  /// Not awaited: play() completes when playback ends, which a loop never does.
  void _resume() {
    unawaited(_player.play().catchError((Object e) => _failed(e)));
  }

  @override
  Future<void> setPaused(bool paused) async {
    if (_uris.isEmpty) return;
    if (paused) {
      await _player.pause();
    } else {
      _resume();
    }
  }

  @override
  Future<void> setDucked(bool ducked) async {
    _ducked = ducked;
    if (_uris.isNotEmpty) await _player.setVolume(_gain);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    if (_uris.isNotEmpty) await _player.setVolume(_gain);
  }

  @override
  Future<void> setLevel(MusicLevel level, {bool atOnce = false}) async {}

  @override
  Future<void> stop() async {
    final had = _uris.isNotEmpty;
    _uris = const [];
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    if (!had) return;
    try {
      await _player.stop();
    } on Object catch (e) {
      debugPrint('Folder music failed to stop: $e');
    }
    _nowPlaying.add(null);
    _progress.add(null);
    _lastProgress = -1;
  }
}

/// Sends a run's music to whichever player can play it: a `content://` address
/// is a file, anything else a song.
class RunMusicPlayer implements MusicPlayer {
  RunMusicPlayer({required this.songs, required this.files}) {
    songs.nowPlaying.listen(_nowPlaying.add);
    files.nowPlaying.listen(_nowPlaying.add);
    songs.progress.listen(_progress.add);
    files.progress.listen(_progress.add);
  }

  final MusicPlayer songs, files;
  late MusicPlayer _active = songs;
  final StreamController<String?> _nowPlaying = StreamController<String?>.broadcast();
  final StreamController<double?> _progress = StreamController<double?>.broadcast();

  @override
  Stream<String?> get nowPlaying => _nowPlaying.stream;

  @override
  Stream<double?> get progress => _progress.stream;

  @override
  Future<bool> start(String songId, {List<String> then = const []}) async {
    await _active.stop();
    _active = songId.startsWith('content:') ? files : songs;
    return _active.start(songId, then: then);
  }

  @override
  Future<void> setPaused(bool paused) => _active.setPaused(paused);

  @override
  Future<void> setDucked(bool ducked) => _active.setDucked(ducked);

  @override
  Future<void> setVolume(double volume) async {
    await songs.setVolume(volume);
    await files.setVolume(volume);
  }

  @override
  Future<void> setLevel(MusicLevel level, {bool atOnce = false}) => _active.setLevel(level, atOnce: atOnce);

  @override
  Future<void> stop() => _active.stop();
}

/// The isolate: makes the next bar each time it is asked.
void _generate((SendPort, List<String>) start) {
  final (out, sources) = start;
  final requests = ReceivePort();
  out.send(requests.sendPort);
  final stream = SongSequence([for (final source in sources) Song.parse(source)]);
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
      stream.currentIndex,
      stream.position,
      stream.barShare,
    ));
  });
}
