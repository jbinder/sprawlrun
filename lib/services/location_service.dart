import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'geo.dart';

enum LocationReadiness { ready, serviceDisabled, denied, deniedForever }

/// Anything that can produce position fixes. The run engine only ever sees
/// this, which keeps it testable without a GPS.
abstract class LocationSource {
  Stream<GeoFix> fixes();
  Future<LocationReadiness> prepare();
  Future<void> stop();
}

/// Real GPS, via geolocator.
class GpsLocationSource implements LocationSource {
  StreamSubscription<Position>? _sub;
  StreamController<GeoFix>? _controller;

  @override
  Future<LocationReadiness> prepare() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationReadiness.serviceDisabled;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.denied => LocationReadiness.denied,
      LocationPermission.deniedForever => LocationReadiness.deniedForever,
      _ => LocationReadiness.ready,
    };
  }

  @override
  Stream<GeoFix> fixes() {
    _controller?.close();
    final controller = StreamController<GeoFix>.broadcast(onCancel: stop);
    _controller = controller;

    // A foreground service is what keeps fixes arriving with the screen off —
    // without it Android throttles the app to a fix every few minutes and the
    // recorded distance quietly collapses.
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      // Use AOSP's LocationManager rather than the Play Services fused
      // provider. Google Play Services is proprietary, which would bar the app
      // from F-Droid and make it dependent on a Google component on de-Googled
      // ROMs. The build also strips the library outright — see the
      // `com.google.android.gms` exclusion in android/app/build.gradle.kts.
      //
      // The cost is a slightly slower first fix and marginally worse battery
      // use, because the fused provider blends in sensors and cell data. For a
      // run that lasts half an hour with the GPS on regardless, that is not a
      // trade worth making.
      forceLocationManager: true,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'SPRAWL//RUN',
        notificationText: 'Mission active — tracking your route.',
        notificationChannelName: 'Active mission',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (p) => controller.add(
        GeoFix(
          lat: p.latitude,
          lon: p.longitude,
          timestamp: p.timestamp,
          accuracy: p.accuracy,
          speed: p.speed,
          speedAccuracy: p.speedAccuracy,
        ),
      ),
      onError: controller.addError,
      cancelOnError: false,
    );

    return controller.stream;
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _controller?.close();
    _controller = null;
  }
}
