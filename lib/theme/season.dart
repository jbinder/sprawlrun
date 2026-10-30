import 'package:flutter/foundation.dart';

import 'cyber_palette.dart';

/// A stretch of the year when the city dresses differently: its own palette,
/// backdrop, text effect, sounds, greeting and — through a pack that names it
/// (`"season"` in docs/MISSION_PACKS.md) — its own operations and handler
/// traffic.
///
/// Which one is in force is worked out from [appNow] and the runner's
/// `Profile.seasonalEvents`; nothing about it is stored.
enum Season {
  samhain;

  /// The id a pack names in its `season` field.
  String get id => name;

  String get title => switch (this) {
    Season.samhain => 'SAMHAIN PROTOCOL',
  };

  CyPalette get palette => switch (this) {
    Season.samhain => CyPalette.samhain,
  };

  /// Folder under `assets/sfx/` holding this season's versions of the shipped
  /// effects. A name with no version there plays the ordinary one.
  String get sfxFolder => name;

  /// Effects [sfxFolder] has a version of. Listed rather than probed, since
  /// asking the asset bundle costs a lookup per sound mid-run.
  Set<String> get sfxVariants => switch (this) {
    Season.samhain => const {
      'drone',
      'comm_open',
      'comm_close',
      'chase_start',
      'chase_clear',
      'goal_reached',
      'unlock',
      'mission_success',
    },
  };

  /// First and last day, inclusive, as month and day: the window recurs.
  ({int month, int day}) get from => switch (this) {
    // Three weeks and a bit: a runner out two or three times a week gets the
    // six to ten runs the four operations need with slack for a missed week.
    Season.samhain => (month: 10, day: 10),
  };

  ({int month, int day}) get until => switch (this) {
    // All Souls' Day: the dead get one more night after All Hallows.
    Season.samhain => (month: 11, day: 2),
  };

  /// Whether [t] falls inside this season's window.
  bool contains(DateTime t) {
    final key = t.month * 100 + t.day;
    return key >= from.month * 100 + from.day && key <= until.month * 100 + until.day;
  }

  /// Whole days left after [t]'s, counting the last day as zero.
  int daysLeft(DateTime t) =>
      DateTime.utc(t.year, until.month, until.day).difference(DateTime.utc(t.year, t.month, t.day)).inDays;

  /// The season [t] falls in, if any.
  static Season? at(DateTime t) {
    for (final s in Season.values) {
      if (s.contains(t)) return s;
    }
    return null;
  }

  /// The season the app is drawn in right now. Null year-round.
  static Season? get active => _active;
  static Season? _active;

  /// Puts [season]'s palette in force, or [otherwise] — the runner's own
  /// look — when there is none. Returns whether anything changed; colours are
  /// read at build time, so whoever calls this rebuilds what lies beneath
  /// it — `SprawlRunApp` does.
  static bool apply(Season? season, {CyPalette otherwise = CyPalette.standard}) {
    final palette = season?.palette ?? otherwise;
    if (season == _active && identical(palette, Cy.palette)) return false;
    _active = season;
    Cy.use(palette);
    return true;
  }

  /// For tests: back to the year-round look without a widget tree.
  @visibleForTesting
  static void debugReset() {
    _active = null;
    Cy.use(CyPalette.standard);
  }
}
