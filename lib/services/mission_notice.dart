import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app's own foreground service, and the notification a run shows.
///
/// Every run has one. It is what holds the app in the foreground: with location
/// granted the service claims the `location` type, which is what keeps fixes
/// arriving once the screen goes off, and without it claims `specialUse`, so a
/// mission with no GPS still cannot be frozen in a pocket halfway through the
/// story.
///
/// geolocator can post a notice of its own, and used to. It is not asked to any
/// more: its text is fixed when the position stream opens, so it could never
/// count a goal down, and two configs would put two notifications on screen for
/// one run.
class MissionNotice {
  const MissionNotice({required this.start, required this.update, required this.stop});

  /// Puts the app in the foreground for the run and posts the first notice.
  final Future<void> Function(String text, {required bool tracking}) start;

  /// Replaces the text in place. Cheap enough to call on every tick.
  final Future<void> Function(String text) update;

  /// Ends it. Safe to call when nothing was ever started.
  final Future<void> Function() stop;

  factory MissionNotice.platform() {
    const channel = MethodChannel('io.github.jbinder.sprawlrun/notifications');

    Future<void> call(String method, [Map<String, Object?>? args]) async {
      if (defaultTargetPlatform != TargetPlatform.android) return;
      try {
        await channel.invokeMethod<void>(method, args);
      } on PlatformException catch (e) {
        // A missing notice is a degraded run, never a failed one.
        debugPrint('$method failed: $e');
      } on MissingPluginException {
        debugPrint('$method unavailable');
      }
    }

    // Remembered from the start call so a later update cannot silently
    // downgrade the service type mid-run.
    var started = false;
    return MissionNotice(
      start: (text, {required bool tracking}) {
        started = tracking;
        return call('startMissionNotice', {'text': text, 'tracking': tracking});
      },
      update: (text) => call('updateMissionNotice', {'text': text, 'tracking': started}),
      stop: () => call('stopMissionNotice'),
    );
  }
}
