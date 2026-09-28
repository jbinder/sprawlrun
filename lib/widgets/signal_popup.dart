import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/mission.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import 'panels.dart';

/// Shows a tapped signal in full.
///
/// The notification shade truncates, and dismissing one puts it beyond reach —
/// there is no inbox by design. Tapping is the way back to the whole line, and
/// this is where it lands.
class SignalWatcher extends StatefulWidget {
  const SignalWatcher({super.key, required this.child});

  final Widget child;

  @override
  State<SignalWatcher> createState() => _SignalWatcherState();
}

class _SignalWatcherState extends State<SignalWatcher> {
  StreamSubscription<Signal>? _sub;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    // read, not watch: the stream is the same one for the life of the app, and
    // this must subscribe exactly once. The stream buffers, so a tap that
    // launched the app is still waiting here.
    _sub = context.read<AppState>().signalTaps.listen(_show);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _show(Signal signal) async {
    // Two taps in quick succession would otherwise stack dialogues on top of
    // each other, and the runner would have to dismiss both.
    if (_showing || !mounted) return;
    _showing = true;
    await showDialog<void>(
      context: context,
      builder: (_) => SignalDialog(signal: signal),
    );
    _showing = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// One signal, read in full. Nothing is kept: closing it is the end of it.
class SignalDialog extends StatelessWidget {
  const SignalDialog({super.key, required this.signal});

  final Signal signal;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: NeonPanel(
        accent: Cy.magenta,
        lit: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wifi_tethering, size: 16, color: Cy.magenta),
                const SizedBox(width: 9),
                Expanded(
                  child: Text('INCOMING', style: CyType.label(size: 10, color: Cy.magenta)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(signal.from.toUpperCase(), style: CyType.display(size: 16, color: Cy.ink)),
            const SizedBox(height: 10),
            Text(signal.text, style: CyType.body(size: 14, color: Cy.ghost, height: 1.5)),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: CyberButton(
                label: 'CLOSE',
                style: CyberButtonStyle.ghost,
                dense: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
