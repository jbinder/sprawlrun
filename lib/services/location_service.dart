import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'geo.dart';

/// Why position fixes are not going to arrive, if they are not.
///
/// [gpsDisabled] is its own case because nothing else catches it:
/// `Geolocator.isLocationServiceEnabled()` answers "is location on at all", and
/// Android's battery-saver location mode leaves network location on while
/// switching the GPS provider off. Permission is granted, the service is
/// enabled, and the provider delivers nothing — which recorded a two-hour run
/// as time-only with no warning before this case existed.
enum LocationReadiness { ready, serviceDisabled, denied, deniedForever, gpsDisabled }

/// Raised on the fix stream when fixes have stopped being possible.
///
/// The platform reports this both when the provider is already off at
/// subscription and when the runner switches it off mid-run, so it can arrive
/// long after [LocationSource.prepare] said everything was in order.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.readiness);

  final LocationReadiness readiness;

  @override
  String toString() => 'LocationUnavailable(${readiness.name})';
}

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
    // vendor shipped; on the device this was found on, it accepts the request
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
      // Translated rather than passed through, so the engine can tell "the GPS
      // provider is off" from an ordinary transient fix error and tell the
      // runner about it. The codes are GpsStream.kt's.
      onError: (Object e) => controller.addError(switch (e) {
        PlatformException(code: 'gpsDisabled') => const LocationUnavailable(LocationReadiness.gpsDisabled),
        PlatformException(code: 'denied') => const LocationUnavailable(LocationReadiness.denied),
        _ => e,
      }),
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
