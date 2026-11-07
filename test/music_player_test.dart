import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sprawl_run/audio/song.dart';
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
  List<String> started = const [];

  @override
  Stream<String?> get nowPlaying => const Stream.empty();

  @override
  Stream<double?> get progress => const Stream.empty();

  final calls = <String>[];

  @override
  Future<bool> start(String songId, {List<String> then = const []}) async {
    started = [songId, ...then];
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
  Future<void> setLevel(MusicLevel level, {bool atOnce = false}) async => calls.add('level:${level.name}:$atOnce');

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

    testWidgets('a level reaches the generator: low comes out slower', (tester) async {
      await tester.runAsync(() async {
        expect(await player.start('neon_pursuit'), isTrue);
        await harness.wrote.future.timeout(const Duration(seconds: 30));
        final normal = harness.writes.first.length;

        await player.setLevel(MusicLevel.low, atOnce: true);
        final seen = harness.writes.length;
        while (harness.writes.length < seen + 3) {
          await harness.wrote.future.timeout(const Duration(seconds: 30));
        }
        expect(harness.writes.last.length, greaterThan(normal + 8));
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

    testWidgets('a missing song in a queue costs only itself', (tester) async {
      await tester.runAsync(() async {
        expect(await player.start('no_such_song', then: const ['neon_pursuit']), isTrue);
        await harness.wrote.future.timeout(const Duration(seconds: 30));
      });
    });

    testWidgets('announces the song it starts, and none once it stops', (tester) async {
      await tester.runAsync(() async {
        final heard = <String?>[];
        final sub = player.nowPlaying.listen(heard.add);
        expect(await player.start('neon_pursuit'), isTrue);
        await harness.wrote.future.timeout(const Duration(seconds: 30));
        expect(heard, ['neon_pursuit']);
        await player.stop();
        await Future<void>.delayed(Duration.zero);
        expect(heard, ['neon_pursuit', null]);
        await sub.cancel();
      });
    });

    testWidgets('a queue of nothing that exists starts nothing', (tester) async {
      await tester.runAsync(() async {
        expect(await player.start('no_such_song', then: const ['nor_this']), isFalse);
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

    testWidgets('takes the queue off how far the song has been made', (tester) async {
      await tester.runAsync(() async {
        final seen = <double?>[];
        final sub = player.progress.listen(seen.add);
        // Half made, with two bars of a hundred still queued ahead of the ear.
        player.reportProgress(2000, madeTo: 0.5, barShare: 0.01, barMs: 1000);
        await Future<void>.delayed(Duration.zero);
        expect(seen.single, closeTo(0.48, 0.0001));

        // Too small a move to be worth a redraw.
        player.reportProgress(2000, madeTo: 0.5005, barShare: 0.01, barMs: 1000);
        await Future<void>.delayed(Duration.zero);
        expect(seen, hasLength(1));

        // More queued than made so far, as at the start of a song.
        player.reportProgress(9000, madeTo: 0.01, barShare: 0.01, barMs: 1000);
        await Future<void>.delayed(Duration.zero);
        expect(seen.last, 0);
        await sub.cancel();
      });
    });

    testWidgets('a phone falling behind loses layers before it loses the music', (tester) async {
      await tester.runAsync(() async {
        expect(await player.start('neon_pursuit'), isTrue);
        await player.setLevel(MusicLevel.high);
        expect(player.level, MusicLevel.high);

        expect(player.stepDown(), isTrue);
        expect(player.level, MusicLevel.normal);
        await player.setLevel(MusicLevel.high);
        expect(player.level, MusicLevel.normal, reason: 'a chase can not put back what the phone gave up');

        expect(player.stepDown(), isTrue);
        expect(player.level, MusicLevel.low);
        expect(player.stepDown(), isFalse, reason: 'nothing left to take away');
        await player.stop();
        expect(player.level, MusicLevel.normal, reason: 'the next run starts over');
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

    test('the drone\'s old switch becomes the choice', () {
      expect(Profile.fromJson(const {'ambientBed': true}).music, Profile.ambientMusic);
      expect(Profile.fromJson(const {'ambientBed': true, 'music': 'off'}).ambientBedOn, isTrue);
      expect(Profile.fromJson(const {'ambientBed': false}).music, Profile.noMusic);
      expect(
        Profile.fromJson(const {'ambientBed': true, 'music': 'neon_pursuit'}).music,
        'neon_pursuit',
        reason: 'a song already replaced the bed',
      );
    });

    test('moving off the drone is not undone by the old switch', () {
      const before = Profile(music: Profile.ambientMusic);
      expect(before.toJson()['ambientBed'], isTrue);
      final saved = before.copyWith(music: Profile.noMusic).toJson();
      expect(saved['ambientBed'], isFalse);
      expect(Profile.fromJson(saved).music, Profile.noMusic);
    });

    test('shuffle and best match count as generated music', () {
      expect(const Profile(music: Profile.shuffleMusic).generatedMusicOn, isTrue);
      expect(const Profile(music: Profile.bestMatchMusic).generatedMusicOn, isTrue);
      expect(reservedSongIds, containsAll([Profile.noMusic, Profile.ambientMusic, Profile.shuffleMusic, Profile.bestMatchMusic]));
    });

    test('songs left out survive a round trip, and start empty', () {
      expect(Profile.fromJson(const {}).songsLeftOut, isEmpty);
      final saved = const Profile(songsLeftOut: ['undercity']).toJson();
      expect(Profile.fromJson(saved).songsLeftOut, ['undercity']);
    });

    test('following effort is on unless the runner turned it off', () {
      expect(Profile.fromJson(const {}).musicFollowsEffort, isTrue);
      final off = Profile.fromJson(const Profile(musicFollowsEffort: false).toJson());
      expect(off.musicFollowsEffort, isFalse);
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

    testWidgets('a level reaches the player only while a song is playing', (tester) async {
      await tester.runAsync(() async {
        final music = _RecordingPlayer();
        final subject = narrator(music, MusicResumeGuard(isMusicActive: () async => false, sendPlay: () async {}));
        await subject.init(const Profile(music: 'neon_pursuit'));
        await subject.setMusicLevel(MusicLevel.high);
        expect(music.calls, isEmpty);

        await subject.startMusic();
        await subject.setMusicLevel(MusicLevel.high, atOnce: true);
        expect(music.calls, contains('level:high:true'));
      });
    });

    testWidgets('a queue reaches the player in order; without one the profile names the song', (tester) async {
      await tester.runAsync(() async {
        final music = _RecordingPlayer();
        final subject = narrator(music, MusicResumeGuard(isMusicActive: () async => false, sendPlay: () async {}));
        await subject.init(const Profile(music: Profile.shuffleMusic));
        await subject.startMusic(queue: const ['b', 'a', 'c']);
        expect(music.started, ['b', 'a', 'c']);

        final single = _RecordingPlayer();
        final other = narrator(single, MusicResumeGuard(isMusicActive: () async => false, sendPlay: () async {}));
        await other.init(const Profile(music: 'neon_pursuit'));
        await other.startMusic();
        expect(single.started, ['neon_pursuit']);
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

  group('the ambient bed', () {
    testWidgets('starting it does not wait for a loop that never ends', (tester) async {
      await tester.runAsync(() async {
        final bed = _LoopingPlayer();
        final subject = AudioNarrator(
          bedPlayer: bed,
          resumeGuard: MusicResumeGuard(isMusicActive: () async => false, sendPlay: () async {}),
        );
        await subject.init(const Profile(music: Profile.ambientMusic));

        await subject.setAmbientBed(true).timeout(const Duration(seconds: 5));
        expect(bed.playing, isTrue);
      });
    });

    testWidgets('a settings change only ever stops it, since a run starts it', (tester) async {
      await tester.runAsync(() async {
        final bed = _LoopingPlayer();
        final subject = AudioNarrator(
          bedPlayer: bed,
          resumeGuard: MusicResumeGuard(isMusicActive: () async => false, sendPlay: () async {}),
        );
        await subject.init(const Profile());

        await subject.applyProfile(const Profile(music: Profile.ambientMusic));
        expect(bed.playing, isFalse);

        await subject.setAmbientBed(true).timeout(const Duration(seconds: 5));
        await subject.applyProfile(const Profile(music: 'neon_pursuit'));
        expect(bed.playing, isFalse);
      });
    });
  });

  group('the ambient bed in a run', () {
    Future<(AudioNarrator, _LoopingPlayer)> started(Profile profile) async {
      final bed = _LoopingPlayer();
      final subject = AudioNarrator(
        bedPlayer: bed,
        resumeGuard: MusicResumeGuard(isMusicActive: () async => false, sendPlay: () async {}),
      );
      await subject.init(profile);
      await subject.setAmbientBed(profile.ambientBedOn);
      return (subject, bed);
    }

    testWidgets('pausing the run holds it and resuming lets it go', (tester) async {
      await tester.runAsync(() async {
        final (subject, bed) = await started(const Profile(music: Profile.ambientMusic));
        expect(bed.playing, isTrue);
        await subject.setMusicPaused(true);
        expect(bed.playing, isFalse);
        await subject.setMusicPaused(false);
        expect(bed.playing, isTrue);
      });
    });

    testWidgets('resuming starts nothing for a runner who did not choose it', (tester) async {
      await tester.runAsync(() async {
        final (subject, bed) = await started(const Profile());
        await subject.setMusicPaused(true);
        await subject.setMusicPaused(false);
        expect(bed.playing, isFalse);
      });
    });

    testWidgets('nothing brings it back after the run has stopped it', (tester) async {
      await tester.runAsync(() async {
        final (subject, bed) = await started(const Profile(music: Profile.ambientMusic));
        await subject.stopAll();
        await subject.setMusicPaused(false);
        expect(bed.playing, isFalse);
      });
    });

    testWidgets('a new run does not inherit the last one\'s pause', (tester) async {
      await tester.runAsync(() async {
        final (subject, bed) = await started(const Profile(music: Profile.ambientMusic));
        await subject.setMusicPaused(true);
        await subject.stopAll();
        await subject.setAmbientBed(true);
        expect(bed.playing, isTrue);
      });
    });

    testWidgets('it follows the music volume and not the effects volume', (tester) async {
      await tester.runAsync(() async {
        const profile = Profile(music: Profile.ambientMusic, musicVolume: 0.4, sfxVolume: 1);
        final (subject, bed) = await started(profile);
        final atFour = bed.volume;
        await subject.applyProfile(profile.copyWith(sfxVolume: 0.2));
        expect(bed.volume, atFour);
        await subject.applyProfile(profile.copyWith(musicVolume: 0.8));
        expect(bed.volume, closeTo(atFour * 2, 0.0001));
      });
    });
  });

  group('RunEngine', () {
    test('a run asks for the bed only when it is the choice', () async {
      for (final (music, expected) in [(Profile.ambientMusic, true), ('neon_pursuit', false), (Profile.noMusic, false)]) {
        final narrator = FakeNarrator();
        final engine = RunEngine(narrator: narrator, location: FakeLocation());
        await engine.start(goal: const RunGoal(GoalType.time, 600), profile: Profile(music: music));
        expect(narrator.ambientBed, expected, reason: music);
        await engine.abort();
      }
    });

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

/// Behaves as just_audio does for a looping source: play() completes only when
/// the player is paused or stopped, which is what once hung every caller.
class _LoopingPlayer extends AudioPlayer {
  _LoopingPlayer() : super(handleAudioSessionActivation: false);

  Completer<void>? _playback;

  @override
  bool get playing => _playback != null;

  @override
  Future<void> play() => (_playback ??= Completer<void>()).future;

  void _end() {
    _playback?.complete();
    _playback = null;
  }

  @override
  Future<void> pause() async => _end();

  @override
  Future<void> stop() async => _end();

  @override
  Future<Duration?> setAsset(String assetPath, {String? package, bool preload = true, Duration? initialPosition, dynamic tag}) async =>
      null;

  double _volume = 1;

  @override
  double get volume => _volume;

  @override
  Future<void> setVolume(double volume) async => _volume = volume;

  @override
  Future<void> setLoopMode(LoopMode mode) async {}
}
