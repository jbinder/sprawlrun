import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether Android may stop the app to save battery, and asking it not to.
///
/// Running a foreground service is meant to keep a run alive, and on a real
/// device it was not enough: a vendor battery manager killed a run at 4.6 of
/// 5 km. An app left out of battery optimisation is spared that. Android asks
/// the runner with its own one-tap dialog; the app asks once before a run and
/// offers it again in Settings, and never makes it a condition of anything.
class BatteryOptimization {
  const BatteryOptimization({required this.optimized, required this.requestExemption});

  /// True while Android may stop the app to save battery. False wherever
  /// there is no such thing — other platforms, old Android, a missing channel.
  final Future<bool> Function() optimized;

  /// Shows Android's dialog and completes once it is closed, with whether the
  /// app is now exempt.
  final Future<bool> Function() requestExemption;

  /// For tests and platforms with nothing to ask.
  static final BatteryOptimization none = BatteryOptimization(
    optimized: () async => false,
    requestExemption: () async => true,
  );

  factory BatteryOptimization.platform() {
    if (defaultTargetPlatform != TargetPlatform.android) return none;
    const channel = MethodChannel('io.github.jbinder.sprawlrun/notifications');
    Future<bool> call(String method, {required bool fallback}) async {
      try {
        return await channel.invokeMethod<bool>(method) ?? fallback;
      } on PlatformException catch (e) {
        debugPrint('$method failed: $e');
        return fallback;
      } on MissingPluginException {
        return fallback;
      }
    }

    return BatteryOptimization(
      optimized: () => call('batteryOptimized', fallback: false),
      requestExemption: () => call('requestBatteryExemption', fallback: false),
    );
  }
}
