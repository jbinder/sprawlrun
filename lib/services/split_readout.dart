/// What the handler's readout says as each kilometre or mile passes on a free
/// run.
///
/// Written for the ear, not the screen: `5:41` is ambiguous spoken aloud —
/// some engines read it as a time of day — so durations are spelled out in
/// words a speech engine cannot misread.
abstract final class SplitReadout {
  /// `Kilometre 3. Split 5 minutes 41. Total 17 minutes 4.`
  static String line({
    required int count,
    required bool metric,
    required double splitSeconds,
    required double totalSeconds,
  }) =>
      '${metric ? 'Kilometre' : 'Mile'} $count. Split ${spoken(splitSeconds)}. Total ${spoken(totalSeconds)}.';

  /// A duration as it should be said: `41 seconds`, `5 minutes 41`,
  /// `6 minutes`, `1 hour 2 minutes`. Seconds are dropped past the hour; at
  /// that length nobody is pacing to the second.
  static String spoken(double seconds) {
    final total = seconds.isFinite && seconds > 0 ? seconds.round() : 0;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    String unit(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

    if (h > 0) return m == 0 ? unit(h, 'hour') : '${unit(h, 'hour')} ${unit(m, 'minute')}';
    if (m == 0) return unit(s, 'second');
    return s == 0 ? unit(m, 'minute') : '${unit(m, 'minute')} $s';
  }
}
