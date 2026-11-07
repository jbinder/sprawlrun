import 'dart:math';

import '../audio/song.dart';
import '../models/goal.dart';
import '../models/mission.dart';
import '../models/run_record.dart';

/// What a run is about to be, as far as choosing its music goes.
class RunSetting {
  const RunSetting({this.walking = false, this.chases = 0, this.finale = false, this.long = false});

  /// Reads it off what the briefing knows.
  factory RunSetting.of({Mission? mission, required RunGoal goal, required Activity activity}) => RunSetting(
    walking: activity == Activity.walk,
    chases: mission?.chaseBeats.length ?? 0,
    // Only the last mission of a pack carries an epilogue.
    finale: mission?.epilogue != null,
    long: goal.isTime ? goal.value >= longSeconds : goal.value >= longMeters,
  );

  static const double longSeconds = 3600, longMeters = 10000;

  /// A mission with this many pursuits in it is mostly running away.
  static const int chaseHeavy = 3;

  final bool walking, finale, long;
  final int chases;
}

/// Puts the songs in the order a run should hear them. Pure: told the songs, the
/// setting and what was played lately, and handed its randomness.
abstract final class SongPicker {
  /// How far back "played lately" reaches, and what it costs a song. A good match
  /// should beat a song heard last time only if there is no other match.
  static const int _recentRuns = 3;
  static const List<int> _recentCost = [8, 4, 2];
  static const int _matchWorth = 10, _clashCost = 10;

  /// Every song once, in random order, not opening with the last one played.
  static List<String> shuffle(List<Song> songs, {required List<String> recent, required Random random}) {
    final ids = [for (final s in songs) s.id]..shuffle(random);
    if (ids.length > 1 && recent.isNotEmpty && ids.first == recent.first) {
      ids.add(ids.removeAt(0));
    }
    return ids;
  }

  /// Every song once, the one that suits [setting] best first. What comes after
  /// it is what suits it next, so a long run stays in character.
  static List<String> bestMatch(
    List<Song> songs, {
    required RunSetting setting,
    required List<String> recent,
    required Random random,
  }) {
    // Ties fall to chance, so equally good songs take turns.
    final scored = [
      for (final song in songs) (id: song.id, score: _score(song, setting, recent), tie: random.nextDouble()),
    ]..sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.tie.compareTo(b.tie);
    });
    return [for (final s in scored) s.id];
  }

  /// The songs of recent runs, latest first, from the log. Runs without a song
  /// are skipped rather than counted: they say nothing about what was heard.
  static List<String> recentSongs(List<RunRecord> log) {
    final played = [
      for (final run in log)
        if (run.song != null) run,
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return [for (final run in played.take(_recentRuns)) run.song!];
  }

  static int _score(Song song, RunSetting setting, List<String> recent) {
    final (wanted, unwanted) = _moods(setting);
    final moods = song.moods.toSet();
    var score = 0;
    if (moods.intersection(wanted).isNotEmpty) score += _matchWorth;
    if (moods.intersection(unwanted).isNotEmpty) score -= _clashCost;
    final last = recent.indexOf(song.id);
    if (last >= 0 && last < _recentCost.length) score -= _recentCost[last];
    return score;
  }

  /// A walk comes first because it has no business with a pursuit soundtrack,
  /// whatever the mission holds.
  static (Set<String>, Set<String>) _moods(RunSetting setting) {
    if (setting.walking) return (const {'atmospheric', 'melancholic'}, const {'aggressive', 'bombastic'});
    if (setting.chases >= RunSetting.chaseHeavy) return (const {'aggressive', 'dark', 'tense'}, const {'melancholic'});
    if (setting.finale || setting.long) return (const {'bombastic'}, const {'melancholic'});
    return (const {'uplifting', 'retro', 'playful'}, const {'bombastic', 'aggressive', 'melancholic'});
  }
}
