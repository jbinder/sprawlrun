import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/song_library.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/services/music_player.dart';
import 'package:sprawl_run/services/music_resume.dart';
import 'package:sprawl_run/services/narrator.dart';
import 'package:sprawl_run/services/run_engine.dart';

import 'support/fakes.dart';

/// Stands in for `MusicTrack.kt`, and for the song files in the app's assets.
class _Harness {
  _Harness() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'queuedMs':
          return queuedMs;
        case 'write':
          writes.add(call.arguments as Uint8List);
          wrote.complete();
          wrote = Completer();
          return null;
        case 'underruns':
          return 0;
        default:
          return null;
      }
    });
  }

  final channel = const MethodChannel('test/music');
  final calls = <String>[];
  final writes = <Uint8List>[];
  var wrote = Completer<void>();
  int queuedMs = 0;

  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  }
}

/// Offers `assets/songs/` as the real asset bundle does.
class _DiskBundle extends CachingAssetBundle {
  _DiskBundle({this.extra = const {}});

  final Map<String, String> extra;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      final assets = [
        for (final f in Directory('assets/songs').listSync().whereType<File>()) f.path,
        ...extra.keys,
      ];
      return const StandardMessageCodec().encodeMessage({
        for (final a in assets)
          a: [
            {'asset': a},
          ],
      })!;
    }
    final bytes = extra.containsKey(key)
        ? Uint8List.fromList(extra[key]!.codeUnits)
        : File(key).readAsBytesSync();
    return ByteData.sublistView(bytes);
  }
}

class _RecordingPlayer implements MusicPlayer {
  final calls = <String>[];

  @override
  Future<bool> start(String songId) async {
    calls.add('start');
    return true;
  }

  @override
  Future<void> setPaused(bool paused) async => calls.add('paused:$paused');

  @override
  Future<void> setDucked(bool ducked) async => calls.add('ducked:$ducked');

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async => calls.add('stop');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LiveMusicPlayer', () {
    late _Harness harness;
    late LiveMusicPlayer player;

    setUp(() {
      harness = _Harness();
      player = LiveMusicPlayer(
        SongLibrary(bundle: _DiskBundle()),
        channel: harness.channel,
        pumpEvery: const Duration(milliseconds: 5),
      );
    });

    tearDown(() async {
      await player.stop();
      harness.dispose();
    });

    testWidgets('generates PCM and hands it over while the queue wants it', (tester) async {
      await tester.runAsync(() async {
        expect(await player.start('neon_pursuit'), isTrue);
        await harness.wrote.future.timeout(const Duration(seconds: 30));
        expect(harness.calls, contains('start'));
        // A bar of stereo 16-bit at 170 BPM.
        expect(harness.writes.first.length, closeTo(4 * 60 / 170 * 44100 * 4, 8));
      });
    });

    testWidgets('makes no more than the queue wants', (tester) async {
      await tester.runAsync(() async {
        harness.queuedMs = LiveMusicPlayer.targetQueueMs;
        expect(await player.start('neon_pursuit'), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(harness.writes, isEmpty);
      });
    });

    testWidgets('stops feeding once stopped', (tester) async {
      await tester.runAsync(() async {
        await player.start('neon_pursuit');
        await harness.wrote.future.timeout(const Duration(seconds: 30));
        await player.stop();
        final count = harness.writes.length;
        expect(harness.calls.last, 'stop');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(harness.writes.length, count);
      });
    });

    testWidgets('a song that does not exist is refused without touching the track', (tester) async {
      await tester.runAsync(() async {
        expect(await player.start('no_such_song'), isFalse);
        expect(harness.calls, isNot(contains('start')));
      });
    });

    testWidgets('a broken file in the folder costs only itself', (tester) async {
      await tester.runAsync(() async {
        final mixed = LiveMusicPlayer(
          SongLibrary(bundle: _DiskBundle(extra: {'assets/songs/aaa_broken.json': '{"format": 1'})),
          channel: harness.channel,
          pumpEvery: const Duration(milliseconds: 5),
        );
        expect(await mixed.start('neon_pursuit'), isTrue);
        await mixed.stop();
      });
    });

    testWidgets('a track that throws ends the music and nothing else', (tester) async {
      await tester.runAsync(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(harness.channel, (
          call,
        ) async {
          if (call.method == 'queuedMs') throw PlatformException(code: 'gone');
          return null;
        });
        expect(await player.start('neon_pursuit'), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        // Reaching here without an uncaught error is the point.
      });
    });
  });

  group('RenderBudget', () {
    test('one slow bar is not enough', () {
      final budget = RenderBudget(bars: 4);
      budget.record(2000, 1400);
      for (var i = 0; i < 3; i++) {
        budget.record(300, 1400);
      }
      expect(budget.exceeded, isFalse);
    });

    test('falling behind for several bars is', () {
      final budget = RenderBudget(bars: 4);
      for (var i = 0; i < 4; i++) {
        budget.record(1400, 1400);
      }
      expect(budget.exceeded, isTrue);
    });

    test('it needs a full window before it judges', () {
      final budget = RenderBudget(bars: 4);
      budget.record(5000, 1400);
      expect(budget.exceeded, isFalse);
    });
  });

  group('Profile', () {
    test('music is off for a profile saved before it existed', () {
      final profile = Profile.fromJson(const {});
      expect(profile.generatedMusicOn, isFalse);
      expect(profile.musicVolume, 0.7);
    });

    test('the choice survives a round trip', () {
      final profile = Profile.fromJson(const Profile(music: 'neon_pursuit', musicVolume: 0.4).toJson());
      expect(profile.music, 'neon_pursuit');
      expect(profile.musicVolume, 0.4);
    });
  });

  group('AudioNarrator with music', () {
    AudioNarrator narrator(_RecordingPlayer music, MusicResumeGuard guard) =>
        AudioNarrator(music: music, resumeGuard: guard);

    testWidgets('puts the runner\'s own player back after the run', (tester) async {
      await tester.runAsync(() async {
        var active = true;
        var nudges = 0;
        final guard = MusicResumeGuard(
          isMusicActive: () async => active,
          sendPlay: () async => nudges++,
          settle: const Duration(milliseconds: 5),
        );
        final music = _RecordingPlayer();
        final subject = narrator(music, guard);
        await subject.init(const Profile(music: 'neon_pursuit'));

        await subject.startMusic();
        expect(music.calls, contains('start'));
        active = false; // Their player paused for the run, and stayed paused.

        await subject.stopAll();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(music.calls.last, 'stop');
        expect(nudges, 1);
      });
    });

    testWidgets('does not start anything for a runner with no music playing', (tester) async {
      await tester.runAsync(() async {
        var nudges = 0;
        final guard = MusicResumeGuard(
          isMusicActive: () async => false,
          sendPlay: () async => nudges++,
          settle: const Duration(milliseconds: 5),
        );
        final subject = narrator(_RecordingPlayer(), guard);
        await subject.init(const Profile(music: 'neon_pursuit'));
        await subject.startMusic();
        await subject.stopAll();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(nudges, 0);
      });
    });

    testWidgets('with music off, nothing is started', (tester) async {
      await tester.runAsync(() async {
        final music = _RecordingPlayer();
        final subject = narrator(
          music,
          MusicResumeGuard(isMusicActive: () async => false, sendPlay: () async {}),
        );
        await subject.init(const Profile());
        await subject.startMusic();
        expect(music.calls, isNot(contains('start')));
      });
    });
  });

  group('RunEngine', () {
    test('a manual pause holds the music and resuming lets it go', () async {
      final narrator = FakeNarrator();
      final engine = RunEngine(narrator: narrator, location: FakeLocation());
      await engine.start(goal: const RunGoal(GoalType.time, 600), profile: const Profile());
      expect(narrator.musicStarted, isTrue);

      engine.pause();
      expect(narrator.musicPaused, isTrue);
      engine.resume();
      expect(narrator.musicPaused, isFalse);
      await engine.abort();
    });
  });
}
