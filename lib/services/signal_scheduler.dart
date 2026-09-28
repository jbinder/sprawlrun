import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/mission.dart';
import 'signal_planner.dart';

/// Hands planned signals to the platform, and takes them back again.
///
/// The closure-port shape the rest of the app uses for platform work: a test
/// injects its own closures, and a device without the plugin degrades to doing
/// nothing rather than throwing. Deciding *what* to send lives in
/// [SignalPlanner]; this only delivers.
class SignalScheduler {
  const SignalScheduler({
    required this.schedule,
    required this.cancelAll,
    this.taps = const Stream.empty(),
  });

  /// Replaces everything previously scheduled with [signals].
  final Future<void> Function(List<PlannedSignal> signals) schedule;

  /// Clears the app's own signals. Never touches the run notice, which is
  /// posted by `MissionService` outside the plugin.
  final Future<void> Function() cancelAll;

  /// Signals the runner tapped in the notification shade.
  ///
  /// Deliberately a single-subscription stream, so a tap that *launched* the
  /// app is buffered until something is around to show it. A broadcast stream
  /// would drop it: the tap is delivered while the plugin initialises, long
  /// before the UI has finished loading the run log.
  final Stream<Signal> taps;

  /// Does nothing, successfully. The default in tests and on any platform
  /// where scheduling is not wired up.
  factory SignalScheduler.noop() => SignalScheduler(
    schedule: (_) async {},
    cancelAll: () async {},
  );

  static const String reminderChannel = 'signals_reminder';
  static const String ambientChannel = 'signals_ambient';

  /// What a notification carries so a tap can be shown in full.
  ///
  /// The planned schedule is never persisted, and the text is fixed when the
  /// notification is scheduled rather than when it fires, so the payload is the
  /// only route from a tap back to what was said.
  static String encodePayload(Signal signal) =>
      jsonEncode({'from': signal.from, 'text': signal.text});

  /// The reverse, and forgiving: null for anything that is not one of ours.
  /// A signal scheduled by an older build, or a payload from somewhere else
  /// entirely, must not take the app down on a tap.
  static Signal? decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      final from = decoded['from'];
      final text = decoded['text'];
      if (from is! String || text is! String || text.isEmpty) return null;
      return Signal(from: from, text: text);
    } on FormatException {
      return null;
    }
  }

  factory SignalScheduler.platform() {
    if (defaultTargetPlatform != TargetPlatform.android) return SignalScheduler.noop();

    final plugin = FlutterLocalNotificationsPlugin();
    final taps = StreamController<Signal>();
    var ready = false;

    // Android delivers a tap that launched the app during `initialize`, which
    // is why the controller buffers rather than broadcasts. Using
    // `getNotificationAppLaunchDetails` as well would report the same tap
    // twice, so this is the only route in.
    void onTap(NotificationResponse response) {
      final signal = decodePayload(response.payload);
      if (signal == null) {
        debugPrint('signal tapped with no readable payload');
        return;
      }
      taps.add(signal);
    }

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
          onDidReceiveNotificationResponse: onTap,
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
    AndroidNotificationDetails detailsFor(PlannedSignal s) => switch (s.kind) {
      SignalKind.reminder => AndroidNotificationDetails(
        reminderChannel,
        'Reminders',
        channelDescription: 'Your handler, asking whether you are running today.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: 'ic_notification',
        // Without this Android shows one line and truncates the rest. These
        // run to 180 characters, so most of a signal was being cut.
        styleInformation: BigTextStyleInformation(s.text, contentTitle: s.from),
      ),
      SignalKind.ambient => AndroidNotificationDetails(
        ambientChannel,
        'Signal noise',
        channelDescription: 'Traffic from the Sprawl. Silent.',
        importance: Importance.low,
        priority: Priority.low,
        enableVibration: false,
        playSound: false,
        icon: 'ic_notification',
        styleInformation: BigTextStyleInformation(s.text, contentTitle: s.from),
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
      taps: taps.stream,
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
              notificationDetails: NotificationDetails(android: detailsFor(s)),
              // The plan is never persisted, so at tap time the app has no
              // other way back to what this one said.
              payload: encodePayload(Signal(from: s.from, text: s.text)),
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
