import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/mission.dart';
import '../screens/timeline_screen.dart';
import '../state/app_state.dart';

/// Opens the timeline at a signal the runner tapped in the notification shade.
///
/// The timeline rather than a popup over whatever screen was showing: the
/// message is there in full, in context — what came before it, the run it
/// was about — and it stays readable after it is dismissed, which a popup
/// never was.
class SignalWatcher extends StatefulWidget {
  const SignalWatcher({super.key, required this.child});

  final Widget child;

  @override
  State<SignalWatcher> createState() => _SignalWatcherState();
}

class _SignalWatcherState extends State<SignalWatcher> {
  StreamSubscription<Signal>? _sub;

  @override
  void initState() {
    super.initState();
    // read, not watch: the stream is the same one for the life of the app, and
    // this must subscribe exactly once. A tap that launched the app is held by
    // the stream until this subscribes.
    _sub = context.read<AppState>().signalTaps.listen(_open);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _open(Signal signal) {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final route = MaterialPageRoute<void>(
      settings: const RouteSettings(name: TimelineScreen.routeName),
      builder: (_) => TimelineScreen(focus: signal),
    );

    // Pushed on top of whatever is showing — a run in progress included, which
    // must never be popped out from under the runner — but a timeline that is
    // already open is replaced rather than stacked.
    var onTimeline = false;
    navigator.popUntil((top) {
      onTimeline = top.settings.name == TimelineScreen.routeName;
      return true;
    });
    if (onTimeline) {
      navigator.pushReplacement(route);
    } else {
      navigator.push(route);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
