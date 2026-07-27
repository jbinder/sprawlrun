import 'dart:math';

/// One position sample, decoupled from the geolocator package so the run
/// engine can be driven by recorded or synthetic fixes in tests.
class GeoFix {
  const GeoFix({
    required this.lat,
    required this.lon,
    required this.timestamp,
    this.accuracy = 5,
    this.speed = 0,
    this.speedAccuracy = 0,
  });

  final double lat;
  final double lon;
  final DateTime timestamp;

  /// Horizontal accuracy in metres. Larger is worse.
  final double accuracy;

  /// Device-reported ground speed in m/s, where available.
  final double speed;
  final double speedAccuracy;
}

abstract final class Geo {
  static const double earthRadiusMeters = 6371008.8;

  /// Great-circle distance in metres.
  ///
  /// Implemented locally rather than via the plugin so distance maths stays
  /// available in unit tests with no platform channels.
  static double distance(double lat1, double lon1, double lat2, double lon2) {
    const toRad = pi / 180.0;
    final dLat = (lat2 - lat1) * toRad;
    final dLon = (lon2 - lon1) * toRad;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * toRad) * cos(lat2 * toRad) * sin(dLon / 2) * sin(dLon / 2);
    return earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}
