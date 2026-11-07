import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/audio/song.dart';
import 'package:sprawl_run/models/goal.dart';
import 'package:sprawl_run/models/run_record.dart';
import 'package:sprawl_run/services/song_picker.dart';

void main() {
  final songs = [
    for (final f in Directory('assets/songs').listSync().whereType<File>()) Song.parse(f.readAsStringSync()),
  ];

  /// The songs that open a run across many tries, however chance falls.
  Set<String> openers(RunSetting setting, {List<String> recent = const []}) => {
    for (var seed = 0; seed < 60; seed++)
      SongPicker.bestMatch(songs, setting: setting, recent: recent, random: Random(seed)).first,
  };

  group('best match', () {
    test('a walk gets the rainy one, whatever the mission holds', () {
      expect(openers(const RunSetting(walking: true)), {'sodium_rain'});
      expect(openers(const RunSetting(walking: true, chases: 5)), {'sodium_rain'});
    });

    test('a chase-heavy mission gets something hard', () {
      expect(openers(const RunSetting(chases: 4)), {'black_ice', 'undercity'});
    });

    test('a long run or a finale gets the big one', () {
      expect(openers(const RunSetting(long: true)), {'skyline_breach'});
      expect(openers(const RunSetting(finale: true)), {'skyline_breach'});
    });

    test('an ordinary run shares between the everyday songs', () {
      expect(openers(const RunSetting()), {'neon_pursuit', 'cold_boot'});
    });

    test('what played last gives way to an equally good match', () {
      expect(openers(const RunSetting(chases: 4), recent: const ['black_ice']), {'undercity'});
      expect(openers(const RunSetting(), recent: const ['cold_boot']), {'neon_pursuit'});
    });

    test('but not to a song that does not suit the run', () {
      expect(openers(const RunSetting(walking: true), recent: const ['sodium_rain']), {'sodium_rain'});
    });

    test('every song is in the queue, once', () {
      final queue = SongPicker.bestMatch(songs, setting: const RunSetting(), recent: const [], random: Random(1));
      expect(queue.toSet(), {for (final s in songs) s.id});
      expect(queue.length, songs.length);
    });
  });

  group('shuffle', () {
    test('plays everything once, in an order that changes', () {
      final a = SongPicker.shuffle(songs, recent: const [], random: Random(1));
      final b = SongPicker.shuffle(songs, recent: const [], random: Random(2));
      expect(a.toSet(), {for (final s in songs) s.id});
      expect(a.length, songs.length);
      expect(a, isNot(b));
    });

    test('does not open with what the last run opened with', () {
      for (var seed = 0; seed < 40; seed++) {
        expect(SongPicker.shuffle(songs, recent: const ['undercity'], random: Random(seed)).first, isNot('undercity'));
      }
    });

    test('a single song still plays', () {
      expect(SongPicker.shuffle([songs.first], recent: [songs.first.id], random: Random(1)), [songs.first.id]);
    });
  });

  group('reading a run', () {
    test('from the briefing', () {
      expect(RunSetting.of(goal: const RunGoal(GoalType.time, 1800), activity: Activity.walk).walking, isTrue);
      expect(RunSetting.of(goal: const RunGoal(GoalType.time, 3600), activity: Activity.run).long, isTrue);
      expect(RunSetting.of(goal: const RunGoal(GoalType.distance, 10000), activity: Activity.run).long, isTrue);
      expect(RunSetting.of(goal: const RunGoal(GoalType.distance, 5000), activity: Activity.run).long, isFalse);
    });

    RunRecord run(int day, String? song) => RunRecord(
      id: 'r$day',
      startedAt: DateTime(2026, 10, day),
      endedAt: DateTime(2026, 10, day, 1),
      elapsedSeconds: 1800,
      movingSeconds: 1800,
      distanceMeters: 5000,
      calories: 0,
      goal: const RunGoal(GoalType.time, 1800),
      outcome: RunOutcome.success,
      song: song,
    );

    test('recent songs come from the log, latest first, skipping runs with none', () {
      final log = [run(1, 'a'), run(4, 'd'), run(3, null), run(2, 'b'), run(5, 'e')];
      expect(SongPicker.recentSongs(log), ['e', 'd', 'b']);
      expect(SongPicker.recentSongs(const []), isEmpty);
    });

    test('a run keeps its song, and an old run has none', () {
      final saved = RunRecord.fromJson(run(1, 'undercity').toJson());
      expect(saved.song, 'undercity');
      expect(RunRecord.fromJson(run(1, null).toJson()).song, isNull);
    });
  });
}
