import '../models/profile.dart';
import '../l10n/l10n.dart';

/// Display formatting. Every number the runner sees goes through here so units
/// and rounding are consistent across the HUD, the summary and the stats.
abstract final class Fmt {
  /// `12:34` under an hour, `1:02:03` over it.
  static String clock(double seconds) {
    final total = seconds.isFinite && seconds > 0 ? seconds.round() : 0;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// Compact duration for lists: `48m`, `1h 12m`.
  static String shortDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '${minutes}m';
    return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
  }

  static String distance(double meters, UnitSystem units) {
    if (units == UnitSystem.imperial) {
      final miles = meters / 1609.344;
      return miles < 10 ? miles.toStringAsFixed(2) : miles.toStringAsFixed(1);
    }
    final km = meters / 1000;
    return km < 10 ? km.toStringAsFixed(2) : km.toStringAsFixed(1);
  }

  static String distanceUnit(UnitSystem units) => units == UnitSystem.imperial ? 'mi' : 'km';

  static String distanceWithUnit(double meters, UnitSystem units) =>
      '${distance(meters, units)} ${distanceUnit(units)}';

  /// `5:42` per km (or per mile). Returns `--:--` when there is no useful pace.
  static String pace(double secondsPerKm, UnitSystem units) {
    if (secondsPerKm <= 0 || !secondsPerKm.isFinite) return '--:--';
    final perUnit = units == UnitSystem.imperial ? secondsPerKm * 1.609344 : secondsPerKm;
    if (perUnit > 3600) return '--:--';
    final m = perUnit ~/ 60;
    final s = (perUnit % 60).round();
    // 59.6 s rounds to 60 and would render as 5:60.
    return s == 60 ? '${m + 1}:00' : '$m:${s.toString().padLeft(2, '0')}';
  }

  static String paceUnit(UnitSystem units) => '/${distanceUnit(units)}';

  static String calories(double kcal) => kcal.round().toString();

  /// `2 500` rather than `2500` — easier to read at a glance mid-run.
  static String grouped(num value) {
    final s = value.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static String weight(double kg, UnitSystem units) =>
      units == UnitSystem.imperial ? '${(kg * 2.20462).round()} lb' : '${kg.round()} kg';

  static String _month(DateTime d) => l10n.monthShort('${d.month}');

  static String date(DateTime d) => '${d.day.toString().padLeft(2, '0')} ${_month(d)}';

  static String dateTime(DateTime d) =>
      '${date(d)} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String weekday(DateTime d) => l10n.weekdayShort('${d.weekday}');

  static String monthYear(DateTime d) => '${_month(d)} ${d.year}';

  /// `15 – 21 SEP 2026`, or `29 SEP – 05 OCT 2026` when the span crosses a
  /// month. Both ends are inclusive.
  static String dateRange(DateTime from, DateTime to) {
    final year = to.year;
    if (from.year == to.year && from.month == to.month) {
      return '${_two(from.day)} – ${_two(to.day)} ${_month(to)} $year';
    }
    return '${date(from)} – ${date(to)} $year';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String weekdayInitial(DateTime d) => l10n.weekdayInitial('${d.weekday}');

  /// `today`, `yesterday`, `12 days ago`, `3 months ago` — for the age of
  /// something the runner did, where the exact date matters less than whether it
  /// was recent.
  static String ago(Duration d) {
    if (d.inDays >= 365) return l10n.agoYears(d.inDays ~/ 365);
    if (d.inDays >= 60) return l10n.agoMonths(d.inDays ~/ 30);
    if (d.inDays >= 2) return l10n.agoDays(d.inDays);
    if (d.inDays == 1) return l10n.agoYesterday;
    return l10n.agoToday;
  }

  /// `3d 04h` — used for "this week closes in".
  static String countdown(Duration d) {
    if (d.isNegative) return l10n.countdownHours('0');
    if (d.inDays > 0) return l10n.countdownDaysHours('${d.inDays}', (d.inHours % 24).toString().padLeft(2, '0'));
    if (d.inHours > 0) return l10n.countdownHoursMinutes('${d.inHours}', (d.inMinutes % 60).toString().padLeft(2, '0'));
    return l10n.countdownMinutes('${d.inMinutes}');
  }
}
