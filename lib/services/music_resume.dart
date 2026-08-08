import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Puts the runner's music back on when Android's audio-focus handoff fails.
///
/// Taking transient focus is supposed to be a loan: the music app receives
/// `AUDIOFOCUS_LOSS_TRANSIENT`, pauses, and resumes when it gets
/// `AUDIOFOCUS_GAIN` back. Several popular players only honour that for short
/// interruptions — after a long one they treat the pause as permanent and stay
/// silent. Nothing an app can do to its own focus request changes that; the
/// only remedy from outside the player is a media-button PLAY, which is what
/// this sends.
///
/// It fires narrowly on purpose. The nudge happens only when music was
/// demonstrably playing immediately before the interlude and is still not
/// playing a couple of seconds after focus went back, so it cannot start
/// something the runner never had going. It can still fight a runner who
/// deliberately paused their music *during* a transmission, which is why it is
/// a setting rather than unconditional behaviour.
class MusicResumeGuard {
  MusicResumeGuard({
    required this.isMusicActive,
    required this.sendPlay,
    this.settle = const Duration(milliseconds: 1800),
    Future<void> Function(Duration)? wait,
  }) : _wait = wait ?? ((d) => Future<void>.delayed(d));

  /// Whether anything is currently playing on the music stream.
  final Future<bool> Function() isMusicActive;

  /// Dispatches a media-button PLAY to whichever player last held the session.
  final Future<void> Function() sendPlay;

  /// How long to give the player to resume on its own before nudging it.
  /// Long enough that a well-behaved player is never touched.
  final Duration settle;

  final Future<void> Function(Duration) _wait;

  bool _wasPlaying = false;

  /// Bumped by every interruption. A nudge that is still inside its settle
  /// window when the next transmission begins is stale: pressing play then
  /// would restart the music underneath the handler's voice, which is exactly
  /// what the whole mechanism exists to avoid.
  int _generation = 0;

  /// Call immediately before taking audio focus.
  Future<void> beforeInterrupt() async {
    _generation++;
    try {
      _wasPlaying = await isMusicActive();
    } on Object catch (e) {
      debugPrint('Music state unavailable: $e');
      _wasPlaying = false;
    }
  }

  /// Call immediately after handing audio focus back. Returns true if it had to
  /// nudge the player.
  ///
  /// Does nothing at all when nothing was playing to begin with — the common
  /// case of a runner with no music of their own costs one bool check.
  Future<bool> afterInterrupt() async {
    if (!_wasPlaying) return false;
    _wasPlaying = false;
    final mine = _generation;
    try {
      await _wait(settle);
      if (mine != _generation) return false;
      if (await isMusicActive()) return false;
      if (mine != _generation) return false;
      await sendPlay();
      return true;
    } on Object catch (e) {
      debugPrint('Music resume nudge failed: $e');
      return false;
    }
  }

  /// Forgets any pending state, in flight or not — used when a run ends and no
  /// nudge should arrive after the fact.
  void cancel() {
    _wasPlaying = false;
    _generation++;
  }

  /// The production wiring, over the platform channel implemented in
  /// MainActivity. Android-only; every other platform reports nothing playing,
  /// which disables the guard rather than breaking it.
  factory MusicResumeGuard.platform() {
    const channel = MethodChannel('io.github.jbinder.sprawlrun/audio');
    return MusicResumeGuard(
      isMusicActive: () async =>
          defaultTargetPlatform == TargetPlatform.android &&
          (await channel.invokeMethod<bool>('isMusicActive') ?? false),
      sendPlay: () => channel.invokeMethod<void>('resumeMusic'),
    );
  }
}
