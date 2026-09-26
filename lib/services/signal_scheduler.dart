import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'signal_planner.dart';

/// Hands planned signals to the platform, and takes them back again.
///
/// The closure-port shape the rest of the app uses for platform work: a test
/// injects its own closures, and a device without the plugin degrades to doing
/// nothing rather than throwing. Deciding *what* to send lives in
/// [SignalPlanner]; this only delivers.
class SignalScheduler {
  const SignalScheduler({required this.schedule, required this.cancelAll});

  /// Replaces everything previously scheduled with [signals].
  final Future<void> Function(List<PlannedSignal> signals) schedule;

  /// Clears the app's own signals. Never touches the run notice, which is
  /// posted by `MissionService` outside the plugin.
  final Future<void> Function() cancelAll;

  /// Does nothing, successfully. The default in tests and on any platform
  /// where scheduling is not wired up.
  factory SignalScheduler.noop() => SignalScheduler(
    schedule: (_) async {},
    cancelAll: () async {},
  );

  static const String reminderChannel = 'signals_reminder';
  static const String ambientChannel = 'signals_ambient';

  factory SignalScheduler.platform() {
    if (defaultTargetPlatform != TargetPlatform.android) return SignalScheduler.noop();

    final plugin = FlutterLocalNotificationsPlugin();
    var ready = false;

    Future<bool> ensureReady() async {
      if (ready) return true;
      try {
        // The database is needed for TZDateTime to exist at all. The zone it
        // defaults to is UTC, and that is fine: every signal is scheduled as
        // an absolute instant converted from a local DateTime, so the moment
        // is preserved whatever zone expresses it. Reading the device's real
        // zone would cost another dependency and buy nothing, since no
        // signal repeats on a wall-clock rule.
        tzdata.initializeTimeZones();
        await plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('ic_notification'),
          ),
        );
        ready = true;
      } on Object catch (e) {
        debugPrint('signal scheduler unavailable: $e');
      }
      return ready;
    }

    // The channels themselves are created by MainActivity at launch, because
    // importance is frozen at creation and getting it right once matters more
    // than letting the plugin invent one.
    AndroidNotificationDetails detailsFor(SignalKind kind) => switch (kind) {
      SignalKind.reminder => const AndroidNotificationDetails(
        reminderChannel,
        'Reminders',
        channelDescription: 'Your handler, asking whether you are running today.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: 'ic_notification',
      ),
      SignalKind.ambient => const AndroidNotificationDetails(
        ambientChannel,
        'Signal noise',
        channelDescription: 'Traffic from the Sprawl. Silent.',
        importance: Importance.low,
        priority: Priority.low,
        enableVibration: false,
        playSound: false,
        icon: 'ic_notification',
      ),
    };

    Future<void> clear() async {
      // By id rather than cancelAll(), so nothing else the app may post is
      // caught in the sweep.
      for (var id = SignalPlanner.reminderBase; id < SignalPlanner.ambientBase + 100; id++) {
        await plugin.cancel(id: id);
      }
    }

    return SignalScheduler(
      cancelAll: () async {
        if (!await ensureReady()) return;
        try {
          await clear();
        } on PlatformException catch (e) {
          debugPrint('cancelling signals failed: $e');
        }
      },
      schedule: (signals) async {
        if (!await ensureReady()) return;
        try {
          await clear();
          for (final s in signals) {
            await plugin.zonedSchedule(
              id: s.id,
              title: s.from,
              body: s.text,
              scheduledDate: tz.TZDateTime.from(s.at, tz.UTC),
              notificationDetails: NotificationDetails(android: detailsFor(s.kind)),
              // Inexact on purpose: exact alarms need SCHEDULE_EXACT_ALARM,
              // which is a permission this app has no business asking for.
              // A reminder a few minutes late is still a reminder.
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            );
          }
        } on PlatformException catch (e) {
          // A missed reminder is a disappointment, never a crash.
          debugPrint('scheduling signals failed: $e');
        } on MissingPluginException {
          debugPrint('signal scheduling unavailable');
        }
      },
    );
  }
}
