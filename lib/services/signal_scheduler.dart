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
  ///
  /// Only what is still *waiting* is replaced. A signal that has already
  /// arrived and sits unread in the shade stays there: this runs on every
  /// launch, and it used to cancel every id in the range — which also removes
  /// a notification on screen, so opening the app without tapping one swept
  /// away the message the runner had not read yet.
  final Future<void> Function(List<PlannedSignal> signals) schedule;

  /// Clears the app's own signals that are still waiting. Never touches the
  /// run notice, which is posted by `MissionService` outside the plugin, nor a
  /// signal already delivered.
  final Future<void> Function() cancelAll;

  /// Signals the runner tapped in the notification shade. See [SignalTaps].
  final Stream<Signal> taps;

  /// Does nothing, successfully. The default in tests and on any platform
  /// where scheduling is not wired up.
  factory SignalScheduler.noop() => SignalScheduler(
    schedule: (_) async {},
    cancelAll: () async {},
  );

  /// Whether [id] is one of the signal ids, as opposed to anything else the
  /// app posts.
  static bool isSignalId(int id) => id >= SignalPlanner.reminderBase && id < SignalPlanner.debriefBase + 100;

  /// The ids a re-plan cancels: the app's signals still waiting to fire, out
  /// of everything the plugin has pending.
  static List<int> cancellable(Iterable<int> pending) => [for (final id in pending) if (isSignalId(id)) id];

  /// [plan], moved off any notification id still on screen.
  ///
  /// A delivered notification keeps its id until it is dismissed, and a new
  /// signal posted under the same id replaces it when it fires — so even
  /// without being cancelled, an unread message would vanish once the next
  /// plan reused its slot. A clashing signal moves to a free id in its own
  /// band (reminders, noise, debrief), so it can never land on another kind's
  /// range. A band with no free id at all keeps the clash rather than drop a
  /// signal.
  static List<PlannedSignal> sparingShown(List<PlannedSignal> plan, Set<int> shown) {
    if (shown.isEmpty) return plan;
    final taken = {...shown, for (final s in plan) s.id};
    return [
      for (final s in plan)
        if (!shown.contains(s.id))
          s
        else
          () {
            final base = s.id - (s.id - SignalPlanner.reminderBase) % 100;
            for (var id = base; id < base + 100; id++) {
              if (taken.add(id)) return s.withId(id);
            }
            return s;
          }(),
    ];
  }

  static const String reminderChannel = 'signals_reminder';
  static const String ambientChannel = 'signals_ambient';
  static const String debriefChannel = 'signals_debrief';

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
    final taps = SignalTaps();
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
          onDidReceiveNotificationResponse: (response) =>
              taps.deliver(id: response.id, payload: response.payload),
        );
        ready = true;

        // A tap that *started* the process never reaches the callback above:
        // the plugin forwards SELECT_NOTIFICATION through `onNewIntent`, which
        // needs an activity that was already running, and its
        // `onAttachedToActivity` handles only foreground action buttons. Asking
        // for the launch details is the sole route for a cold start — which is
        // the usual case, since a signal arrives hours after the app was last
        // open and Android has long since killed it.
        final launch = await plugin.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp ?? false) {
          final response = launch!.notificationResponse;
          taps.deliver(id: response?.id, payload: response?.payload);
        }
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
      // Its own channel rather than the reminder one, so a runner who wants the
      // weekly readout but not the nudges — or the other way round — can say so
      // in Android's own settings without the app needing a second switch.
      SignalKind.debrief => AndroidNotificationDetails(
        debriefChannel,
        'Weekly debrief',
        channelDescription: 'How your week went, when it closes.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: 'ic_notification',
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

    // Cancels only what is still waiting. By id rather than cancelAll(), so
    // nothing else the app may post is caught in the sweep.
    Future<void> clear() async {
      final List<int> ids;
      try {
        ids = cancellable((await plugin.pendingNotificationRequests()).map((p) => p.id));
      } on PlatformException catch (e) {
        // Without the list, fall back to sweeping the range: a duplicate
        // reminder would be worse than a message cleared from the shade.
        debugPrint('listing pending signals failed, sweeping: $e');
        for (var id = SignalPlanner.reminderBase; id < SignalPlanner.debriefBase + 100; id++) {
          await plugin.cancel(id: id);
        }
        return;
      }
      for (final id in ids) {
        await plugin.cancel(id: id);
      }
    }

    // The signal ids still on screen, so the new plan steers clear of them.
    Future<Set<int>> shown() async {
      try {
        final active = await plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.getActiveNotifications();
        return {for (final n in active ?? const <ActiveNotification>[]) if (n.id != null && isSignalId(n.id!)) n.id!};
      } on PlatformException catch (e) {
        debugPrint('listing shown signals failed: $e');
        return const {};
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
          for (final s in sparingShown(signals, await shown())) {
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

/// Collects notification taps and hands them to the app as a stream.
///
/// Its own class because the delivery rules are the fiddly part and they need
/// testing without a device — the first version of them was written inline in
/// [SignalScheduler.platform], untestable, and was wrong.
///
/// Two rules, both learned the hard way:
///
/// - **A tap can arrive before anything is listening.** A cold start begins
///   with the boot screen, and the launch tap is read as soon as the plugin
///   initialises. Anything that arrives with no listener is held and replayed
///   to the first one.
/// - **The same tap can arrive twice.** A cold start is reported by
///   `getNotificationAppLaunchDetails`, and a warm one by the tap callback; a
///   launch that is somehow both must still show one dialog.
class SignalTaps {
  SignalTaps() {
    _controller.onListen = _drain;
  }

  final _controller = StreamController<Signal>.broadcast();
  final _waiting = <Signal>[];
  final _seen = <String>{};

  Stream<Signal> get stream => _controller.stream;

  /// Accepts a tap, from either route.
  ///
  /// Unreadable payloads are dropped rather than thrown: a notification
  /// scheduled by an older build carries none, and a tap must never be able to
  /// take the app down.
  void deliver({int? id, String? payload}) {
    // Keyed on both, because ids are reused across re-plans. Within one process
    // the same notification cannot be tapped twice — it auto-cancels — so a
    // repeat is always the two routes reporting one tap.
    if (!_seen.add('$id\u0000$payload')) return;

    final signal = SignalScheduler.decodePayload(payload);
    if (signal == null) {
      debugPrint('signal tapped with no readable payload');
      return;
    }
    if (_controller.hasListener) {
      _controller.add(signal);
    } else {
      _waiting.add(signal);
    }
  }

  void _drain() {
    final queued = List.of(_waiting);
    _waiting.clear();
    for (final signal in queued) {
      // A microtask, because adding from inside onListen does not reach the
      // subscription that is still being set up.
      scheduleMicrotask(() {
        if (_controller.hasListener) _controller.add(signal);
      });
    }
  }

  Future<void> close() => _controller.close();
}
