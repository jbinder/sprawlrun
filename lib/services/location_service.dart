import 'dart:async';

import 'package:flutter/services.dart';
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

/// Real GPS. geolocator answers whether location is usable at all (service on,
/// permission granted — and asks for it); the fixes themselves come from the
/// app's own channel to the GPS provider.
class GpsLocationSource implements LocationSource {
  static const _gps = EventChannel('io.github.jbinder.sprawlrun/gps');

  StreamSubscription<Object?>? _sub;
  StreamController<GeoFix>? _controller;

  @override
  Future<LocationReadiness> prepare() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationReadiness.serviceDisabled;
    }

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

    // Fixes come from the app's own GPS-provider channel, not from
    // geolocator's stream. geolocator's LocationManager client on Android 12+
    // prefers the ROM's "fused" provider whenever one is registered, and
    // `forceLocationManager` does not change that — it only avoids Play
    // Services. On a de-Googled device the fused provider is whatever the
    // vendor shipped; on the Xperia this was found on, it accepts the request
    // and never delivers a fix, so the run watched a healthy, empty stream for
    // half an hour. Asking the GPS provider by name is what "use AOSP's
    // LocationManager" was always meant to mean. Google Play Services stays
    // out of the build either way — see the `com.google.android.gms`
    // exclusion in android/app/build.gradle.kts.
    //
    // Fixes keep arriving with the screen off because MissionService holds
    // the app in the foreground with the `location` service type. Without some
    // foreground service Android throttles the app to a handful of fixes an
    // hour and the recorded distance quietly collapses.
    _sub = _gps.receiveBroadcastStream().listen(
      (raw) {
        final m = Map<Object?, Object?>.from(raw as Map);
        controller.add(
          GeoFix(
            lat: m['lat']! as double,
            lon: m['lon']! as double,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              m['time']! as int,
              isUtc: true,
            ),
            accuracy: m['accuracy']! as double,
            speed: m['speed']! as double,
            speedAccuracy: m['speedAccuracy']! as double,
          ),
        );
      },
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
