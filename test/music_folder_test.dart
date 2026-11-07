import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sprawl_run/audio/song.dart' show MusicLevel;
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/services/music_folder.dart';
import 'package:sprawl_run/services/music_player.dart';
import 'package:sprawl_run/services/music_resume.dart';
import 'package:sprawl_run/services/narrator.dart';
import 'package:sprawl_run/services/run_engine.dart';
import 'package:sprawl_run/state/app_state.dart';

import 'support/fakes.dart';

/// Records what a real player is told, and hangs on play() as a loop does.
class _Player extends AudioPlayer {
  _Player() : super(handleAudioSessionActivation: false);

  final calls = <String>[];
  final index = StreamController<int?>.broadcast();
  final events = StreamController<PlaybackEvent>.broadcast();
  List<AudioSource> sources = const [];
  double gain = 1;

  @override
  Stream<int?> get currentIndexStream => index.stream;

  /// The real player listens to this itself while being built, without handling
  /// errors, so only what comes after that gets the stream a test writes to.
  bool _built = false;

  @override
  Stream<PlaybackEvent> get playbackEventStream => _built ? events.stream : const Stream.empty();

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    sources = audioSources;
    return null;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    _built = true;
    calls.add('loop:${mode.name}');
  }

  @override
  Future<void> setVolume(double volume) async => gain = volume;

  @override
  Future<void> play() {
    calls.add('play');
    return Completer<void>().future;
  }

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> seekToNext() async => calls.add('next');
}

class _Plain implements MusicPlayer {
  final List<String> calls = [];

  @override
  Stream<String?> get nowPlaying => const Stream.empty();

  @override
  Future<bool> start(String songId, {List<String> then = const []}) async {
    calls.add('start:$songId');
    return true;
  }

  @override
  Future<void> setPaused(bool paused) async => calls.add('paused:$paused');

  @override
  Future<void> setDucked(bool ducked) async {}

  @override
  Future<void> setVolume(double volume) async => calls.add('volume');

  @override
  Future<void> setLevel(MusicLevel level, {bool atOnce = false}) async => calls.add('level');

  @override
  Future<void> stop() async => calls.add('stop');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('natural order', () {
    test('numbers sort as numbers, and case does not matter', () {
      final names = ['Track 10.mp3', 'track 2.mp3', 'Track 1.mp3', 'alpha.mp3', 'Zulu.mp3'];
      names.sort(naturalOrder);
      expect(names, ['alpha.mp3', 'Track 1.mp3', 'track 2.mp3', 'Track 10.mp3', 'Zulu.mp3']);
    });

    test('a name that is a prefix of another comes first', () {
      expect(naturalOrder('run', 'run 2'), lessThan(0));
    });

    test('tracks are listed in that order', () {
      final sorted = MusicFolder.sorted(const [
        FolderTrack(uri: 'b', name: '10 b.mp3'),
        FolderTrack(uri: 'a', name: '2 a.mp3'),
      ]);
      expect([for (final t in sorted) t.uri], ['a', 'b']);
    });
  });

  test('a track\'s title drops its extension, and only that', () {
    expect(const FolderTrack(uri: 'x', name: 'Nite.Drive.flac').title, 'Nite.Drive');
    expect(const FolderTrack(uri: 'x', name: 'no extension').title, 'no extension');
    expect(const FolderTrack(uri: 'x', name: '.hidden').title, '.hidden');
  });

  test('a folder is its own kind of music: no levels, no recorded song', () {
    const profile = Profile(music: Profile.folderMusic);
    expect(profile.folderMusicOn, isTrue);
    expect(profile.generatedMusicOn, isFalse);
    expect(profile.runMusicOn, isTrue);
    expect(Profile.fromJson(const {}).folderRandom, isFalse);
    expect(Profile.fromJson(const Profile(folderRandom: true).toJson()).folderRandom, isTrue);
  });

  group('a run with a folder', () {
    test('asks for no levels and records no song', () {
      fakeAsyncRun((elapse) {
        final narrator = FakeNarrator();
        final engine = RunEngine(narrator: narrator, location: FakeLocation());
        engine.start(
          goal: const RunGoal(GoalType.time, 60),
          profile: const Profile(music: Profile.folderMusic),
          musicQueue: const ['content://a', 'content://b'],
        );
        elapse(const Duration(seconds: 70));
        expect(narrator.musicQueue, ['content://a', 'content://b']);
        expect(narrator.musicLevels, isEmpty);
        expect(engine.snapshot().song, isNull);
        engine.abort();
      });
    });

    testWidgets('with nothing in it, the runner keeps their own player', (tester) async {
      await tester.runAsync(() async {
        var asked = 0;
        final music = _Plain();
        final subject = AudioNarrator(
          music: music,
          resumeGuard: MusicResumeGuard(
            isMusicActive: () async {
              asked++;
              return true;
            },
            sendPlay: () async {},
          ),
        );
        await subject.init(const Profile(music: Profile.folderMusic));
        await subject.startMusic();
        expect(music.calls, isEmpty);
        expect(asked, 0, reason: 'nothing that would take focus was started');
      });
    });
  });

  group('AppState', () {
    Future<AppState> state(WidgetTester tester, Profile profile, List<FolderTrack> tracks) async {
      final root = Directory.systemTemp.createTempSync('folder');
      addTearDown(() => root.deleteSync(recursive: true));
      final profiles = ProfileRepository(root);
      final app = AppState(
        profiles: profiles,
        runs: RunRepository(Directory('${root.path}/runs')),
        missions: MissionRepository(externalDir: Directory('${root.path}/packs')),
        narrator: FakeNarrator(),
        musicFolder: MusicFolder(
          current: () async => 'Run mix',
          choose: () async => 'Run mix',
          forget: () async {},
          list: () async => tracks,
        ),
      );
      await tester.runAsync(() async {
        await profiles.save(profile);
        await app.load();
      });
      return app;
    }

    const tracks = [
      FolderTrack(uri: 'content://1', name: 'one.mp3'),
      FolderTrack(uri: 'content://2', name: 'two.mp3'),
      FolderTrack(uri: 'content://3', name: 'three.mp3'),
      FolderTrack(uri: 'content://4', name: 'four.mp3'),
    ];
    const goal = RunGoal(GoalType.time, 1800);

    testWidgets('plays the folder in order, by default', (tester) async {
      final app = await state(tester, const Profile(music: Profile.folderMusic), tracks);
      expect(app.musicFolderName, 'Run mix');
      expect(app.musicQueue(goal: goal, activity: Activity.run), [for (final t in tracks) t.uri]);
      expect(app.songName('content://2'), 'two');
    });

    testWidgets('or at random, each file once', (tester) async {
      final app = await state(tester, const Profile(music: Profile.folderMusic, folderRandom: true), tracks);
      final queue = app.musicQueue(goal: goal, activity: Activity.run, random: Random(3));
      expect(queue.toSet(), {for (final t in tracks) t.uri});
      expect(queue, isNot([for (final t in tracks) t.uri]));
    });

    testWidgets('an empty folder queues nothing', (tester) async {
      final app = await state(tester, const Profile(music: Profile.folderMusic), const []);
      expect(app.musicQueue(goal: goal, activity: Activity.run), isEmpty);
    });
  });

  group('FolderMusicPlayer', () {
    testWidgets('loops the queue, does not wait on play, and names what is heard', (tester) async {
      await tester.runAsync(() async {
        final raw = _Player();
        final player = FolderMusicPlayer(player: raw);
        final heard = <String?>[];
        player.nowPlaying.listen(heard.add);

        final started = await player.start('content://a', then: const ['content://b']).timeout(const Duration(seconds: 5));
        expect(started, isTrue);
        expect(raw.sources, hasLength(2));
        expect(raw.calls, containsAll(['loop:all', 'play']));

        raw.index.add(1);
        await Future<void>.delayed(Duration.zero);
        expect(heard, ['content://b']);

        await player.stop();
        await Future<void>.delayed(Duration.zero);
        expect(heard.last, isNull);
        expect(raw.calls.last, 'stop');
      });
    });

    testWidgets('a line lowers it, and a pause holds it', (tester) async {
      await tester.runAsync(() async {
        final raw = _Player();
        final player = FolderMusicPlayer(player: raw);
        await player.setVolume(0.5);
        await player.start('content://a');
        expect(raw.gain, 0.5);
        await player.setDucked(true);
        expect(raw.gain, closeTo(0.1, 0.001));
        await player.setDucked(false);
        expect(raw.gain, 0.5);
        await player.setPaused(true);
        expect(raw.calls.last, 'pause');
        await player.setPaused(false);
        expect(raw.calls.last, 'play');
      });
    });

    testWidgets('a file that will not play is skipped, and a folder of them ends it', (tester) async {
      await tester.runAsync(() async {
        final raw = _Player();
        final player = FolderMusicPlayer(player: raw);
        await player.start('content://a', then: const ['content://b']);

        raw.events.addError(Exception('bad file'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(raw.calls, contains('next'));

        raw.events.addError(Exception('bad file too'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(raw.calls.last, 'stop');
      });
    });
  });

  group('RunMusicPlayer', () {
    test('a file goes to the folder player and a song to the generator', () async {
      final songs = _Plain(), files = _Plain();
      final player = RunMusicPlayer(songs: songs, files: files);
      await player.start('content://x');
      expect(files.calls, contains('start:content://x'));
      expect(songs.calls, isNot(contains('start:content://x')));

      await player.setPaused(true);
      expect(files.calls.last, 'paused:true');

      await player.start('neon_pursuit');
      expect(songs.calls, contains('start:neon_pursuit'));
      expect(files.calls.last, 'stop', reason: 'only one plays at a time');
      await player.setLevel(MusicLevel.high);
      expect(songs.calls.last, 'level');
    });
  });
}

/// Runs [body] in fake time, with a way to move it on.
void fakeAsyncRun(void Function(void Function(Duration)) body) {
  fakeAsync((fake) {
    body((d) {
      fake.flushMicrotasks();
      fake.elapse(d);
      fake.flushMicrotasks();
    });
  });
}
