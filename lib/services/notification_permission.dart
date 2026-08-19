import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asks for POST_NOTIFICATIONS, which is what makes the mission notification
/// visible while a run is tracking.
///
/// The notification itself is posted by geolocator's foreground service, not by
/// this app, so no plugin here ever asks for the permission. Android 13 made it
/// a runtime grant: without it the service still runs and the run still records
/// — only the ongoing "Mission active" notice is suppressed, which leaves the
/// runner with no sign that anything is tracking with the screen off.
///
/// Declining is harmless and is never asked again by the platform after the
/// second refusal, so this is fire-and-forget at the start of a run rather than
/// a gate on anything.
class NotificationPermission {
  const NotificationPermission({required this.request});

  /// Returns true when notifications may be posted — including on every
  /// platform and Android version where the permission does not exist.
  final Future<bool> Function() request;

  factory NotificationPermission.platform() {
    const channel = MethodChannel('io.github.jbinder.sprawlrun/notifications');
    return NotificationPermission(
      request: () async {
        if (defaultTargetPlatform != TargetPlatform.android) return true;
        try {
          return await channel.invokeMethod<bool>('requestPermission') ?? false;
        } on PlatformException catch (e) {
          debugPrint('notification permission request failed: $e');
          return false;
        } on MissingPluginException {
          return false;
        }
      },
    );
  }
}
