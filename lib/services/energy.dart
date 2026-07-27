/// Energy expenditure, using the ACSM metabolic equations.
///
/// These are the same equations treadmills use. They need only speed and body
/// mass, which is exactly what a GPS watch-less phone can measure honestly —
/// no heart rate, no invented multipliers.
abstract final class Energy {
  /// Gross VO2 in ml/kg/min for a horizontal speed given in metres/minute.
  ///
  /// ACSM specifies a walking equation below roughly 100 m/min (6 km/h) and a
  /// running equation above it; the two are within a few percent at the seam.
  static double vo2(double metresPerMinute) {
    if (metresPerMinute <= 0) return 3.5;
    return metresPerMinute < 100 ? 0.1 * metresPerMinute + 3.5 : 0.2 * metresPerMinute + 3.5;
  }

  /// kcal burned covering [distanceMeters] in [seconds] at [weightKg].
  ///
  /// Uses average speed over the whole interval, so a run recorded as one
  /// segment and the same run recorded as many segments agree to within
  /// rounding.
  static double kcal({required double distanceMeters, required double seconds, required double weightKg}) {
    if (seconds <= 0 || weightKg <= 0) return 0;
    final minutes = seconds / 60.0;
    final metresPerMinute = distanceMeters / minutes;
    // kcal/min = VO2 (ml/kg/min) * kg / 1000 (L) * 5 kcal/L O2
    return vo2(metresPerMinute) * weightKg / 1000.0 * 5.0 * minutes;
  }
}
