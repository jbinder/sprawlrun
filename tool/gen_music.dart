// Renders part of a song to a WAV, for listening while writing one.
//
//     fvm dart run tool/gen_music.dart <song.json> [out.wav] [fromBar] [bars] [levels]
//
// `levels` is one level (`low`, `normal`, `high`), or a change every so many bars
// to hear the joins: `low:16,normal:16,high:16` holds each for 16 bars, in turn.
//
// By default, the whole first pass. For Neon Pursuit, bars 24 to 67 are the hook,
// breakdown, build and drop, about 62 seconds. `music/` is gitignored.

import 'dart:io';
import 'dart:typed_data';

import 'package:sprawl_run/audio/song.dart';
import 'package:sprawl_run/audio/song_stream.dart';
import 'package:sprawl_run/audio/synth/dsp.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: gen_music.dart <song.json> [out.wav] [fromBar] [bars]');
    exit(64);
  }
  final song = Song.parse(File(args[0]).readAsStringSync());
  final out = File(args.length > 1 ? args[1] : 'music/${song.id}.wav');
  final fromBar = args.length > 2 ? int.parse(args[2]) : 0;
  final bars = args.length > 3 ? int.parse(args[3]) : song.bars;

  final clock = Stopwatch()..start();
  final changes = _levels(args.length > 4 ? args[4] : 'normal');
  final stream = SongStream(song, fromBar: fromBar, level: changes.values.first);
  final rendered = <RenderedBar>[];
  for (var n = 0; n < bars; n++) {
    if (changes[n] case final level?) stream.setLevel(level);
    rendered.add(stream.nextBar());
  }
  clock.stop();

  final frames = rendered.fold(0, (sum, bar) => sum + bar.left.length);
  final left = Float32List(frames), right = Float32List(frames);
  var at = 0;
  for (final bar in rendered) {
    left.setAll(at, bar.left);
    right.setAll(at, bar.right);
    at += bar.left.length;
  }
  _fadeOut(left, right, 0.75);

  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(_wav(left, right));

  final length = frames / sampleRate;
  final seconds = clock.elapsedMilliseconds / 1000;
  stdout.writeln(
    '${out.path}: bars $fromBar-${fromBar + bars - 1}, '
    '${length.toStringAsFixed(1)} s of audio in '
    '${seconds.toStringAsFixed(2)} s '
    '(${(length / seconds).toStringAsFixed(0)}x real time)',
  );
}

/// The bar each level starts at.
Map<int, MusicLevel> _levels(String text) {
  final out = <int, MusicLevel>{};
  var at = 0;
  for (final part in text.split(',')) {
    final [name, ...rest] = part.split(':');
    out[at] = MusicLevel.values.byName(name);
    if (rest.isNotEmpty) at += int.parse(rest.first);
  }
  return out;
}

/// The render stops mid-song, so it should not stop with a click.
void _fadeOut(Float32List left, Float32List right, double seconds) {
  final count = (seconds * sampleRate).round();
  final start = left.length - count;
  for (var i = 0; i < count; i++) {
    final gain = 1 - i / count;
    left[start + i] *= gain;
    right[start + i] *= gain;
  }
}

/// 16-bit stereo PCM.
Uint8List _wav(Float32List left, Float32List right) {
  final frames = left.length;
  final dataSize = frames * 4;
  final bytes = ByteData(44 + dataSize);
  void tag(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(at + i, text.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 2, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 4, Endian.little);
  bytes.setUint16(32, 4, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  bytes.setUint32(40, dataSize, Endian.little);
  for (var i = 0; i < frames; i++) {
    final at = 44 + i * 4;
    bytes.setInt16(at, (left[i] * 32767).round(), Endian.little);
    bytes.setInt16(at + 2, (right[i] * 32767).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}
