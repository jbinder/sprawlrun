import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/services/mission_notice.dart';

/// Whether the service survives a locked screen is not testable here. What is
/// testable: the run can never be *stopped* by this thing, and the service type
/// claimed at the start is never silently downgraded by a later tick — Android
/// would drop background location if it were.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.github.jbinder.sprawlrun/notifications');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  List<MethodCall> record() {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    return calls;
  }

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('start carries the text and the service type', () async {
    final calls = record();
    await MissionNotice.platform().start('24:00 left', tracking: true);

    expect(calls.single.method, 'startMissionNotice');
    expect(calls.single.arguments, {'text': '24:00 left', 'tracking': true});
  });

  test('an update keeps the type the run started with', () async {
    final calls = record();
    final notice = MissionNotice.platform();
    await notice.start('24:00 left', tracking: true);
    await notice.update('23:59 left');

    expect(calls.map((c) => c.method), ['startMissionNotice', 'updateMissionNotice']);
    expect(calls.last.arguments, {'text': '23:59 left', 'tracking': true});
  });

  test('a run started without location never claims to have it', () async {
    final calls = record();
    final notice = MissionNotice.platform();
    await notice.start('24:00 left', tracking: false);
    await notice.update('23:59 left');

    expect(calls.last.arguments, {'text': '23:59 left', 'tracking': false});
  });

  test('stop needs nothing from the caller', () async {
    final calls = record();
    await MissionNotice.platform().stop();
    expect(calls.single.method, 'stopMissionNotice');
  });

  test('a platform failure does not take the run down with it', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'no such service'),
    );

    final notice = MissionNotice.platform();
    await expectLater(notice.start('x', tracking: true), completes);
    await expectLater(notice.update('y'), completes);
    await expectLater(notice.stop(), completes);
  });

  test('no handler at all still completes', () async {
    await expectLater(MissionNotice.platform().start('x', tracking: false), completes);
  });

  test('non-Android platforms never call the channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final calls = record();
    await MissionNotice.platform().start('x', tracking: true);
    expect(calls, isEmpty);
  });
}
