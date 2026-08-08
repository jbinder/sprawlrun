import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/services/music_resume.dart';

/// Drives the guard without waiting for real time, and lets a test decide what
/// the music stream is doing at each check.
class FakeMusicStream {
  FakeMusicStream(this.states);

  /// Answers to successive isMusicActive() calls.
  final List<bool> states;
  int asked = 0;
  int plays = 0;

  Future<bool> isActive() async {
    final value = states[asked.clamp(0, states.length - 1)];
    asked++;
    return value;
  }

  Future<void> play() async => plays++;
}

MusicResumeGuard guardFor(FakeMusicStream stream) => MusicResumeGuard(
  isMusicActive: stream.isActive,
  sendPlay: stream.play,
  wait: (_) async {},
);

void main() {
  test('presses play when music was on and did not come back', () async {
    // Playing before the beat, still silent after the settle window.
    final stream = FakeMusicStream([true, false]);
    final guard = guardFor(stream);

    await guard.beforeInterrupt();
    expect(await guard.afterInterrupt(), isTrue);
    expect(stream.plays, 1);
  });

  test('leaves a player that resumed on its own alone', () async {
    final stream = FakeMusicStream([true, true]);
    final guard = guardFor(stream);

    await guard.beforeInterrupt();
    expect(await guard.afterInterrupt(), isFalse);
    expect(stream.plays, 0);
  });

  test('never starts music the runner did not have playing', () async {
    final stream = FakeMusicStream([false, false]);
    final guard = guardFor(stream);

    await guard.beforeInterrupt();
    expect(await guard.afterInterrupt(), isFalse);
    expect(stream.plays, 0);
    expect(stream.asked, 1, reason: 'with nothing playing there is nothing to check afterwards');
  });

  test('does not fire twice for one interruption', () async {
    final stream = FakeMusicStream([true, false, false]);
    final guard = guardFor(stream);

    await guard.beforeInterrupt();
    await guard.afterInterrupt();
    expect(await guard.afterInterrupt(), isFalse, reason: 'the second release has nothing pending');
    expect(stream.plays, 1);
  });

  test('a nudge still pending when the next beat starts is abandoned', () async {
    // The player did not come back, but by the time the settle window elapsed
    // the next transmission had already taken focus. Pressing play now would
    // restart the music under the handler's voice.
    var released = false;
    late MusicResumeGuard guard;
    var plays = 0;

    guard = MusicResumeGuard(
      isMusicActive: () async => !released,
      sendPlay: () async => plays++,
      wait: (_) async {
        // Stands in for the next beat beginning during the settle window.
        await guard.beforeInterrupt();
      },
    );

    await guard.beforeInterrupt();
    released = true;
    expect(await guard.afterInterrupt(), isFalse);
    expect(plays, 0);
  });

  test('cancel drops a pending nudge', () async {
    final stream = FakeMusicStream([true, false]);
    final guard = guardFor(stream);

    await guard.beforeInterrupt();
    guard.cancel();
    expect(await guard.afterInterrupt(), isFalse);
    expect(stream.plays, 0);
  });

  test('a platform channel that throws is not fatal', () async {
    final guard = MusicResumeGuard(
      isMusicActive: () async => throw StateError('no channel'),
      sendPlay: () async {},
      wait: (_) async {},
    );

    await guard.beforeInterrupt();
    expect(await guard.afterInterrupt(), isFalse);
  });

  test('a failing play call is swallowed rather than breaking the beat', () async {
    var asked = 0;
    final guard = MusicResumeGuard(
      isMusicActive: () async => asked++ == 0,
      sendPlay: () async => throw StateError('no session'),
      wait: (_) async {},
    );

    await guard.beforeInterrupt();
    expect(await guard.afterInterrupt(), isFalse);
  });
}
